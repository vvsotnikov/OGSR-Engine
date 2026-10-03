#pragma once
// Temporary diagnostic header. No policy/timing changes to the scheduler.
#include <fstream>
namespace CadenceProbe
{
inline bool Enabled() { static const bool value = strstr(Core.Params, "-alife_cadence") != nullptr; return value; }
struct Dispatch
{
    const void* object = nullptr;
    u32 now = 0, elapsed = 0, requested = 0, late = 0, next = 0;
    bool realtime = false;
};
inline thread_local Dispatch current;
inline void Begin(const void* object, u32 now, u32 elapsed, u32 requested, u32 late, u32 next, bool realtime)
{
    if (Enabled()) current = {object, now, elapsed, requested, late, next, realtime};
}
inline std::ofstream Open(const char* file, const char* header)
{
    string_path path;
    FS.update_path(path, "$app_data_root$", file);
    std::ofstream stream(path);
    R_ASSERT(stream.good());
    stream << header << '\n';
    return stream;
}
inline void Stalker(const void* object, u16 id, bool alive, u16 enemy, bool firing)
{
    if (!Enabled()) return;
    static std::ofstream stream = Open("cadence-updates.csv", "game_ms,dispatch_ms,id,alive,enemy,firing,engine_interval_ms,requested_ms,late_ms,next_ms,realtime,context_valid");
    const auto& c = current;
    const u32 dispatch = Device.TimerAsync();
    stream << Device.dwTimeGlobal << ',' << dispatch << ',' << id << ',' << alive << ',' << enemy << ',' << firing << ','
           << c.elapsed << ',' << c.requested << ',' << c.late + (dispatch - c.now) << ',' << c.next << ',' << c.realtime << ',' << (c.object == object) << '\n';
}
inline void Frame(u32 time, bool stopped, u32 pending, u32 overdue, u32 max_late, float budget)
{
    if (!Enabled()) return;
    static std::ofstream stream = Open("cadence-scheduler.csv", "game_ms,budget_stopped,pending,overdue,max_late_ms,budget_ms");
    stream << time << ',' << stopped << ',' << pending << ',' << overdue << ',' << max_late << ',' << budget << '\n';
}
inline void Shot(u16 owner, u16 weapon)
{
    if (!Enabled()) return;
    static std::ofstream stream = Open("cadence-shots.csv", "game_ms,owner,weapon");
    stream << Device.dwTimeGlobal << ',' << owner << ',' << weapon << '\n';
}
}
