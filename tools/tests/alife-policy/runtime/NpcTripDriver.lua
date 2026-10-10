-- Enrolment and observations only: the production Rust/C++ planner chooses and
-- executes travel/pickup. The fixture never moves the NPC or grants its item.
return function(cfg)
    local npc_id, supply_id = cfg.npc, cfg.supply
    local started, sample, moved, saved, finished, attacked, fought, released_enemy
    local switching, switched, removed, killed, pushed, relocated
    local saw_online, saw_offline, mismatch_started, mismatch_released, elevated
    -- Navigable anchor in the installed vanilla Bar geometry, shared with the seed.
    local home_node, source_node = 34548, nil
    local home, actor_position
    local function path(name) return getFS():update_path("$app_data_root$", name) end
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now = device():time_global()
        if not started then
            started = now
            assert(level.name() == "l05_bar", "Expected Bar")
            home = level.vertex_position(home_node)
            get_console():execute("g_god on")
            level.disable_input()
            actor_position = home
            if cfg.scenario ~= "natural" then
                -- Exercise the assigned trip without a nearby actor holding meet control.
                local actor_node = level.vertex_in_direction(home_node,vector():set(-1,0,0),25)
                actor_position = level.vertex_position(actor_node)
            end
            db.actor:set_actor_position(vector():set(actor_position.x,actor_position.y+1.1,actor_position.z))
            if cfg.scenario == "natural" then alife():set_switch_distance(5) end
            local home_graph = cross_table():vertex(home_node):game_vertex_id()
            local best = 6
            for _, direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                for _, length in ipairs(cfg.scenario == "boundary" and {20,40,60} or {20}) do
                    local candidate = level.vertex_in_direction(home_node, vector():set(direction[1],0,direction[2]),length)
                    local distance = home:distance_to(level.vertex_position(candidate))
                    if distance > best and (cfg.scenario ~= "boundary" or cross_table():vertex(candidate):game_vertex_id() ~= home_graph) then source_node, best = candidate, distance end
                end
            end
            if cfg.scenario == "far" then
                source_node, best = nil, 30
                local graph = game_graph()
                local map = graph:vertex(home_graph):level_id()
                for id=0,graph:vertex_count()-1 do
                    local vertex = graph:vertex(id)
                    if vertex:level_id() == map and graph:accessible(id) then
                        local distance = home:distance_to(vertex:level_point())
                        if distance > best and distance <= 60 then source_node, best = vertex:level_vertex_id(), distance end
                    end
                end
            end
            assert(source_node, "No clear supply-trip route")
            if not npc_id then
                local source = level.vertex_position(source_node)
                if cfg.scenario == "elevated" then source.y = source.y + 2.4 end
                log1(string.format("[npc fixture] route home_graph=%d source_graph=%d",home_graph,cross_table():vertex(source_node):game_vertex_id()))
                supply_id = assert(alife():create(cfg.scenario == "elevated" and "npc_trip_elevated_bandage" or "bandage", source, source_node, cross_table():vertex(source_node):game_vertex_id())).id
                npc_id = assert(alife():create("npc_trip_stalker", home, home_node, cross_table():vertex(home_node):game_vertex_id())).id
                assert(alife():start_supply_trip(npc_id,supply_id), "Planner enrolment rejected")
                local file = assert(io.open(path("npc-trip-ids.lua"),"w"))
                file:write(string.format("return {npc=%d,supply=%d}",npc_id,supply_id)); file:close()
                if cfg.scenario == "mismatch" then alife():set_switch_online(supply_id,false) end
                if cfg.scenario == "offline" then
                    alife():set_switch_online(npc_id,false)
                    alife():set_switch_online(supply_id,false)
                end
            else
                local restored = alife():supply_trip_phase(npc_id)
                assert((cfg.scenario == "fallback" and restored == -1) or (cfg.scenario == "resume" and restored >= 0 and restored <= 2), "Unexpected restored owner")
                log1("[npc fixture] restored_pending")
            end
            log1(string.format("[npc fixture] start scenario=%s npc=%d supply=%d",cfg.scenario,npc_id,supply_id))
        end
        assert(now-started < (cfg.scenario == "far" and 600000 or 240000), "Trip timed out")
        local server = assert(alife():object(npc_id), "NPC missing")
        local supply = alife():object(supply_id)
        assert(supply or cfg.scenario == "missing", "Supply missing")
        local client = level.object_by_id(npc_id)
        local phase = alife():supply_trip_phase(npc_id)
        if ((cfg.scenario == "missing" or cfg.scenario == "moved") and phase == 4) or (cfg.scenario == "death" and phase == 5) then
            assert((removed and not supply) or (relocated and supply.parent_id == 65535) or (killed and not client:alive()), "Missing terminal cause")
            log1("[npc fixture] complete scenario=" .. cfg.scenario)
            finished = true
            get_console():execute("quit")
            return
        end
        if cfg.scenario == "fallback" then
            assert(phase == -1, "Removed opt-in still owns the NPC")
            if client and now-started > 3000 then
                assert(client:is_talk_enabled(), "Ordinary dialog control was not restored")
                log1("[npc fixture] complete scenario=fallback")
                finished = true; get_console():execute("quit")
            end
            return
        end
        assert(phase >= 0 and phase <= 3, "Planner failed or NPC died: " .. phase)
        if client and cfg.scenario ~= "interrupt" and cfg.scenario ~= "spawn-combat" and cfg.scenario ~= "death" then
            assert(client:is_talk_enabled(), "Planner disabled ordinary dialogs")
        end
        if server.online then saw_online = true elseif saw_online then saw_offline = true end
        if cfg.scenario == "mismatch" and phase == 1 and not mismatch_released then
            assert(server.online and not supply.online, "Expected mixed representation")
            mismatch_started = mismatch_started or now
            if now-mismatch_started > 6000 then
                alife():set_switch_online(supply_id,true)
                mismatch_released = true
                log1("[npc fixture] mismatch_waited")
            end
        end
        if cfg.scenario == "elevated" and not elevated then
            local item = level.object_by_id(supply_id)
            if item and item:get_physics_shell() then
                item:get_physics_shell():freeze()
                assert(item:position().y-level.vertex_position(source_node).y > 2.0, "Supply fell before elevated test")
                elevated = true
            end
        end
        if cfg.scenario == "moved" then
            local item = level.object_by_id(supply_id)
            if item and item:get_physics_shell() then
                if not pushed then
                    local shell = item:get_physics_shell()
                    shell:Enable()
                    item:set_const_force(vector():set(0,1,0), shell:get_element_by_order(0):get_mass()*40, 1000)
                    pushed = true
                end
                if not relocated and item:position():distance_to(supply.position) > 1.5 then
                    item:get_physics_shell():freeze()
                    relocated = true
                    log1("[npc fixture] live_item_displaced")
                end
            end
        end
        local here = client and client:position() or server.position
        if here:distance_to(home) > 2 then moved = true end
        if not sample or now-sample >= 1000 then
            sample = now
            log1(string.format("[npc fixture] sample phase=%d online=%s distance_home=%.3f parent=%d graph=%d",phase,tostring(server.online),here:distance_to(home),supply and supply.parent_id or 65535,client and client:game_vertex_id() or server.m_game_vertex_id))
        end
        if cfg.scenario == "missing" and moved and not removed then
            alife():release(supply,true)
            removed = true
        end
        if cfg.scenario == "death" and moved and client and not killed then
            client:kill(db.actor)
            killed = true
        end
        if cfg.scenario == "switch" and moved and not switched then
            if not switching then
                alife():set_switch_online(npc_id,false)
                alife():set_switch_online(supply_id,false)
                switching = true
            elseif not server.online and not client then
                log1("[npc fixture] observed_offline")
                alife():set_switch_online(npc_id,true)
                alife():set_switch_online(supply_id,true)
                switched = true
            end
        end
        if cfg.scenario == "save" and moved and phase == 0 and not saved then
            saved, finished = true, true
            get_console():execute("save npc_trip_pending")
            log1("[npc fixture] saved_pending")
            get_console():execute("quit")
            return
        end
        if (cfg.scenario == "interrupt" or cfg.scenario == "spawn-combat") and client then
            if (moved or cfg.scenario == "spawn-combat") and not attacked then
                attacked = now
                db.actor:set_actor_position(vector():set(home.x,home.y+1.1,home.z))
                client:set_goodwill(-10000,db.actor)
                client:set_enemy_callback(function(_, enemy) return enemy:id() == db.actor:id() end)
                local stimulus = hit()
                stimulus.draftsman, stimulus.type, stimulus.power, stimulus.impulse = db.actor, hit.fire_wound, 0.01, 0
                stimulus.direction = vector():set(1,0,0)
                client:hit(stimulus)
            end
            if attacked and client:best_enemy() then fought = true end
            if attacked and now-attacked > 70000 and not released_enemy then
                assert(fought, "Combat interruption was not observed")
                client:set_enemy_callback(function() return false end)
                client:set_relation(game_object.neutral,db.actor)
                db.actor:set_actor_position(vector():set(actor_position.x,actor_position.y+1.1,actor_position.z))
                released_enemy = true
                log1("[npc fixture] combat_observed")
            end
        end
        if phase == 3 then
            if cfg.scenario == "natural" then
                assert(saw_online and saw_offline, "No natural representation transition")
                if not client or not server.online then return end
            end
            if cfg.scenario == "mismatch" then assert(mismatch_released, "Mixed pickup was not exercised") end
            if cfg.scenario == "elevated" then assert(elevated, "Missing elevated supply") end
            assert(cfg.scenario ~= "missing" and cfg.scenario ~= "moved" and cfg.scenario ~= "death", "Unexpected successful trip")
            assert(moved or cfg.scenario == "resume", "NPC never left home")
            assert(supply.parent_id == npc_id, "Completed without owning supply")
            assert(here:distance_to(home) <= 1.6, "Completed away from home")
            if cfg.scenario == "interrupt" or cfg.scenario == "spawn-combat" then assert(fought and released_enemy, "No completed combat interruption") end
            if cfg.scenario == "switch" then assert(switched and server.online and client, "Missing representation round trip") end
            if cfg.scenario == "offline" then assert(not server.online and not client, "Offline scenario went online") end
            log1("[npc fixture] complete scenario=" .. cfg.scenario)
            finished = true
            get_console():execute("quit")
        end
    end
    level.add_call(function()
        local ok, err = xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED " .. tostring(err)); finished=true; get_console():execute("quit") end
        return false
    end,function() end)
end
