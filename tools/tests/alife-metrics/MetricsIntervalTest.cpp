#include "alife_diagnostics.h"
#include <iostream>
#include <stdexcept>
#include <vector>

unsigned timers = 0;
struct TestTimer
{
    TestTimer() { ++timers; }
    void Start() {}
    double GetElapsed_sec() const { return .001; }
};
void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
int main()
{
    try
    {
        for (std::uint32_t start : {0u, 11872u, UINT32_MAX - 500u})
        {
            alife_diagnostics::MetricsInterval metrics;
            std::uint32_t now = start;
            std::vector<unsigned> reports;
            std::vector<char> operations;
            auto update = [&](bool enabled) {
                metrics.update<TestTimer>(enabled, [&] { return now; },
                    [&] { operations.push_back('s'); }, [&] { operations.push_back('o'); }, [&] {
                        require(metrics.switch_ms == metrics.updates, "Switch interval total incorrect");
                        require(metrics.offline_scheduled_ms == metrics.updates, "Offline interval total incorrect");
                        require(metrics.samples == reports.size() + 1, "Sample count not advanced before report");
                        reports.push_back(metrics.updates);
                    });
            };
            const auto before = timers;
            update(false);
            require(timers == before && reports.empty(), "Disabled metrics used timers or emitted a report");
            update(true);
            require(reports.empty(), "First interval includes loading time");
            now = start + 999u; update(true);
            require(reports.empty(), "Reported before the interval elapsed");
            now = start + 1000u; update(true);
            require(reports == std::vector<unsigned>{3}, "First interval has incorrect update count");
            require(!metrics.updates && !metrics.switch_ms && !metrics.offline_scheduled_ms, "Interval totals not reset");
            now = start + 1001u; update(true);
            require(reports.size() == 1, "Repeated report without a full interval");
            now = start + 2000u; update(true);
            require(reports == std::vector<unsigned>({3, 2}), "Second interval includes previous work");
            require(operations == std::vector<char>({'s','o','s','o','s','o','s','o','s','o','s','o'}), "Switch/offline work reordered or omitted");
        }
    }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "Production metrics intervals passed, including loading and clock wrap\n";
}
