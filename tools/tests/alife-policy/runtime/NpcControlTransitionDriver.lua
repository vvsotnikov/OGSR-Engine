return function(cfg)
    local function path(name) return getFS():update_path("$app_data_root$",name) end
    local state_file = path("npc-control-transition.lua")
    local file = io.open(state_file,"r")
    local state = {phase=1}
    if file then file:close(); state=dofile(state_file) end
    local started, since, sent, released = nil,nil,false,false
    local function next_phase()
        state.phase=state.phase+1
        local output=assert(io.open(state_file,"w"))
        output:write(string.format("return {phase=%d,npc=%d,item=%d,x=%.9g,y=%.9g,z=%.9g}",state.phase,state.npc,state.item,state.x,state.y,state.z))
        output:close()
        sent=true
    end
    local function depart(map)
        next_phase()
        get_console():execute("jump_to_level "..map)
    end
    local function tick()
        if sent or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now=device():time_global()
        if not started then
            started=now
            get_console():execute("g_god on"); level.disable_input()
            assert(level.name() == (state.phase == 2 and "l02_garbage" or "l05_bar"))
            if state.phase ~= 2 then
                local node=level.vertex_in_direction(34548,vector():set(-1,0,0),25)
                local p=level.vertex_position(node)
                db.actor:set_actor_position(vector():set(p.x,p.y+1.1,p.z))
            end
            if state.phase == 1 then
                local function spawn(section,node)
                    return assert(alife():create(section,level.vertex_position(node),node,cross_table():vertex(node):game_vertex_id())).id
                end
                state.npc=spawn("npc_trip_stalker",34548)
                state.item=spawn("bandage",level.vertex_in_direction(34548,vector():set(1,0,0),20))
                assert(alife():start_supply_goal(state.npc))
                assert(alife():remember_supply(state.npc,state.item))
            end
        end
        assert(now-started < 120000,"Level-change control scenario timed out")
        local server=assert(alife():object(state.npc))
        local client=level.object_by_id(state.npc)
        assert(server:smart_terrain_id() == 65535,"Planner NPC acquired a smart-terrain assignment")
        if state.phase == 1 then
            if not client or not db.storage[state.npc] or not db.storage[state.npc].ini then return end
            if not since then
                if client:position():distance_to(level.vertex_position(34548)) < 2 then return end
                assert(not db.storage[state.npc].active_section)
                xr_logic.pstor_store(client,"npc_control_quest",42)
                assert(xr_logic.switch_to_section(client,db.storage[state.npc],"remark@hold"))
                since=now
            elseif now-since > 4000 then
                local p=client:position(); state.x,state.y,state.z=p.x,p.y,p.z
                log1("[npc control] departing_online_with_script_owner")
                depart("l02_garbage")
            end
        elseif state.phase == 2 then
            assert(not server.online and not client,"Previous-map NPC remained online")
            assert(server.position:distance_to(vector():set(state.x,state.y,state.z)) < 1,"Off-map planner stole script control")
            assert(alife():object(state.item).parent_id == 65535)
            if now-started > 5000 then
                server.money=1234567
                log1("[npc control] off_map_script_hold")
                depart("l05_bar")
            end
        elseif state.phase >= 3 and client and db.storage[state.npc] and db.storage[state.npc].ini then
            if not released then
                assert(xr_logic.pstor_retrieve(client,"npc_control_quest",0) == 42,"Level transition lost quest state")
                assert(db.storage[state.npc].active_section == "remark@hold","Level transition lost script owner")
                assert(client:money() == 1234567,"Off-map money was overwritten")
                if state.phase == 3 then
                    log1("[npc control] returned_with_script_state")
                    next_phase()
                    get_console():execute("save npc_control_online")
                    get_console():execute("load npc_control_online")
                    return
                end
                log1("[npc control] online_reload_preserved_script_state")
                assert(xr_logic.switch_to_section(client,db.storage[state.npc],"nil"))
                released=true
            end
            if alife():supply_trip_phase(state.npc) == 3 then
                assert(alife():object(state.item).parent_id == state.npc)
                assert(client:position():distance_to(level.vertex_position(34548)) < 1.6)
                log1("[npc fixture] complete scenario=control-transition")
                sent=true; get_console():execute("quit")
            end
        end
    end
    level.add_call(function()
        local ok,err=xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED "..tostring(err)); sent=true; get_console():execute("quit") end
        return false
    end,function() end)
end
