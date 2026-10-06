#include "alife_diagnostics.h"
#include <cstdio>
#include <iostream>
#include <limits>
#include <stdexcept>

void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
int main(int argc, char** argv)
{
    if (argc != 2 || !std::freopen(argv[1], "w", stdout))
    {
        std::cerr << "Cannot open production log fixture output\n";
        return 1;
    }
    try
    {
        alife_diagnostics::Reconciliation state;
        unsigned records = 0, anchors = 0;
        std::uint32_t frame = 0;
        auto update = [&](std::uint32_t time, double elapsed, double budget = .81) {
            ++frame;
            state.begin();
            if (state.sampled)
            {
                for (unsigned i = 0; i != 4; ++i)
                {
                    require(state.stages[i] == 0, "Stage totals carried into a new sample");
                    state.stages[i] = (i + 1) * .1;
                }
            }
            state.finish(time, frame, elapsed, budget, 400,
                [&](const char* format, auto... values) { ++records; std::printf(format, values...); std::putchar('\n'); },
                [&](std::uint32_t anchor) { require(anchor == frame, "Anchor does not identify emitted frame"); ++anchors; });
        };
        update(0, 20, -1.0);
        require(records == 1 && !state.suppressed, "First spike was not emitted immediately");
        update(1000, 12);
        require(records == 2 && !state.suppressed, "Spike interval boundary suppressed a report");
        update(1100, 11);
        require(records == 2 && state.suppressed == 1, "Spike rate limit failed");
        for (unsigned i = 4; i < 64; ++i)
            update(1200, 2);
        require(records == 2, "Sampling occurred before update 64");
        for (auto& value : state.stages) value = 99;
        update(1200, 2);
        require(records == 3 && !state.suppressed && !state.sampled, "Sample did not emit/reset suppression or stop sampling");
        update(std::numeric_limits<std::uint32_t>::max() - 200, 20);
        update(500, 20);
        require(records == 4 && state.suppressed == 1, "Clock wrap broke spike suppression");
        update(800, 20);
        require(records == 5 && !state.suppressed && anchors == records, "Spike/anchor count incorrect after clock wrap");
        require(std::fflush(stdout) == 0, "Cannot flush production log fixture");
    }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
