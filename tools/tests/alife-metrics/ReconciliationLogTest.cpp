#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <limits>
using u32 = std::uint32_t;
using int64_t = std::int64_t;
struct { u32 dwTimeGlobal = 0, dwFrame = 0; } Device;
unsigned records = 0, anchors = 0;
void Msg(const char* format, ...)
{
    ++records;
    va_list args; va_start(args, format); std::vprintf(format, args); va_end(args);
    std::putchar('\n');
}
void TracyPlot(const char*, int64_t frame) { if (frame == Device.dwFrame) ++anchors; }
struct Candidate
{
#include "log-constants.inc"
    bool m_reconcile_metrics = false, m_reconcile_sample = false;
    u32 m_reconcile_updates = 0, m_last_reconcile_spike_log = 0, m_suppressed_spikes = 0;
    double m_reconcile_stage_ms[4] = {};
    void begin_reconciliation();
    void finish_reconciliation(double, double, u32);
};
#include "log-methods.inc"
int main(int argc, char** argv)
{
    if (argc != 2 || !std::freopen(argv[1], "w", stdout)) return 1;
    Candidate manager;
    auto update = [&](u32 time, double elapsed) {
        Device.dwTimeGlobal = time; ++Device.dwFrame;
        manager.begin_reconciliation();
        manager.finish_reconciliation(elapsed, 300000.0, 400);
    };
    update(0, 20);
    if (records || manager.m_reconcile_updates || manager.m_suppressed_spikes) return 2;
    manager.m_reconcile_metrics = true;
    update(0, 20);
    if (records || manager.m_suppressed_spikes != 1) return 3;
    update(1000, 12);
    if (records != 1 || manager.m_suppressed_spikes) return 4;
    update(1100, 11);
    if (records != 1 || manager.m_suppressed_spikes != 1) return 5;
    manager.m_reconcile_updates = Candidate::reconcile_stage_cadence - 1;
    update(1200, 2);
    if (records != 2 || manager.m_suppressed_spikes || manager.m_reconcile_sample) return 6;
    update(std::numeric_limits<u32>::max() - 200, 20);
    update(500, 20);
    if (records != 3 || manager.m_suppressed_spikes != 1) return 7;
    update(800, 20);
    if (records != 4 || manager.m_suppressed_spikes || anchors != records) return 8;
    return std::fflush(stdout) == 0 ? 0 : 9;
}
