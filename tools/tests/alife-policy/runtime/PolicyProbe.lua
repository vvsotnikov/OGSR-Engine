-- Prove the loaded level's policy with a live NPC beyond both distance gates.
return function(now, mode)
    alife():set_switch_distance(20)
    local limit = 20 * (1 + system_ini():r_float("alife", "switch_factor"))
    local best_distance = limit + 80
    local graph = game_graph()
    local current_level = graph:vertex(db.actor:game_vertex_id()):level_id()
    local selected, node = nil, nil
    for candidate = 0, level.vertex_count() - 1 do
        local distance = level.vertex_position(candidate):distance_to(db.actor:position())
        if level.is_accessible_vertex_id(candidate) and distance > best_distance then
            local id = cross_table():vertex(candidate):game_vertex_id()
            if graph:valid_vertex_id(id) and graph:vertex(id):level_id() == current_level then
                selected, node = id, candidate
                best_distance = distance
            end
        end
    end
    assert(selected, "No distant navigation vertex for policy probe")
    local object = assert(alife():create("stalker", level.vertex_position(node), node, selected))
    local id, start, stable, sample = object.id, now(), nil, 0
    alife():set_switch_online(id, true)
    alife():set_switch_offline(id, true)
    return function()
        local object = assert(alife():object(id), "Policy probe disappeared")
        local distance = object.position:distance_to(db.actor:position())
        assert(distance > limit, "Policy probe inconclusive: actor or NPC moved inside the actual distance gate")
        local expected = mode == "whole-map"
        if now() >= sample then
            log1(string.format("[policy probe state] mode=%s id=%d distance=%.3f online=%s client=%s", mode, id, distance, tostring(object.online), tostring(level.object_by_id(id) ~= nil)))
            sample = now() + 5000
        end
        local matches = object.online == expected and (level.object_by_id(id) ~= nil) == expected
        if matches then stable = stable or now() else stable = nil end
        assert(now() - start < 30000, "Policy probe timed out")
        if now() - start >= 15000 and stable and now() - stable >= 5000 then
            log1(string.format("[policy probe] mode=%s id=%d distance=%.3f limit=%.3f online=%s", mode, id, distance, limit, tostring(object.online)))
            return true
        end
        return false
    end
end
