#pragma once
#include "SchedulerProbe.h"
#include <chrono>
namespace QueueProbe
{
using Clock = std::chrono::steady_clock;
inline thread_local Clock::time_point start;
inline thread_local double maintenance_us;
inline thread_local u32 removed;
inline void Begin() { start = Clock::now(); maintenance_us = 0; removed = 0; }
struct Maintenance
{
    Clock::time_point start = Clock::now();
    ~Maintenance() { maintenance_us += std::chrono::duration<double, std::micro>(Clock::now() - start).count(); }
};
inline void Finish(bool compact)
{
    const double step_us = std::chrono::duration<double, std::micro>(Clock::now() - start).count();
    static auto stream = CadenceProbe::Open("queue-timing.csv", "game_ms,compact,maintenance_us,step_us,removed");
    stream << Device.dwTimeGlobal << ',' << compact << ',' << maintenance_us << ',' << step_us << ',' << removed << '\n';
}
}
