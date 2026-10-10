-- The fixture creates world facts; only personal vision may teach the corpse.
return function(cfg)
    local state_path=getFS():update_path("$app_data_root$","npc-corpse-state.lua")
    local saved=io.open(state_path,"r")
    if saved then
        saved:close()
        local state=dofile(state_path)
        for key,value in pairs(state) do cfg[key]=value end
    end
    local refusal_waits,waiting_refusal=0,false
    local npc,body,item,rival = cfg.npc,cfg.body,cfg.item,cfg.rival
    local stage,started,since,finished = cfg.stage or 0,nil,nil,false
    local home,node,moved,attacked,fought,released,actor_position,corpse_time,reacted,extra,consumed,ordinary,ordinary_time,ordinary_refreshed
    local function object(id) return id and alife():object(id) end
    local function spawn(section,vertex,parent)
        return assert(alife():create(section,level.vertex_position(vertex),vertex,cross_table():vertex(vertex):game_vertex_id(),parent or 65535)).id
    end
    local function finish()
        if cfg.scenario=="corpse" or cfg.scenario=="corpse-empty" then assert(reacted,"Missing initial corpse danger reaction") end
        if cfg.scenario=="corpse-danger" then assert(ordinary_refreshed,"Legacy corpse danger did not refresh") end
        log1("[npc fixture] complete scenario=" .. cfg.scenario)
        finished=true; get_console():execute("quit")
    end
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now=device():time_global()
        if not started then
            started=now
            if stage==5 then
                assert(level.name()=="l02_garbage")
                home=vector():set(cfg.x,cfg.y,cfg.z)
                get_console():execute("g_god on"); level.disable_input()
                log1("[npc fixture] restored_pending")
            else
            assert(level.name()=="l05_bar")
            home=level.vertex_position(34548)
            node=level.vertex_in_direction(34548,vector():set(1,0,0),8)
            get_console():execute("g_god on"); level.disable_input()
            local graph=game_graph()
            local map=graph:vertex(cross_table():vertex(34548):game_vertex_id()):level_id()
            local clearance=15
            local radius=cfg.mode=="distance" and alife():switch_distance()*(1-system_ini():r_float("alife","switch_factor"))
            for id=0,graph:vertex_count()-1 do
                local vertex=graph:vertex(id)
                if vertex:level_id()==map and graph:accessible(id) then
                    local candidate=level.vertex_position(vertex:level_vertex_id())
                    local from_home=candidate:distance_to(home)
                    local from_body=candidate:distance_to(level.vertex_position(node))
                    local gap=math.min(from_home,from_body)
                    if gap>clearance and from_home<=60 and (not radius or (from_home+2<radius and from_body+2<radius)) then
                        actor_position,clearance=candidate,gap
                    end
                end
            end
            assert(actor_position,"No actor position clear of greeting and within the requested online range")
            local p=actor_position
            db.actor:set_actor_position(vector():set(p.x,p.y+1.1,p.z))
            if not body then body=spawn("stalker",node)
            else log1("[npc fixture] restored_pending") end
            end
        end
        assert(now-started<180000,"Corpse scenario timed out stage="..stage)
        local corpse=body and level.object_by_id(body)
        local legacy=ordinary and level.object_by_id(ordinary)
        if legacy and corpse then
            legacy:set_sight(corpse)
            local threat=legacy:best_danger()
            if threat and threat:type()==danger_object.entity_corpse and threat:object() and threat:object():id()==body then
                if ordinary_time and threat:time()>ordinary_time+1000 then ordinary_refreshed=true end
                ordinary_time=ordinary_time or threat:time()
            end
        end
        local observer=npc and level.object_by_id(npc)
        local danger=observer and observer:best_danger()
        if danger and danger:type()==danger_object.entity_corpse and danger:object() and danger:object():id()==body then
            assert(not corpse_time or corpse_time==danger:time(),"Repeated sight renewed the same corpse danger")
            corpse_time=danger:time()
            if observer:motivation_action_manager():current_action_id()==stalker_ids.action_danger_planner then reacted=true end
        end
        if stage==0 and corpse then
            corpse:kill(corpse); stage=1; since=now
        elseif stage==1 and now-since>4000 then
            assert(corpse and not corpse:alive())
            local remove={}
            corpse:iterate_inventory(function(_,it) if it:section()=="bandage" then remove[#remove+1]=it:id() end end,corpse)
            for _,id in ipairs(remove) do alife():release(object(id),true) end
            if cfg.scenario~="corpse-empty" then item=spawn("bandage",node,body) end
            if (cfg.scenario=="corpse-revisit" or cfg.scenario=="corpse-mixed" or cfg.scenario=="corpse-static") then extra=spawn(cfg.scenario=="corpse-static" and "npc_corpse_bandage" or "bandage",node,body) end
            stage=2; since=now
        elseif stage==2 and now-since>2000 then
            npc=spawn("npc_trip_stalker",34548); assert(alife():start_supply_goal(npc))
            if cfg.scenario=="corpse-competition" then
                rival=spawn("npc_trip_stalker",34548); assert(alife():start_supply_goal(rival))
            end
            if cfg.scenario=="corpse-danger" then ordinary=spawn("stalker",34548) end
            stage=3; since=now
        elseif stage==3 then
            local client=level.object_by_id(npc)
            if cfg.scenario=="corpse-rejected" or cfg.scenario=="corpse-mixed" or cfg.scenario=="corpse-static" then
                if not client or now-since<2000 then return end
                if extra and item>extra then item,extra=extra,item end
                local loot=assert(level.object_by_id(item))
                if cfg.scenario=="corpse-static" then
                    -- Change only this isolated process's fixture section after
                    -- spawning so native starter-inventory creation is unaffected.
                    local ini=system_ini()
                    local readonly=ini.readonly; ini.readonly=false
                    ini:w_bool(loot:section(),"can_take",false); ini.readonly=readonly
                else
                    local flags=loot:get_inventory_item_flags()
                    flags:set(global_flags.FCanTake,false)
                    loot:set_inventory_item_flags(flags)
                end
            end
            if client and corpse then client:set_sight(corpse) end
            if rival and corpse and level.object_by_id(rival) then level.object_by_id(rival):set_sight(corpse) end
            local phase=alife():supply_trip_phase(npc)
            if phase==0 or phase==1 then
                log1("[npc corpse fixture] discovered")
                if cfg.scenario=="corpse-removed" then
                    if item then alife():release(object(item),true); item=nil end
                    alife():release(object(body),true); body=nil
                elseif cfg.scenario=="corpse-offline" or cfg.scenario=="corpse-save" or cfg.scenario=="corpse-rejected-offline" then
                    local state=assert(io.open(state_path,"w"))
                    state:write(string.format("return {npc=%d,body=%d,item=%d,stage=5,x=%.9g,y=%.9g,z=%.9g}",npc,body,item,home.x,home.y,home.z))
                    state:close()
                    finished=true
                    get_console():execute("jump_to_level l02_garbage")
                    return
                end
                stage=4
            end
        elseif stage==4 or stage==5 then
            local server=assert(object(npc))
            local client=level.object_by_id(npc)
            local phase=alife():supply_trip_phase(npc)
            if cfg.scenario=="corpse-combat" and client then
                if not attacked then
                    attacked=now
                    client:set_goodwill(-10000,db.actor)
                    client:set_enemy_callback(function(_,enemy) return enemy:id()==db.actor:id() end)
                    local stimulus=hit()
                    stimulus.draftsman,stimulus.type,stimulus.power,stimulus.impulse=db.actor,hit.fire_wound,0.01,0
                    stimulus.direction=vector():set(1,0,0); client:hit(stimulus)
                end
                if client:best_enemy() then
                    fought=true
                    assert(object(item).parent_id==body,"Searched while combat owned execution")
                end
                if not released and now-attacked>20000 then
                    assert(fought,"No real combat interruption")
                    client:set_enemy_callback(function() return false end)
                    client:set_relation(game_object.neutral,db.actor)
                    local away=actor_position
                    db.actor:set_actor_position(vector():set(away.x,away.y+1.1,away.z))
                    released=true; log1("[npc fixture] combat_observed")
                end
            end
            assert(phase~=4 and phase~=5,"Goal failed")
            local here=client and client:position() or server.position
            if here:distance_to(home)>2 then moved=true end
            if cfg.scenario=="corpse-save" and not server.online and not object(body).online then
                local file=assert(io.open(getFS():update_path("$app_data_root$","npc-trip-ids.lua"),"w"))
                file:write(string.format("return {npc=%d,body=%d,item=%d,stage=5,x=%.9g,y=%.9g,z=%.9g}",npc,body,item,home.x,home.y,home.z)); file:close()
                finished=true; get_console():execute("save npc_trip_pending")
                log1("[npc fixture] saved_pending"); get_console():execute("quit"); return
            end
            if cfg.scenario=="corpse-empty" or cfg.scenario=="corpse-removed" then
                if moved and phase==6 then
                    since=since or now
                    if now-since>10000 then finish() end
                else since=now end
            elseif cfg.scenario=="corpse-rejected" or cfg.scenario=="corpse-rejected-offline" then
                assert(object(item).parent_id==body,"Refused item was transferred")
                if moved and phase==6 then
                    if not waiting_refusal then refusal_waits=refusal_waits+1; waiting_refusal=true; since=now end
                    if refusal_waits>=2 and now-since>10000 then finish() end
                else waiting_refusal=false; since=now end
            elseif rival then
                local parent=assert(object(item)).parent_id
                local other=parent==npc and rival or npc
                if ((parent==npc and phase==3) or (parent==rival and alife():supply_trip_phase(rival)==3)) and alife():supply_trip_phase(other)==6 then
                    local winner=assert(level.object_by_id(parent))
                    local loser=assert(level.object_by_id(other))
                    assert(winner:object("bandage") and not loser:object("bandage"),"Competition duplicated or lost loot")
                    finish()
                end
            elseif phase==3 and (not consumed or object(item).parent_id==npc) then
                if cfg.scenario=="corpse-mixed" or cfg.scenario=="corpse-static" then
                    assert(item<extra and object(item).parent_id==body and object(extra).parent_id==npc,"Locked item blocked acceptable loot")
                    assert(here:distance_to(home)<=1.6)
                    finish(); return
                end
                if cfg.scenario=="corpse-revisit" and not consumed and object(extra).parent_id==npc then item,extra=extra,item end
                assert(object(item).parent_id==npc and here:distance_to(home)<=1.6,"No real corpse loot/return")
                if cfg.scenario=="corpse-revisit" and not consumed then
                    assert(object(extra).parent_id==body,"Both bandages taken in one search")
                    local owned=assert(level.object_by_id(item))
                    client:eat(owned)
                    consumed=true; item=extra
                    log1("[npc corpse fixture] consumed_first_bandage")
                    return
                end
                if cfg.scenario=="corpse-combat" then assert(fought and released and not client:best_enemy()) end
                if cfg.scenario=="corpse-offline" or cfg.scenario=="corpse-resume" then assert(not server.online) end
                finish()
            end
        end
    end
    level.add_call(function()
        local ok,err=xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED "..tostring(err)); finished=true; get_console():execute("quit") end
        return false
    end,function() end)
end
