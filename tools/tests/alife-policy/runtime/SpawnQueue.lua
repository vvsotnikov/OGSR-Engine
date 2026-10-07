-- Synchronous creation batches spread across driver callbacks.
-- The caller owns the queue and must finish/cancel it before saving or changing maps.
return function(jobs, create, now, budget_ms, max_per_step)
    assert(budget_ms >= 0 and max_per_step >= 1)
    local queue = {next_job = 1, results = {}}
    function queue:step()
        local start, count = now(), 0
        while self.next_job <= #jobs do
            local result = assert(create(jobs[self.next_job]), "Creation returned no object")
            self.results[#self.results + 1] = result
            self.next_job = self.next_job + 1
            count = count + 1
            -- One creation is indivisible: this is a soft time budget.
            if count >= max_per_step or (budget_ms > 0 and now() - start >= budget_ms) then break end
        end
        return self.next_job > #jobs, count, now() - start
    end
    return queue
end
