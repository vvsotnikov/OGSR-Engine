#include "TracyFileRead.hpp"
#include "TracyWorker.hpp"
#include <chrono>
#include <fstream>
#include <memory>
#include <thread>
#include <string>
#include <iostream>

// A projection of Tracy data, not an alternative trace parser. Load once to
// export frame boundaries and selected inclusive zones for interval analysis.
int main(int argc, char** argv)
{
    if (argc != 3) { std::cerr << "Usage: ogsr-trace-summary input.tracy output-prefix\n"; return 1; }
    try
    {
        auto file = std::unique_ptr<tracy::FileRead>(tracy::FileRead::Open(argv[1]));
        if (!file) return 2;
        tracy::Worker worker(*file, tracy::EventType::Plots);
        while (!worker.IsBackgroundDone()) std::this_thread::sleep_for(std::chrono::milliseconds(100));
        std::ofstream frames(std::string(argv[2]) + "-frames.tsv");
        std::ofstream zones(std::string(argv[2]) + "-zones.tsv");
        std::ofstream plots(std::string(argv[2]) + "-plots.tsv");
        if (!frames || !zones || !plots) return 3;
        plots << "name\ttime_ns\tvalue\n";
        for (const auto* plot : worker.GetPlots())
        {
            const std::string name = worker.GetString(plot->name);
            if (name.rfind("ALife/", 0) != 0) continue;
            for (const auto& point : plot->data)
                plots << name << '\t' << point.time.Val() << '\t' << point.val << '\n';
        }
        frames << "index\tstart_ns\tduration_ns\n";
        const auto* base = worker.GetFramesBase();
        for (size_t i = 0; i < worker.GetFullFrameCount(*base); ++i)
            frames << i << '\t' << worker.GetFrameBegin(*base, i) << '\t' << worker.GetFrameTime(*base, i) << '\n';
        zones << "name\tstart_ns\tduration_ns\tthread_slot\n";
        for (const auto& entry : worker.GetSourceLocationZones())
        {
            const auto& location = worker.GetSourceLocation(entry.first);
            const std::string name = worker.GetString(location.name.active ? location.name : location.function);
            if (name.rfind("ALife/", 0) != 0 && name != "CLevel::script_gc" &&
                name != "WaitSecondThread" && name != "Render process" &&
                name != "DoRender" && name != "DoRender End" && name != "seqParallel" && name != "seqFrameMT" &&
                name != "CSheduler::Update" && name != "CSheduler::ProcessStep" && name != "CSheduler::ProcessStep2" &&
                name.rfind("stalker/", 0) != 0) continue;
            for (const auto& event : entry.second.zones)
            {
                const auto* zone = event.Zone();
                if (zone->End() < zone->Start()) continue;
                zones << name << '\t' << zone->Start() << '\t' << zone->End() - zone->Start() << '\t' << event.Thread() << '\n';
            }
        }
        std::cout << "capture_unix=" << worker.GetCaptureTime() << " last_ns=" << worker.GetLastTime()
                  << " frame_offset=" << worker.GetFrameOffset() << '\n';
        frames.flush(); zones.flush(); plots.flush();
        return frames && zones && plots ? 0 : 4;
    }
    catch (const std::exception& e) { std::cerr << "Trace read failed: " << e.what() << '\n'; return 5; }
}
