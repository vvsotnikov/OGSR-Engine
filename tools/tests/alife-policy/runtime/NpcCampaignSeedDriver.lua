-- The runner disables migration in its private configuration for this save.
return function()
    local started, camp, npcs, sent = nil, nil, {}, false
    local function tick()
        if sent or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        if level.name() == "l05_bar" then
            get_console():execute("jump_to_level l01_escape")
            sent = true
            return
        end
        assert(level.name() == "l01_escape")
        local now = time_global()
        if not started then
            started = now
            get_console():execute("g_god on")
            db.actor:give_info_portion("agroprom_military_case")
            for id = 0, 65534 do
                local obj = alife():object(id)
                if obj and obj:name() == "esc_farm_lager" then camp = obj; break end
            end
            assert(camp, "No farm camp")
            camp:initialize_if_needed()
            for id in pairs(camp.npc_info) do
                local obj = alife():object(id)
                if obj and obj:alive() then npcs[#npcs + 1] = id end
            end
            assert(#npcs <= 3, "Unexpected farm population")
            local p = level.vertex_position(camp.m_level_vertex_id)
            db.actor:set_actor_position(vector():set(p.x + 8, p.y + 1, p.z))
            for i = #npcs + 1, 3 do
                local obj = assert(alife():create("esc_stalker_respawn_1", p, camp.m_level_vertex_id, camp.m_game_vertex_id))
                assert(obj:smart_terrain_id() == camp.id, "Wrong camp")
                npcs[i] = obj.id
            end
        end
        assert(now - started < 90000, "Camp seed timed out")
        for _, id in ipairs(npcs) do
            local obj, st = assert(alife():object(id)), db.storage[id]
            assert(obj:alive() and obj:smart_terrain_id() == camp.id)
            assert(alife():supply_trip_phase(id) == -1, "Seed already has planner ownership")
            if not st or not st.ini or not camp.gulag.Object_begin_job[id] then return end
            assert(st.gulag_name == camp:name() and st.active_section)
        end
        local file = assert(io.open(getFS():update_path("$app_data_root$", "campaign-seed.lua"), "w"))
        file:write(string.format("return {camp=%d,npcs={%d,%d,%d}}", camp.id, npcs[1], npcs[2], npcs[3]))
        file:close()
        get_console():execute("save campaign_legacy_seed")
        log1("[npc fixture] complete scenario=campaign-seed")
        sent = true
        get_console():execute("quit")
    end
    level.add_call(function()
        local ok, err = xpcall(tick, debug.traceback)
        if not ok then
            log1("[npc fixture] FAILED " .. tostring(err))
            sent = true
            get_console():execute("quit")
        end
        return false
    end, function() end)
end
