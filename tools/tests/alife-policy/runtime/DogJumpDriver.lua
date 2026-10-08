return function(cfg)
    local start, spawned, done, sampled
    local node, graph, target
    local assigned = {}
    level.add_call(function()
        if done or not db.actor or not app_ready() or device().precache_frame ~= 0 then return false end
        local ok, err = xpcall(function()
            local now = device():time_global()
            if not start then
                start = now
                assert(level.name() == "l05_bar", "Expected Bar fixture")
                local anchor = level.vertex_position(34548)
                node = level.vertex_in_direction(34548, vector():set(1, 0, 0), 4)
                graph = cross_table():vertex(node):game_vertex_id()
                target = vector():set(anchor.x, anchor.y + 1.1, anchor.z)
            end
            get_console():execute("g_god on")
            db.actor:set_actor_position(target)
            if now - start < 3000 then return end
            if not spawned then
                spawned = {}
                log1("[dog fixture] begin section=" .. cfg.section)
                -- A lone dog can panic instead of attacking a stronger actor.
                for i = 1, 3 do
                    local id = assert(alife():create(cfg.section, level.vertex_position(node), node, graph)).id
                    spawned[i] = id
                    log1(string.format("[dog fixture] spawned id=%d section=%s", id, cfg.section))
                end
            end
            for _,id in ipairs(spawned) do
                local member = level.object_by_id(id)
                if member and not assigned[id] then
                    member:set_enemy_callback(function(_, enemy) return enemy:id() == db.actor:id() end)
                    local stimulus = hit()
                    stimulus.draftsman = db.actor
                    stimulus.type = hit.fire_wound
                    stimulus.power = 0.01
                    stimulus.impulse = 0
                    stimulus.direction = vector():set(1, 0, 0)
                    member:hit(stimulus)
                    assigned[id] = true
                end
            end
            local dog = level.object_by_id(spawned[1])
            if dog and (not sampled or now - sampled > 5000) then
                sampled = now
                local pos, enemy = dog:position(), dog:get_enemy()
                log1(string.format("[dog fixture] sample pos=%.2f,%.2f,%.2f actor=%.2f,%.2f,%.2f enemy=%s", pos.x,pos.y,pos.z,target.x,target.y,target.z,enemy and tostring(enemy:id()) or "none"))
            end
            if now - start > 33000 then
                for _,id in ipairs(spawned) do
                    assert(level.object_by_id(id) and level.object_by_id(id):alive(), "Test dog died or disappeared")
                end
                log1("[dog fixture] complete")
                done = true
                get_console():execute("quit")
            end
        end, debug.traceback)
        if not ok then
            done = true
            log1("[dog fixture] FAILED " .. err)
            get_console():execute("quit")
        end
        return false
    end, function() end)
end
