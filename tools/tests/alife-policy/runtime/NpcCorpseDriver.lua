-- The fixture creates world facts; only personal vision may teach the corpse.
return function(cfg)
    local state_path=getFS():update_path("$app_data_root$","npc-corpse-state.lua")
    local saved=io.open(state_path,"r")
    if saved then
        saved:close()
        local state=dofile(state_path)
        for key,value in pairs(state) do cfg[key]=value end
    end
    local npc,body,item,rival = cfg.npc,cfg.body,cfg.item,cfg.rival
    local stage,started,since,finished = cfg.stage or 0,nil,nil,false
    local home,node,moved,sampled,attacked,fought,released
    local function object(id) return id and alife():object(id) end
    local function spawn(section,vertex,parent)
        return assert(alife():create(section,level.vertex_position(vertex),vertex,cross_table():vertex(vertex):game_vertex_id(),parent or 65535)).id
    end
    local function finish()
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
            local p=level.vertex_position(level.vertex_in_direction(34548,vector():set(-1,0,0),60))
            db.actor:set_actor_position(vector():set(p.x,p.y+1.1,p.z))
            if not body then body=spawn("stalker",node)
            else log1("[npc fixture] restored_pending") end
            end
        end
        assert(now-started<180000,"Corpse scenario timed out stage="..stage)
        local corpse=body and level.object_by_id(body)
        if stage==0 and corpse then
            corpse:kill(corpse); stage=1; since=now
        elseif stage==1 and now-since>4000 then
            assert(corpse and not corpse:alive())
            local remove={}
            corpse:iterate_inventory(function(_,it) if it:section()=="bandage" then remove[#remove+1]=it:id() end end,corpse)
            for _,id in ipairs(remove) do alife():release(object(id),true) end
            if cfg.scenario~="corpse-empty" then item=spawn("bandage",node,body) end
            stage=2; since=now
        elseif stage==2 and now-since>2000 then
            npc=spawn("npc_trip_stalker",34548); assert(alife():start_supply_goal(npc))
            if cfg.scenario=="corpse-competition" then
                rival=spawn("npc_trip_stalker",34548); assert(alife():start_supply_goal(rival))
            end
            stage=3
        elseif stage==3 then
            local client=level.object_by_id(npc)
            if client and corpse then client:set_sight(corpse) end
            if rival and corpse and level.object_by_id(rival) then level.object_by_id(rival):set_sight(corpse) end
            local phase=alife():supply_trip_phase(npc)
            if client and (not sampled or now-sampled>3000) then
                sampled=now
                log1(string.format("[npc corpse fixture] sample phase=%d action=%d danger=%s enemy=%s distance=%.2f",phase,
                    client:motivation_action_manager():current_action_id(),tostring(client:best_danger() and (tostring(client:best_danger():type()).."/"..client:best_danger():time().."/"..tostring(client:best_danger():object() and client:best_danger():object():id()))),tostring(client:best_enemy()),client:position():distance_to(home)))
            end
            if phase==0 or phase==1 then
                log1("[npc corpse fixture] discovered")
                if cfg.scenario=="corpse-removed" then
                    if item then alife():release(object(item),true); item=nil end
                    alife():release(object(body),true); body=nil
                elseif cfg.scenario=="corpse-offline" or cfg.scenario=="corpse-save" then
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
            if client and (not sampled or now-sampled>3000) then
                sampled=now
                log1(string.format("[npc corpse fixture] sample phase=%d action=%d danger=%s enemy=%s distance=%.2f",phase,
                    client:motivation_action_manager():current_action_id(),tostring(client:best_danger() and (tostring(client:best_danger():type()).."/"..client:best_danger():time().."/"..tostring(client:best_danger():object() and client:best_danger():object():id()))),tostring(client:best_enemy()),client:position():distance_to(home)))
            end
            if not client and (not sampled or now-sampled>3000) then
                sampled=now
                log1(string.format("[npc corpse fixture] offline phase=%d body_online=%s item_online=%s parent=%s distance=%.2f",phase,
                    tostring(object(body) and object(body).online),tostring(object(item) and object(item).online),
                    tostring(object(item) and object(item).parent_id),object(body) and server.position:distance_to(object(body).position) or -1))
            end
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
                    local away=level.vertex_position(0)
                    assert(away:distance_to(client:position())>40,"Actor retreat is too close")
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
            elseif rival then
                local parent=assert(object(item)).parent_id
                local other=parent==npc and rival or npc
                if ((parent==npc and phase==3) or (parent==rival and alife():supply_trip_phase(rival)==3)) and alife():supply_trip_phase(other)==6 then
                    local winner=assert(level.object_by_id(parent))
                    local loser=assert(level.object_by_id(other))
                    assert(winner:object("bandage") and not loser:object("bandage"),"Competition duplicated or lost loot")
                    finish()
                end
            elseif phase==3 then
                assert(object(item).parent_id==npc and here:distance_to(home)<=1.6,"No real corpse loot/return")
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
