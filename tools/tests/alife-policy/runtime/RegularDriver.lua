-- Private test driver for a non-Tracy Release executable without C++ test hooks.
return function(cfg)
    local ffi = FFI
    ffi.cdef[[int QueryPerformanceCounter(int64_t*); int QueryPerformanceFrequency(int64_t*);]]
    local kernel = ffi.load("kernel32")
    local counter, frequency = ffi.new("int64_t[1]"), ffi.new("int64_t[1]")
    assert(kernel.QueryPerformanceFrequency(frequency) ~= 0)
    local scale = 1000 / tonumber(frequency[0])
    local function now()
        assert(kernel.QueryPerformanceCounter(counter) ~= 0)
        return tonumber(counter[0]) * scale
    end
    local function path(name) return getFS():update_path("$app_data_root$", name) end
    if cfg.transitions then return dofile(path("TransitionDriver.lua"))(now, path, cfg) end
    if cfg.distance_control then alife():set_switch_distance(20) end
    local distance_mode = cfg.mode == "distance"
    local factor = system_ini():r_float("alife", "switch_factor")
    assert(factor >= 0 and factor < 1, "Unsupported hysteresis factor")
    local far_limit = alife():switch_distance() * (1 + factor) + 10
    local far_samples = 0
    local eligibility = cfg.eligibility and dofile(path("Test-Eligibility.lua"))(cfg.positions[1], now)
    local ownership = cfg.eligibility and dofile(path("Test-Ownership.lua"))(now)
    local populations = assert(io.open(path("regular-population.csv"), "w"))
    populations:write("game_ms,stage,created,retained,online,client,living\n")
    local jobs = {}
    for i = 1, cfg.count do jobs[i] = assert(cfg.positions[i]) end
    local ids, online_at_creation = {}, 0
    local make_queue = dofile(path("SpawnQueue.lua"))
    local queue = make_queue(jobs, function(job)
        local object = assert(alife():create("stalker", level.vertex_position(job.node), job.node, job.graph))
        ids[#ids + 1] = object.id
        if object.online then online_at_creation = online_at_creation + 1 end
        log1(string.format("[regular spawn] index=%d id=%d node=%d graph=%d", #ids, object.id, job.node, job.graph))
        return object.id
    end, now, cfg.budget_ms, cfg.budget_ms > 0 and 8 or 400)
    local stage, deadline, last_frame, sample = 0, 0, nil, 0
    local creation_start, creation_end, work_total, all_online = nil, nil, 0, false
    local frames, previous_time = {}, nil
    local function tick()
        local d = device()
        if not db.actor or not app_ready() or d.precache_frame ~= 0 then return end
        if d.frame == last_frame then return end
        assert(not d:is_paused(), "Paused actor")
        assert(db.actor:alive(), "Dead actor")
        if eligibility and not eligibility() then return end
        if ownership and not ownership() then return end
        local time = now()
        if cfg.frame_times and previous_time then frames[#frames+1] = {d.frame, d:time_global(), stage, time-previous_time} end
        previous_time = time
        if stage == 0 then
            assert(level.name() == "l05_bar", "Wrong map")
            stage, deadline = 1, time + 15000
            log1("[regular] ready map=l05_bar")
        end
        if stage == 1 and time >= deadline then
            stage, creation_start = 2, time
            log1("[regular] create_begin")
        end
        if stage == 2 then
            local done, count, work = queue:step()
            work_total = work_total + work
            if done then
                creation_end = now()
                stage, deadline = 3, creation_end + 15000
                log1(string.format("[regular] create_end count=%d wall_ms=%.3f work_ms=%.3f online_at_creation=%d", #ids, creation_end-creation_start, work_total, online_at_creation))
            end
        elseif stage == 3 and time >= deadline then
            stage, deadline = 4, time + 45000
            log1("[regular] measure_begin")
        elseif stage == 4 and time >= deadline then
            assert(#ids == cfg.count and (distance_mode or all_online), "Incomplete creation/activation")
            if cfg.distance_control and cfg.count > 0 then
                assert(far_samples >= 25, "No sustained population beyond distance gate")
                log1("[regular] distance_control_passed mode=" .. cfg.mode .. " samples=" .. far_samples)
            end
            log1("[regular] measure_end")
            if cfg.verify_ids and #cfg.verify_ids > 0 then log1("[regular] verified_restored count=" .. #cfg.verify_ids) end
            populations:close()
            if cfg.frame_times then
                local output = assert(io.open(path("regular-frames.csv"), "w"))
                output:write("frame,game_ms,stage,wall_ms\n")
                for _,row in ipairs(frames) do output:write(string.format("%d,%d,%d,%.6f\n", unpack(row))) end
                output:close()
            end
            if cfg.save then get_console():execute("save regular_validation") end
            get_console():execute("quit")
            return
        end
        if time >= sample then
            local retained, online, client, living, far, far_online, far_client = 0, 0, 0, 0, 0, 0, 0
            for _, id in ipairs(ids) do
                local object = alife():object(id)
                if object then
                    retained = retained + 1
                    if object.online then online = online + 1 end
                    if object.is_alive then living = living + 1 end
                    if object.position:distance_to(db.actor:position()) > far_limit then
                        far = far + 1
                        if object.online then far_online = far_online + 1 end
                        if level.object_by_id(id) then far_client = far_client + 1 end
                    end
                end
                if level.object_by_id(id) then client = client + 1 end
            end
            populations:write(string.format("%d,%d,%d,%d,%d,%d,%d\n", d:time_global(), stage, #ids, retained, online, client, living))
            if creation_end and not all_online and retained == cfg.count and online == cfg.count and client == cfg.count then
                all_online = true
                log1(string.format("[regular] all_online count=%d after_create_ms=%.3f", #ids, now()-creation_end))
            end
            if stage == 4 then
                assert(retained == cfg.count, "Lost spawned object")
                if not distance_mode then assert(online == cfg.count and client == cfg.count, "Offline spawned object") end
                if cfg.distance_control and cfg.count > 0 then
                    assert(far > 0, "No distant NPCs in control")
                    local matches = far_online == (distance_mode and 0 or far) and far_client == (distance_mode and 0 or far)
                    far_samples = matches and (far_samples + 1) or 0
                    log1(string.format("[regular control] far=%d online=%d client=%d limit=%.3f", far, far_online, far_client, far_limit))
                end
            end
            if stage == 4 then
                for _, id in ipairs(cfg.verify_ids or {}) do
                    local object = assert(alife():object(id), "Missing restored ID " .. id)
                    assert(object.online and level.object_by_id(id), "Restored ID offline or without client " .. id)
                end
            end
            sample = time + 1000
        end
        last_frame = d.frame
    end
    level.add_call(function()
        local ok, err = xpcall(tick, debug.traceback)
        if not ok then log1("[regular] FAILED " .. tostring(err)); get_console():execute("quit") end
        return false
    end, function() end)
end
