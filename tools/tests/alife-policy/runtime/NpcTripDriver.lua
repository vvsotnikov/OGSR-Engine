-- Enrolment and observations only: the production Rust/C++ planner chooses and
-- executes travel/pickup. The fixture never moves the NPC or grants its item.
return function(cfg)
    local npc_id, supply_id = cfg.npc, cfg.supply
    local started, sample, moved, saved, finished, attacked, fought, released_enemy
    local switching, switched, removed, killed
    local home_node, source_node = 34548, nil
    local home
    local function path(name) return getFS():update_path("$app_data_root$", name) end
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now = device():time_global()
        if not started then
            started = now
            assert(level.name() == "l05_bar", "Expected Bar")
            home = level.vertex_position(home_node)
            get_console():execute("g_god on")
            local best = 6
            for _, direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local candidate = level.vertex_in_direction(home_node, vector():set(direction[1],0,direction[2]),20)
                local distance = home:distance_to(level.vertex_position(candidate))
                if distance > best then source_node, best = candidate, distance end
            end
            assert(source_node, "No clear supply-trip route")
            if not npc_id then
                local source = level.vertex_position(source_node)
                supply_id = assert(alife():create("bandage", source, source_node, cross_table():vertex(source_node):game_vertex_id())).id
                npc_id = assert(alife():create("npc_trip_stalker", home, home_node, cross_table():vertex(home_node):game_vertex_id())).id
                assert(alife():start_supply_trip(npc_id,supply_id), "Planner enrolment rejected")
                local file = assert(io.open(path("npc-trip-ids.lua"),"w"))
                file:write(string.format("return {npc=%d,supply=%d}",npc_id,supply_id)); file:close()
                if cfg.scenario == "offline" then
                    alife():set_switch_online(npc_id,false)
                    alife():set_switch_online(supply_id,false)
                end
            else
                assert(alife():supply_trip_phase(npc_id) <= 2, "Restored trip is missing or already terminal")
                log1("[npc fixture] restored_pending")
            end
            log1(string.format("[npc fixture] start scenario=%s npc=%d supply=%d",cfg.scenario,npc_id,supply_id))
        end
        assert(now-started < 240000, "Trip timed out")
        local server = assert(alife():object(npc_id), "NPC missing")
        local supply = alife():object(supply_id)
        assert(supply or cfg.scenario == "missing", "Supply missing")
        local client = level.object_by_id(npc_id)
        local phase = alife():supply_trip_phase(npc_id)
        if (cfg.scenario == "missing" and phase == 4) or (cfg.scenario == "death" and phase == 5) then
            assert((removed and not supply) or (killed and not client:alive()), "Missing terminal cause")
            log1("[npc fixture] complete scenario=" .. cfg.scenario)
            finished = true
            get_console():execute("quit")
            return
        end
        assert(phase <= 3, "Planner failed or NPC died: " .. phase)
        local here = client and client:position() or server.position
        if here:distance_to(home) > 2 then moved = true end
        if not sample or now-sample >= 1000 then
            sample = now
            log1(string.format("[npc fixture] sample phase=%d online=%s distance_home=%.3f parent=%d",phase,tostring(server.online),here:distance_to(home),supply and supply.parent_id or 65535))
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
        if cfg.scenario == "interrupt" and client then
            if moved and not attacked then
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
            if attacked and now-attacked > 8000 and not released_enemy then
                assert(fought, "Combat interruption was not observed")
                client:set_enemy_callback(function() return false end)
                client:set_relation(game_object.neutral,db.actor)
                released_enemy = true
                log1("[npc fixture] combat_observed")
            end
        end
        if phase == 3 then
            assert(cfg.scenario ~= "missing" and cfg.scenario ~= "death", "Unexpected successful trip")
            assert(moved or cfg.scenario == "resume", "NPC never left home")
            assert(supply.parent_id == npc_id, "Completed without owning supply")
            assert(here:distance_to(home) <= 1.6, "Completed away from home")
            if cfg.scenario == "interrupt" then assert(fought and released_enemy, "No completed combat interruption") end
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
