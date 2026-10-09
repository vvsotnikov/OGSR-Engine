-- Exercise real server/client transitions without retaining engine pointers.
-- This NPC exists only in the disposable validation session.
return function(position, now)
    local id, phase, deadline, stable_since = nil, 0, 0, nil
    local function flags(online, offline)
        if phase < 5 then
            alife():set_switch_online(id, online)
            alife():set_switch_offline(id, offline)
        else
            local object = assert(alife():object(id))
            -- can_switch_* resolves to virtual Lua queries on these objects.
            -- Mutate the exposed flags directly, bypassing simulator setters.
            object.m_flags:set(2, online) -- CSE_ALifeObject::flSwitchOnline
            object.m_flags:set(4, offline) -- CSE_ALifeObject::flSwitchOffline
        end
        local object = assert(alife():object(id))
        assert(object.m_flags:test(2) == online, "Online permission setter did not change flSwitchOnline")
        assert(object.m_flags:test(4) == offline, "Offline permission setter did not change flSwitchOffline")
        deadline, stable_since = now() + 20000, nil
    end
    return function()
        if phase == 11 then return true end
        if not id then
            local object = assert(alife():create("stalker", level.vertex_position(position.node), position.node, position.graph))
            id = object.id
            assert(not object.online, "Creation unexpectedly synchronous")
            flags(false, true)
            phase = 1
        end
        local object = assert(alife():object(id), "Eligibility NPC disappeared")
        local client = level.object_by_id(id) ~= nil
        local step = (phase - 1) % 5 + 1
        local expected = step == 2 or step == 3 or step == 5
        local matches = object.online == expected and client == expected
        if phase == 1 or step == 3 then assert(matches, "Eligibility restriction violated") end
        assert(now() < deadline, "Eligibility transition timed out in phase " .. phase)
        if matches then stable_since = stable_since or now() else stable_since = nil end
        if stable_since and now() - stable_since >= 4000 then
            log1(string.format("[regular] eligibility_phase=%d id=%d online=%s client=%s", phase, id, tostring(object.online), tostring(client)))
            if step == 1 then flags(true, true)
            elseif step == 2 then flags(false, false) -- cannot-offline takes priority
            elseif step == 3 then flags(false, true)
            elseif step == 4 then flags(true, true)
            elseif phase == 5 then flags(false, true)
            else
                alife():release(object, true)
                log1("[regular] eligibility_passed")
            end
            phase = phase + 1
        end
        return phase == 11
    end
end
