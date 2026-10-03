-- Runs inside the private Lua driver, with no game objects or wall-clock dependency.
return function(make_queue)
    local time, seen = 0, {}
    local queue = make_queue({1,2,3,4,5}, function(job)
        time = time + 2; seen[#seen+1] = job; return job
    end, function() return time end, 3, 8)
    local done, count = queue:step(); assert(not done and count == 2)
    done, count = queue:step(); assert(not done and count == 2)
    done, count = queue:step(); assert(done and count == 1)
    assert(table.concat(seen, ',') == '1,2,3,4,5' and #queue.results == 5)
    queue = make_queue({1,2,3}, function(job) time=time+10; return job end, function() return time end, 3, 8)
    done, count = queue:step(); assert(not done and count == 1)
    queue = make_queue({1,2,3}, function(job) return job end, function() return time end, 3, 2)
    done, count = queue:step(); assert(not done and count == 2)
    queue = make_queue({}, function() error('Unexpected creation') end, function() return time end, 3, 8)
    done, count = queue:step(); assert(done and count == 0)
    queue = make_queue({1}, function() return nil end, function() return time end, 3, 8)
    assert(not pcall(function() queue:step() end) and queue.next_job == 1 and #queue.results == 0)
end
