#pragma once
#include <atomic>
#include <cstdint>

class CSE_ALifeDynamicObject;
namespace alife_service_trace
{
// One process-wide gate; all mutable collection state is protected in the recorder.
extern std::atomic<bool> enabled;
void begin();
void end();
void record(const char* kind, std::uint16_t id = 65535, std::uint64_t value = 0, std::uint32_t flags = 0, bool changes_only = false);
void object(const char* kind, const CSE_ALifeDynamicObject* object);
inline void event(const char* kind, std::uint16_t id = 65535, std::uint64_t value = 0, std::uint32_t flags = 0, bool changes_only = false)
{
    if (enabled.load(std::memory_order_relaxed)) record(kind, id, value, flags, changes_only);
}
}
