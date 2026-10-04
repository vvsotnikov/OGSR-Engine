#include "TracyFileRead.hpp"
#include "TracyWorker.hpp"
#include <chrono>
#include <memory>
#include <thread>
#include <string>
#include <iostream>
#include <exception>
#include "TraceTsv.hpp"

// A projection of Tracy data, not an alternative trace parser. Load once to
// export frame boundaries and all inclusive CPU zones for interval analysis.
int main(int argc, char** argv)
{
    if (argc != 3) { std::cerr << "Usage: ogsr-trace-export input.tracy output-prefix\n"; return 1; }
    try
    {
        auto file = std::unique_ptr<tracy::FileRead>(tracy::FileRead::Open(argv[1]));
        if (!file) { std::cerr << "Cannot open trace: " << argv[1] << '\n'; return 2; }
        tracy::Worker worker(*file, tracy::EventType::Plots);
        while (!worker.IsBackgroundDone()) std::this_thread::sleep_for(std::chrono::milliseconds(100));
        trace_export::TsvFiles output(argv[2]);
        for (const auto* plot : worker.GetPlots())
        {
            const std::string name = worker.GetString(plot->name);
            for (const auto& point : plot->data)
            {
                output.plot(name, point.time.Val(), point.val);
            }
        }
        const auto* base = worker.GetFramesBase();
        for (size_t i = 0; i < worker.GetFullFrameCount(*base); ++i)
            output.frame(i, worker.GetFrameBegin(*base, i), worker.GetFrameTime(*base, i));
        for (const auto& entry : worker.GetSourceLocationZones())
        {
            const auto& location = worker.GetSourceLocation(entry.first);
            const std::string name = worker.GetString(location.name.active ? location.name : location.function);
            for (const auto& event : entry.second.zones)
            {
                const auto* zone = event.Zone();
                if (zone->End() < zone->Start()) continue;
                const auto thread_id = worker.DecompressThread(event.Thread());
                output.zone(name, zone->Start(), zone->End() - zone->Start(),
                            thread_id, worker.GetThreadName(thread_id));
            }
        }
        std::cout << "capture_unix=" << worker.GetCaptureTime() << " last_ns=" << worker.GetLastTime()
                  << " frame_offset=" << worker.GetFrameOffset() << '\n';
        output.finish();
        return 0;
    }
    catch (const std::exception& e) { std::cerr << "Trace export failed: " << e.what() << '\n'; return 5; }
}
