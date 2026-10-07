-- Exercise real server/client transitions without retaining engine pointers.
-- This NPC exists only in the disposable validation session.
return function(position, now)
    local id, phase, deadline, stable_since = nil, 0, 0, nil
    local function flags(online, offline)
        alife():set_switch_online(id, online)
        alife():set_switch_offline(id, offline)
        deadline, stable_since = now() + 20000, nil
    end
    return function()
        if phase == 6 then return true end
        if not id then
            local object = assert(alife():create("stalker", level.vertex_position(position.node), position.node, position.graph))
            id = object.id
            assert(not object.online, "Creation unexpectedly synchronous")
            flags(false, true)
            phase = 1
        end
        local object = assert(alife():object(id), "Eligibility NPC disappeared")
        local client = level.object_by_id(id) ~= nil
        local expected = phase == 2 or phase == 3 or phase == 5
        local matches = object.online == expected and client == expected
        if phase == 1 or phase == 3 then assert(matches, "Eligibility restriction violated") end
        assert(now() < deadline, "Eligibility transition timed out in phase " .. phase)
        if matches then stable_since = stable_since or now() else stable_since = nil end
        if stable_since and now() - stable_since >= 4000 then
            log1(string.format("[regular] eligibility_phase=%d id=%d online=%s client=%s", phase, id, tostring(object.online), tostring(client)))
            if phase == 1 then flags(true, true)
            elseif phase == 2 then flags(false, false) -- cannot-offline takes priority
            elseif phase == 3 then flags(false, true)
            elseif phase == 4 then flags(true, true)
            else log1("[regular] eligibility_passed") end
            phase = phase + 1
        end
        return phase == 6
    end
end
