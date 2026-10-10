-- Real visibility supplies knowledge; this fixture never assigns a source.
return function(cfg)
    local npc,item = cfg.npc,cfg.item
    local stage,started,finished = cfg.stage or 0,nil,false
    local unseen_since,memory_since
    local home
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now = device():time_global()
        if not started then
            started = now
            home = level.vertex_position(34548)
            assert(level.name() == "l05_bar")
            get_console():execute("g_god on"); level.disable_input()
            local actor_node = level.vertex_in_direction(34548,vector():set(-1,0,0),25)
            local p = level.vertex_position(actor_node)
            db.actor:set_actor_position(vector():set(p.x,p.y+1.1,p.z))
            if not npc then
                local node = level.vertex_in_direction(34548,vector():set(1,0,0),8)
                assert(home:distance_to(level.vertex_position(node)) > 4,"No observation route")
                local function spawn(section,vertex)
                    return assert(alife():create(section,level.vertex_position(vertex),vertex,cross_table():vertex(vertex):game_vertex_id())).id
                end
                npc = spawn("npc_trip_stalker",34548)
                item = spawn("bandage",node)
                alife():set_switch_online(item,false)
                assert(alife():start_supply_goal(npc))
            else
                assert(stage == 3,"Invalid saved observation stage")
                log1("[npc fixture] restored_pending")
            end
        end
        assert(now-started < 150000,"Perception timed out stage=" .. stage)
        local server,supply = assert(alife():object(npc)),assert(alife():object(item))
        local client,visible_item = level.object_by_id(npc),level.object_by_id(item)
        local phase = alife():supply_trip_phase(npc)
        assert(phase ~= 4 and phase ~= 5,"Perception goal failed")
        if stage == 0 then
            if client then client:set_sight(look.direction,vector():set(-1,0,0),true) end
            assert(not supply.online and phase == 6,"Unseen supply became knowledge")
            if client and now-started > 5000 then
                log1("[npc perception fixture] unseen_wait")
                alife():set_switch_online(item,true)
                stage = 10
            end
        elseif stage == 10 then
            if client then client:set_sight(look.direction,vector():set(-1,0,0),true) end
            assert(phase == 6,"Online unseen supply became knowledge")
            if client and visible_item then
                assert(not client:see(visible_item),"Negative fixture item entered field of view")
                unseen_since = unseen_since or now
                if now-unseen_since > 5000 then
                    log1("[npc perception fixture] online_unseen")
                    if cfg.scenario == "perception-memory" then
                        assert(npc_sim_test_nonpersonal_memory(alife(),npc,item))
                        memory_since = now; stage = 11
                    else stage = 1 end
                end
            end
        elseif stage == 11 then
            if client then client:set_sight(look.direction,vector():set(-1,0,0),true) end
            assert(phase == 6,"Non-personal visual memory became supply knowledge")
            if now-memory_since > 5000 then
                log1("[npc perception fixture] nonpersonal_ignored")
                stage = 1
            end
        elseif stage == 1 then
            -- Looking is a physical action, not an injected memory or destination.
            if client and visible_item then client:set_sight(visible_item) end
            if phase == 0 or phase == 1 then
                log1("[npc perception fixture] discovered")
                if cfg.scenario == "perception-save" then
                    alife():set_switch_online(npc,false)
                    alife():set_switch_online(item,false)
                    stage = 2
                else stage = 4 end
            end
        elseif stage == 2 and not server.online and not supply.online then
            local file = assert(io.open(getFS():update_path("$app_data_root$","npc-trip-ids.lua"),"w"))
            file:write(string.format("return {npc=%d,item=%d,stage=3}",npc,item)); file:close()
            finished = true
            get_console():execute("save npc_trip_pending")
            log1("[npc fixture] saved_pending")
            get_console():execute("quit")
        elseif stage == 3 then
            assert(not server.online and not supply.online,"Remembered trip unexpectedly activated")
            if phase == 3 then stage = 4 end
        end
        if stage == 4 and phase == 3 then
            local here = client and client:position() or server.position
            assert(supply.parent_id == npc and here:distance_to(home) <= 1.6,"No actual pickup and return")
            log1("[npc fixture] complete scenario=" .. cfg.scenario)
            finished = true; get_console():execute("quit")
        end
    end
    level.add_call(function()
        local ok,err = xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED " .. tostring(err)); finished = true; get_console():execute("quit") end
        return false
    end,function() end)
end
