-- Keep IDs, never engine pointers, across asynchronous representation changes.
return function(now, distance_mode)
    local id, phase, deadline, stable = nil, 0, 0, nil
    local baseline, before_mutation
    local function advance()
        phase, deadline, stable, baseline = phase + 1, now() + 20000, nil, nil
    end
    return function()
        if phase == 9 then return true end
        if phase == 0 then
            local actor = db.actor
            local item = assert(alife():create("bandage", actor:position(), actor:level_vertex_id(), actor:game_vertex_id(), actor:id()))
            id = item.id
            item = assert(alife():object(id)) -- create() returns the generic CSE_Abstract wrapper.
            item.m_flags:set(2, false) -- flSwitchOnline
            item.m_flags:set(4, true) -- flSwitchOffline
            assert(not item.m_flags:test(2) and item.m_flags:test(4), "Inventory permission setters failed")
            advance()
        end
        local item, client = alife():object(id), level.object_by_id(id)
        local matches
        if phase == 8 then
            matches = not item and not client
        else
            assert(item, "Inventory item disappeared")
            if phase == 1 then
                matches = item.parent_id == db.actor:id() and item.online and client ~= nil
            elseif phase == 2 or phase == 6 then
                matches = item.parent_id == 65535 and not item.online and not client
            else
                matches = item.parent_id == 65535 and item.online and client ~= nil
            end
        end
        assert(now() < deadline, "Ownership transition timed out in phase " .. phase)
        if matches then stable = stable or now() else stable, baseline = nil, nil end
        local reusable = phase == 3 or phase == 4 or phase == 5 or phase == 7
        -- Allow the first maintenance visit after a transition before comparing.
        if reusable and stable and now() - stable >= 1000 and not baseline then
            baseline = {decisions=item.representation_decisions, reuses=item.representation_reuses}
        end
        if stable and now() - stable >= 4000 then
            if reusable then
                assert(baseline, "Missing representation baseline")
                if distance_mode then
                    assert(item.representation_reuses == 0 and item.representation_decisions > baseline.decisions,
                        "Distance mode skipped reconciliation")
                else
                    assert(item.representation_reuses > baseline.reuses and item.representation_decisions == baseline.decisions,
                        "Native item did not reuse unchanged decision")
                end
                if before_mutation then
                    assert(item.representation_decisions > before_mutation, "Permission change did not invalidate decision")
                end
                log1(string.format("[regular representation] phase=%d decisions=%d reuses=%d", phase,
                    item.representation_decisions, item.representation_reuses))
            end
            log1(string.format("[regular] ownership_phase=%d id=%d", phase, id))
            if phase == 1 then db.actor:drop_item(client)
            elseif phase == 2 then item.m_flags:set(2, true)
            elseif phase == 3 then
                before_mutation = item.representation_decisions
                alife():set_switch_offline(id, false)
                assert(not item.m_flags:test(4), "Simulator permission setter failed")
            elseif phase == 4 then
                before_mutation = item.representation_decisions
                item.m_flags:set(4, true) -- Unnotified mutation must invalidate too.
            elseif phase == 5 then
                alife():set_switch_online(id, false)
            elseif phase == 6 then item.m_flags:set(2, true)
            elseif phase == 7 then alife():release(item, true)
            else log1("[regular] ownership_passed") end
            advance()
        end
        return phase == 9
    end
end
