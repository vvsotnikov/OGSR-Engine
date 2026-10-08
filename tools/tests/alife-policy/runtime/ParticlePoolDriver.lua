return function()
    local root = getFS():update_path("$app_data_root$", "")
    local marker = root .. "particle-pool-phase.txt"
    local maps = {"l05_bar", "l02_garbage", "l05_bar", "l02_garbage", "l05_bar"}
    local previous = io.open(marker, "r")
    local phase = previous and assert(tonumber(previous:read("*a"))) or 1
    if previous then previous:close() end
    assert(phase >= 1 and phase <= #maps)
    local start, done
    level.add_call(function()
        if done or not db.actor or not app_ready() or device().precache_frame ~= 0 then return false end
        local ok, err = xpcall(function()
            local now = device():time_global()
            if not start then
                start = now
                get_console():execute("g_god on")
            end
            if now - start < 15000 then return end
            assert(level.name() == maps[phase], "Unexpected particle probe map")
            log1(string.format("[particle pool] phase=%d map=%s", phase, level.name()))
            done = true
            if phase == #maps then
                log1("[particle pool] complete")
                get_console():execute("quit")
            else
                local f = assert(io.open(marker, "w"))
                f:write(tostring(phase + 1))
                f:close()
                get_console():execute("jump_to_level " .. maps[phase + 1])
            end
        end, debug.traceback)
        if not ok then
            done = true
            log1("[particle pool] FAILED " .. err)
            get_console():execute("quit")
        end
        return false
    end,function() end)
end
