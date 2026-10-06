#pragma once

#include <cstdint>

namespace alife_diagnostics
{
// This header also owns the always-used per-object switch lifecycle and update
// ordering. Only timing and reporting are optional; disabling diagnostics must
// not bypass reconciliation or scheduled updates.
// Operations supplies the real object's lifecycle in the engine and controlled
// operations in tests. release() invalidates the object: never access it after
// that call. Read online() after synchronization, which may change its state.
template <class Timer, class Operations>
void reconcile_object(bool sampled, double (&stages)[4], Operations& operations)
{
    const auto before = [&]() {
        if (operations.redundant())
        {
            operations.release();
            return false;
        }
        return operations.synchronize_location();
    };
    const auto evaluate = [&]() {
        if (operations.online())
            operations.try_switch_offline();
        else
            operations.try_switch_online();
    };
    const auto after = [&]() {
        if (operations.redundant())
            operations.release();
    };

    if (!sampled)
    {
        if (!before())
            return;
        evaluate();
        after();
        return;
    }
    Timer timer;
    timer.Start();
    const bool ready = before();
    const double before_end = timer.GetElapsed_sec() * 1000.0;
    stages[0] += before_end;
    if (!ready)
        return;
    const unsigned phase = operations.online() ? 1 : 2;
    evaluate();
    const double dispatch_end = timer.GetElapsed_sec() * 1000.0;
    stages[phase] += dispatch_end - before_end;
    after();
    stages[3] += timer.GetElapsed_sec() * 1000.0 - dispatch_end;
}

struct Reconciliation
{
    static constexpr std::uint32_t stage_cadence = 64;
    static constexpr double spike_ms = 10.0;
    static constexpr std::uint32_t spike_log_interval_ms = 1000;
    bool sampled = false;
    std::uint32_t updates = 0;
    std::uint32_t suppressed = 0;
    double stages[4] = {};
    std::uint32_t last_spike_log = std::uint32_t(0) - spike_log_interval_ms;

    void begin()
    {
        sampled = ++updates % stage_cadence == 0;
        if (sampled)
            for (auto& value : stages)
                value = 0;
    }

    // Unsigned subtraction preserves the interval across the engine's u32 clock
    // wrap. Emit and anchor run outside the measured reconciliation update.
    template <class Emit, class Anchor>
    void finish(std::uint32_t now, std::uint32_t frame,
                double elapsed_ms, double budget_ms, std::uint32_t visited,
                Emit emit, Anchor anchor)
    {
        const bool spike = elapsed_ms >= spike_ms;
        const bool report_spike = spike && std::uint32_t(now - last_spike_log) >= spike_log_interval_ms;
        if (sampled || report_spike)
        {
            if (report_spike)
                last_spike_log = now;
            emit("[ALife reconcile] frame=%u update=%u sampled=%u spike=%u suppressed=%u objects=%u budget_ms=%.6f total_ms=%.6f before_ms=%.6f try_offline_ms=%.6f try_online_ms=%.6f after_ms=%.6f",
                 unsigned(frame), unsigned(updates), unsigned(sampled), unsigned(spike), unsigned(suppressed), unsigned(visited), budget_ms,
                 elapsed_ms, sampled ? stages[0] : 0.0, sampled ? stages[1] : 0.0,
                 sampled ? stages[2] : 0.0, sampled ? stages[3] : 0.0);
            anchor(frame);
            suppressed = 0;
        }
        else if (spike)
            ++suppressed;
        sampled = false;
    }
};

struct MetricsInterval
{
    std::uint32_t time = 0;
    std::uint32_t updates = 0;
    std::uint32_t samples = 0;
    double switch_ms = 0;
    double offline_scheduled_ms = 0;

    template <class Timer, class Now, class Switch, class Scheduled, class Report>
    void update(bool enabled, Now now, Switch switch_objects, Scheduled scheduled, Report report)
    {
        if (!enabled)
        {
            switch_objects();
            scheduled();
            return;
        }
        // Loading time must not shorten the first reporting interval.
        if (!samples && !updates)
            time = now();
        Timer timer;
        timer.Start();
        switch_objects();
        switch_ms += timer.GetElapsed_sec() * 1000.0;
        timer.Start();
        scheduled();
        offline_scheduled_ms += timer.GetElapsed_sec() * 1000.0;
        ++updates;
        if (std::uint32_t(now() - time) >= 1000)
        {
            ++samples;
            report();
            time = now();
            updates = 0;
            switch_ms = offline_scheduled_ms = 0;
        }
    }
};
}
