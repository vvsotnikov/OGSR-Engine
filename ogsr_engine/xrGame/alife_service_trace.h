#pragma once
#include <atomic>
#include <cstdint>

class CSE_ALifeDynamicObject;
namespace alife_service_trace
{
enum class Cache { None, Settings, Scheduler };
// Collection gates; mutable capture state is protected in the recorder.
extern std::atomic<bool> enabled;
extern std::atomic<bool> detail_enabled;
extern std::atomic<bool> visits_enabled;
void begin();
void end();
void record(const char* kind, std::uint16_t id = 65535, std::uint64_t value = 0, std::uint32_t flags = 0, Cache cache = Cache::None);
void object(const char* kind, const CSE_ALifeDynamicObject* object);
inline void event(const char* kind, std::uint16_t id = 65535, std::uint64_t value = 0, std::uint32_t flags = 0, Cache cache = Cache::None)
{
    if (detail_enabled.load(std::memory_order_relaxed)) record(kind, id, value, flags, cache);
}
}
