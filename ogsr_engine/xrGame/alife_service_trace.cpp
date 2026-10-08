#include "stdafx.h"
#include "alife_service_trace.h"
#include "xrServer_Objects_ALife.h"
#include "xrServer_Objects_ALife_Monsters.h"
#include <array>
#include <chrono>
#include <mutex>
#include <vector>
#include <condition_variable>
#include <thread>
#include <string>
#include <optional>

namespace alife_service_trace
{
std::atomic<bool> enabled{false};
namespace
{
using Clock = std::chrono::steady_clock;
struct Event { std::uint64_t us, generation, value; const char* kind; std::uint32_t flags; std::uint16_t id; };
std::mutex mutex;
std::vector<Event> events;
std::condition_variable wake;
std::thread worker;
bool stopping = false;
IWriter* writer = nullptr;
std::uint64_t written = 0;
struct Settings { std::uint16_t id; std::uint64_t value; std::uint32_t flags; };
std::optional<Settings> last_settings, last_scheduler;
std::array<std::uint64_t, 65536> generations{};
Clock::time_point epoch;
std::uint64_t dropped = 0, serial = 0;
constexpr size_t capacity = 65536;
constexpr size_t batch_size = 4096;
std::uint64_t now() { return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - epoch).count(); }
}
void begin()
{
    if (!strstr(Core.Params, "-alife_service_trace")) return;
    std::lock_guard<std::mutex> guard(mutex);
    R_ASSERT(!enabled.load());
    last_settings.reset();
    last_scheduler.reset();
    events.clear();
    events.reserve(capacity);
    generations.fill(0);
    dropped = written = 0;
    stopping = false;
    ++serial;
    string_path path;
    string128 name;
    xr_sprintf(name, "alife-service-%lu-%llu.csv", GetCurrentProcessId(), serial);
    FS.update_path(path, "$app_data_root$", name);
    writer = FS.w_open(path);
    R_ASSERT2(writer, "Cannot open ALife service trace");
    writer->w_printf("ogsr-service,1\n");
    writer->w_printf("us,kind,id,generation,value,flags\n");
    epoch = Clock::now();
    worker = std::thread([] {
        std::vector<Event> batch;
        batch.reserve(capacity);
        std::string text;
        for (;;)
        {
            {
                std::unique_lock<std::mutex> lock(mutex);
                wake.wait(lock, [] { return stopping || events.size() >= batch_size; });
                if (events.empty() && stopping) break;
                batch.swap(events);
            }
            text.clear();
            for (const auto& e : batch)
            {
                char line[160];
                const int size = sprintf_s(line, "%llu,%s,%u,%llu,%llu,%u\n", e.us, e.kind, unsigned(e.id), e.generation, e.value, e.flags);
                text.append(line, size);
            }
            writer->w(text.data(), text.size());
            written += batch.size();
            batch.clear();
        }
    });
    enabled.store(true, std::memory_order_release);
}
void record(const char* kind, std::uint16_t id, std::uint64_t value, std::uint32_t flags, Cache cache)
{
    std::lock_guard<std::mutex> guard(mutex);
    if (!enabled.load(std::memory_order_relaxed)) return;
    std::optional<Settings>* previous = nullptr;
    if (cache != Cache::None)
    {
        previous = cache == Cache::Settings ? &last_settings : &last_scheduler;
        if (*previous && (*previous)->id == id && (*previous)->value == value && (*previous)->flags == flags) return;
    }
    if (strcmp(kind, "register") == 0) ++generations[id];
    if (events.size() == capacity) { ++dropped; return; }
    events.push_back({now(), generations[id], value, kind, flags, id});
    if (previous) *previous = Settings{id, value, flags};
    if (events.size() == batch_size) wake.notify_one();
}
void object(const char* kind, const CSE_ALifeDynamicObject* object)
{
    if (!enabled.load(std::memory_order_relaxed)) return;
    // Snapshot only side-effect-free object fields. Permission evaluation remains in production policy.
    const auto* creature = smart_cast<const CSE_ALifeCreatureAbstract*>(object);
    const std::uint32_t flags = (object->m_bOnline ? 1u : 0u) | (object->ID_Parent != 65535 ? 2u : 0u) |
        (creature ? 4u : 0u) | (creature && creature->fHealth > 0 ? 8u : 0u) |
        (object->can_switch_online() ? 16u : 0u) | (object->can_switch_offline() ? 32u : 0u);
    record(kind, object->ID, object->m_tGraphID, flags);
}
void end()
{
    if (!enabled.load(std::memory_order_relaxed)) return;
    std::uint64_t stop;
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (!enabled.exchange(false)) return;
        stop = now();
        stopping = true;
        wake.notify_one();
    }
    worker.join();
    writer->w_printf("%llu,end,65535,%llu,%llu,0\n", stop, written, dropped);
    FS.w_close(writer);
    Msg("[ALife service trace] records=%llu dropped=%llu", written, dropped);
}
}
