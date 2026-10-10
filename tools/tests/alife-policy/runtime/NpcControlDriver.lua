-- Exercise installed xr_motivator/xr_logic/xr_remark, without replacing their services.
return function(cfg)
    local npc,item = cfg.npc,cfg.item
    local stage,started,since,anchor = 0,nil,nil,nil
    local finished, sampled, other, returned = false,nil,nil,false
    local function path(name) return getFS():update_path("$app_data_root$",name) end
    local function switch(client,section)
        assert(xr_logic.switch_to_section(client,db.storage[npc],section))
    end
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now = device():time_global()
        local home = level.vertex_position(34548)
        if not started then
            started = now
            get_console():execute("g_god on"); level.disable_input()
            local actor_node = level.vertex_in_direction(34548,vector():set(-1,0,0),25)
            local actor_position = level.vertex_position(actor_node)
            db.actor:set_actor_position(vector():set(actor_position.x,actor_position.y+1.1,actor_position.z))
            if not npc then
                local node = level.vertex_in_direction(34548,vector():set(1,0,0),20)
                assert(home:distance_to(level.vertex_position(node)) > 8)
                local function spawn(section,vertex)
                    return assert(alife():create(section,level.vertex_position(vertex),vertex,cross_table():vertex(vertex):game_vertex_id())).id
                end
                npc,item = spawn("npc_trip_stalker",34548),spawn("bandage",node)
                if cfg.scenario == "control-meet" then other=spawn("npc_trip_stalker",level.vertex_in_direction(34548,vector():set(0,0,-1),20)) end
                assert(alife():start_supply_goal(npc))
                assert(alife():remember_supply(npc,item))
            else
                stage = 4
                since,anchor = now,alife():object(npc).position
                assert(not alife():object(npc).online,"Saved script owner unexpectedly online")
            end
        end
        assert(now-started < 240000,"Control test timed out stage="..stage)
        local server = alife():object(npc)
        if stage == 8 then
            if not server and not level.object_by_id(npc) and not db.storage[npc] then
                assert(alife():supply_trip_phase(npc) == -1,"Removed NPC retained planner binding")
                log1("[npc fixture] complete scenario="..cfg.scenario)
                finished = true; get_console():execute("quit")
            end
            return
        end
        assert(server)
        local client = level.object_by_id(npc)
        local manager = client and client:motivation_action_manager()
        local action = manager and manager:initialized() and manager:current_action_id() or nil
        local phase = alife():supply_trip_phase(npc)
        if not sampled or now-sampled > 2000 then
            sampled=now
            log1(string.format("[npc control] stage=%d phase=%d online=%s action=%s distance=%.2f",stage,phase,tostring(server.online),tostring(action),(client and client:position() or server.position):distance_to(home)))
        end
        assert(stage >= 7 or (phase ~= 4 and phase ~= 5),"Goal failed or died")
        if stage == 0 and client and db.storage[npc] then
            assert(db.storage[npc].ini and not db.storage[npc].active_section,"Spawn did not initialize planner-compatible logic")
            xr_logic.pstor_store(client,"npc_control_quest",42)
            stage = 1
        elseif stage == 1 and client and client:position():distance_to(home) > 2 then
            assert(client:is_trade_enabled(),"Trade disabled for planner NPC")
            if cfg.scenario == "control-meet" then
                xr_meet.init_meet(client,db.storage[npc].ini,"meet@fixture",db.storage[npc].meet,nil)
                db.actor:activate_slot(0)
                local pos = client:position()
                db.actor:set_actor_position(vector():set(pos.x,pos.y+1.1,pos.z+1))
                stage = 11
            else
                switch(client,"remark@hold")
                stage = 2
            end
        elseif stage == 2 and action == xr_actions_id.zmey_remark_base+1 then
            if not since then since,anchor = now,client:position() end
            assert(client:position():distance_to(anchor) < 1,"Planner moved a script-controlled NPC")
            assert(alife():object(item).parent_id == 65535,"Planner collected during script control")
            if now-since > 4000 then
                log1("[npc control] script_hold")
                alife():set_switch_online(npc,false)
                stage,since = 3,nil
            end
        elseif stage == 3 and not server.online and not client then
            if not since then since,anchor = now,server.position end
            assert(server.position:distance_to(anchor) < 0.1,"Offline planner stole script control")
            if now-since > 4000 then
                server.money = 1234567
                local file = assert(io.open(path("npc-trip-ids.lua"),"w"))
                file:write(string.format("return {npc=%d,item=%d}",npc,item)); file:close()
                finished = true
                get_console():execute("save npc_trip_pending")
                log1("[npc fixture] saved_pending")
                get_console():execute("quit")
            end
        elseif stage == 4 then
            assert(not server.online and not client)
            assert(server.position:distance_to(anchor) < 0.1,"Reload lost script suspension")
            assert(alife():object(item).parent_id == 65535)
            if now-since > 4000 then
                npc=npc_sim_test_cancel_spawn(alife(),npc)
                assert(npc ~= 65535,"Could not cancel queued client spawn")
                log1("[npc control] cancelled_pending_spawn")
                stage,since=14,now
            end
        elseif stage == 14 then
            assert(not server.online and not client)
            if now-since > 4000 then
                alife():set_switch_online(npc,true)
                stage=5
            end
        elseif stage == 5 and client and db.storage[npc] then
            assert(client:money() == 1234567,"Stale native client snapshot overwrote offline money")
            assert(xr_logic.pstor_retrieve(client,"npc_control_quest",0) == 42,"Binder lost quest state")
            assert(db.storage[npc].active_section == "remark@hold","Binder lost script activity")
            if action == xr_actions_id.zmey_remark_base+1 then
                log1("[npc control] restored_script_hold")
                switch(client,"nil")
                stage = 6
            end
        elseif stage == 6 and phase == 3 then
            assert(alife():object(item).parent_id == npc,"Released goal did not collect")
            assert(client and client:position():distance_to(home) < 1.6)
            assert(client:is_trade_enabled(),"Trade lost after reload/release")
            db.actor:activate_slot(0)
            local approach = level.vertex_in_direction(client:level_vertex_id(),vector():set(0,0,1),2)
            local pos = level.vertex_position(approach)
            db.actor:set_actor_position(vector():set(pos.x,pos.y+1.1,pos.z))
            stage = 9
        elseif stage == 9 and client:is_talk_enabled() then
            db.actor:run_talk_dialog(client)
            assert(db.actor:is_talking() and client:is_talking(),"Dialog did not start")
            assert(db.actor:get_talk_partner():id() == npc)
            db.actor:switch_to_trade()
            stage = 10
        elseif stage == 10 then
            assert(db.actor:is_trading(),"Trade UI did not start")
            db.actor:stop_talk()
            log1("[npc control] dialog_trade_passed")
            client:kill(db.actor)
            stage = 7
        elseif stage == 11 and action == xr_actions_id.stohe_meet_base+1 and client:is_talk_enabled() then
            assert(not db.storage[npc].active_section,"Meet unexpectedly claimed a persistent section")
            db.actor:run_talk_dialog(client)
            assert(client:is_talking(),"Mid-trip dialog did not start")
            db.actor:stop_talk()
            local ordinary = assert(level.object_by_id(other))
            xr_logic.pstor_store(ordinary,"npc_control_unenrolled",99)
            assert(alife():supply_trip_phase(other) == -1)
            alife():set_switch_online(npc,false)
            alife():set_switch_online(item,false)
            alife():set_switch_online(other,false)
            anchor,since,stage = client:position(),now,12
        elseif stage == 12 and not server.online and not client then
            if server.position:distance_to(anchor) > 2 then
                log1("[npc control] meet_released_offline")
                server.money = 1234567
                local pos=level.vertex_position(level.vertex_in_direction(34548,vector():set(-1,0,0),25))
                db.actor:set_actor_position(vector():set(pos.x,pos.y+1.1,pos.z))
                alife():set_switch_online(npc,true)
                alife():set_switch_online(item,true)
                alife():set_switch_online(other,true)
                stage=13
            end
        elseif stage == 13 and client and action then
            if not returned then
                -- The tested meet is over; prevent another greeting on the return leg.
                xr_meet.init_meet(client,db.storage[npc].ini,"no_meet",db.storage[npc].meet,nil)
                returned=true
            end
            local ordinary=level.object_by_id(other)
            if not ordinary or not db.storage[other] or not db.storage[other].ini then return end
            assert(xr_logic.pstor_retrieve(ordinary,"npc_control_unenrolled",0) == 0,"Unenrolled NPC retained nonstandard script snapshot")
            assert(client:money() == 1234567)
            assert(xr_logic.pstor_retrieve(client,"npc_control_quest",0) == 42)
            if phase == 3 then
                assert(alife():object(item).parent_id == npc)
                log1("[npc fixture] complete scenario="..cfg.scenario)
                finished=true; get_console():execute("quit")
            end
        elseif stage == 7 and client and not client:alive() then
            assert(db.storage[npc].death.killer == db.actor:id(),"Binder death callback missing")
            assert(phase == 5,"Native death did not end the goal")
            alife():release(server,true)
            stage = 8
        end
    end
    level.add_call(function()
        local ok,err = xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED "..tostring(err)); finished=true; get_console():execute("quit") end
        return false
    end,function() end)
end
