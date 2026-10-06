-- Uses saved ON_OFF_G membership, never substitutes engine group operations.
return function(cfg)
    local phase, start, stable, deadline, killed, done = 1, nil, nil, nil, nil, false
    local function members(group)
        -- CSE_ALifeOnlineOfflineGroup::STATE_Write ends with u32 count and u16 member IDs.
        local packet = net_packet()
        packet:w_begin(0)
        group:STATE_Write(packet)
        return packet
    end
    local function begin_phase()
        local now = device():time_global()
        stable, deadline = nil, now + 30000
        alife():set_switch_online(cfg.group, phase ~= 4 and phase ~= 6)
        alife():set_switch_offline(cfg.group, phase ~= 7)
        alife():set_switch_distance((phase == 2 or phase == 4 or phase == 5 or phase == 8) and 10000 or 1)
    end
    level.add_call(function()
        if done or not db.actor or not app_ready() or device().precache_frame ~= 0 then return false end
        local ok, err = xpcall(function()
            local now = device():time_global()
            if not start then
                start = now
                get_console():execute("g_god on")
                begin_phase()
            end
            if now - start < 15000 then return end
            local group = alife():object(cfg.group)
            local member = assert(alife():object(cfg.member), "Saved group member disappeared")
            local client = level.object_by_id(cfg.member)
            if killed then
                assert(now < deadline, "Group member removal timed out")
                if now - killed < 4000 then return end
                assert(client and not client:alive(), "Member did not die")
                if group then
                    local packet = members(group)
                    packet:r_seek(packet:w_tell() - 4)
                    assert(packet:r_u32() == 0, "Dead member remains registered")
                end
                log1("[group policy] complete member_dead=true group_empty=true")
                done = true
                get_console():execute("quit")
                return
            end
            assert(group, "Saved group disappeared")
            local packet = members(group)
            packet:r_seek(packet:w_tell() - 6)
            assert(packet:r_u32() == 1 and packet:r_u16() == cfg.member, "Saved group membership changed")
            assert(now < deadline, "Group policy phase timed out: " .. phase)
            local expected = phase == 2 or phase == 5 or phase == 7 or phase == 8 or (cfg.mode == "whole-map" and phase ~= 4 and phase ~= 6)
            if phase == 1 or phase == 3 then
                local limit = 1 + system_ini():r_float("alife", "switch_factor")
                assert(member.position:distance_to(db.actor:position()) > limit, "Distant group control inconclusive")
            end
            local matches = group.online == expected and member.online == expected and (client ~= nil) == expected
            if matches then stable = stable or now else stable = nil end
            if not stable or now - stable < 4000 then return end
            log1(string.format("[group policy] phase=%d mode=%s group=%d member=%d online=%s client=%s", phase, cfg.mode, cfg.group, cfg.member, tostring(group.online), tostring(client ~= nil)))
            if phase == 8 then
                assert(client and client:alive(), "Expected living group member")
                client:kill(db.actor)
                killed, deadline = now, now + 30000
            else
                phase = phase + 1
                begin_phase()
            end
        end, debug.traceback)
        if not ok then done = true; log1("[group policy] FAILED " .. err); get_console():execute("quit") end
        return false
    end, function() end)
end
