-- Private test driver for an unpatched, non-Tracy Release executable.
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
    local frames = assert(io.open(path("regular-frames.csv"), "w"))
    frames:write("frame,game_ms,stage,frame_ms,frame_gap\n")
    local batches = assert(io.open(path("regular-batches.csv"), "w"))
    batches:write("frame,count,work_ms\n")
    local populations = assert(io.open(path("regular-population.csv"), "w"))
    populations:write("game_ms,stage,created,retained,online,client,living\n")
    local jobs = {}
    for i = 1, cfg.count do jobs[i] = assert(cfg.positions[i]) end
    local ids, online_at_creation = {}, 0
    local make_queue = dofile(path("SpawnQueue.lua"))
    dofile(path("Test-SpawnQueue.lua"))(make_queue)
    log1("[regular] queue_tests_passed")
    local queue = make_queue(jobs, function(job)
        local object = assert(alife():create("stalker", level.vertex_position(job.node), job.node, job.graph))
        ids[#ids + 1] = object.id
        if object.online then online_at_creation = online_at_creation + 1 end
        log1(string.format("[regular spawn] index=%d id=%d node=%d graph=%d", #ids, object.id, job.node, job.graph))
        return object.id
    end, now, cfg.budget_ms, cfg.budget_ms > 0 and 8 or 400)
    local stage, deadline, last, last_frame, last_stage, sample = 0, 0, nil, nil, 0, 0
    local creation_start, creation_end, work_total, all_online = nil, nil, 0, false
    local function tick()
        local d = device()
        if not db.actor or not app_ready() or d.precache_frame ~= 0 then return end
        if d.frame == last_frame then return end
        assert(not d:is_paused() and db.actor:alive(), "Paused or dead actor")
        local time = now()
        if stage == 0 then
            assert(level.name() == "l05_bar", "Wrong map")
            stage, deadline = 1, time + 15000
            log1("[regular] ready map=l05_bar")
        end
        if last then frames:write(string.format("%d,%d,%d,%.6f,%d\n", d.frame, d:time_global(), last_stage, time-last, d.frame-last_frame)) end
        if stage == 1 and time >= deadline then
            stage, creation_start = 2, time
            log1("[regular] create_begin")
        end
        if stage == 2 then
            local done, count, work = queue:step()
            work_total = work_total + work
            batches:write(string.format("%d,%d,%.6f\n", d.frame, count, work))
            if done then
                creation_end = now()
                stage, deadline = 3, creation_end + 15000
                log1(string.format("[regular] create_end count=%d wall_ms=%.3f work_ms=%.3f online_at_creation=%d", #ids, creation_end-creation_start, work_total, online_at_creation))
            end
        elseif stage == 3 and time >= deadline then
            stage, deadline = 4, time + 30000
            log1("[regular] measure_begin")
        elseif stage == 4 and time >= deadline then
            assert(#ids == cfg.count and all_online, "Incomplete creation/activation")
            log1("[regular] measure_end")
            frames:close(); batches:close(); populations:close()
            if cfg.save then get_console():execute("save regular_validation") end
            get_console():execute("quit")
            return
        end
        if time >= sample then
            local retained, online, client, living = 0, 0, 0, 0
            for _, id in ipairs(ids) do
                local object = alife():object(id)
                if object then
                    retained = retained + 1
                    if object.online then online = online + 1 end
                    if object.is_alive then living = living + 1 end
                end
                if level.object_by_id(id) then client = client + 1 end
            end
            populations:write(string.format("%d,%d,%d,%d,%d,%d,%d\n", d:time_global(), stage, #ids, retained, online, client, living))
            if creation_end and not all_online and retained == cfg.count and online == cfg.count and client == cfg.count then
                all_online = true
                log1(string.format("[regular] all_online count=%d after_create_ms=%.3f", #ids, now()-creation_end))
            end
            if stage == 4 then assert(retained == cfg.count and online == cfg.count and client == cfg.count, "Lost/offline spawned object") end
            sample = time + 1000
        end
        last, last_frame, last_stage = time, d.frame, stage
    end
    level.add_call(function()
        local ok, err = xpcall(tick, debug.traceback)
        if not ok then log1("[regular] FAILED " .. tostring(err)); get_console():execute("quit") end
        return false
    end, function() end)
end
