-- Technical roundtrip via the existing console command; not a natural exit test.
return function(now, path)
    local maps = {"l05_bar", "l02_garbage", "l05_bar"}
    local state_path = path("transition-phase.txt")
    local input = io.open(state_path, "r")
    local phase = 1
    if input then phase = assert(tonumber(input:read("*a"))); input:close() end
    assert(phase >= 1 and phase <= 3)
    local ready, sent = nil, false
    local function tick()
        if sent or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        assert(db.actor:alive(), "Actor died after artificial level jump")
        assert(not device():is_paused(), "Unexpected paused state after level jump")
        assert(level.name() == maps[phase], "Unexpected roundtrip destination")
        if not ready then
            -- Isolate world loading from survival at the command's chosen
            -- destination. This affects only this disposable fixture.
            get_console():execute("g_god on")
            log1("[transition] survival_isolation=g_god")
            ready = now()
            log1(string.format("[transition] arrived phase=%d map=%s", phase, level.name()))
        end
        if now() - ready < 15000 then return end
        sent = true
        if phase == 3 then
            get_console():execute("save reconcile_roundtrip")
            log1("[transition] complete")
            get_console():execute("quit")
        else
            local output = assert(io.open(state_path, "w"))
            output:write(tostring(phase + 1)); output:close()
            get_console():execute("jump_to_level " .. maps[phase + 1])
        end
    end
    level.add_call(function()
        local ok, err = xpcall(tick, debug.traceback)
        if not ok then log1("[transition] FAILED " .. tostring(err)); get_console():execute("quit") end
        return false
    end, function() end)
end
