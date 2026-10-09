-- Keep IDs, never engine pointers, across asynchronous representation changes.
return function(now)
    local id, phase, deadline, stable = nil, 0, 0, nil
    local function advance()
        phase, deadline, stable = phase + 1, now() + 20000, nil
    end
    return function()
        if phase == 5 then return true end
        if phase == 0 then
            local actor = db.actor
            local item = assert(alife():create("bandage", actor:position(), actor:level_vertex_id(), actor:game_vertex_id(), actor:id()))
            id = item.id
            item:can_switch_online(false)
            item:can_switch_offline(true)
            advance()
        end
        local item, client = alife():object(id), level.object_by_id(id)
        local matches
        if phase == 4 then
            matches = not item and not client
        else
            assert(item, "Inventory item disappeared")
            if phase == 1 then
                matches = item.parent_id == db.actor:id() and item.online and client ~= nil
            elseif phase == 2 then
                matches = item.parent_id == 65535 and not item.online and not client
            else
                matches = item.parent_id == 65535 and item.online and client ~= nil
            end
        end
        assert(now() < deadline, "Ownership transition timed out in phase " .. phase)
        if matches then stable = stable or now() else stable = nil end
        if stable and now() - stable >= 4000 then
            log1(string.format("[regular] ownership_phase=%d id=%d", phase, id))
            if phase == 1 then db.actor:drop_item(client)
            elseif phase == 2 then item:can_switch_online(true)
            elseif phase == 3 then alife():release(item, true)
            else log1("[regular] ownership_passed") end
            advance()
        end
        return phase == 5
    end
end
