#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>
struct { std::uint32_t dwTimeGlobal; } Device;
unsigned timers = 0;
struct CTimer
{
    CTimer() { ++timers; }
    void Start() {}
    double GetElapsed_sec() const { return 0.001; }
};
struct CALifeUpdateManager
{
    bool m_alife_metrics = false;
    std::uint32_t m_metrics_time = 0, m_metrics_updates = 0, m_metrics_samples = 0;
    double m_metrics_switch_ms = 0, m_metrics_offline_scheduled_ms = 0;
    unsigned switches = 0, scheduled = 0;
    std::vector<unsigned> reported_updates;
    void update_switch() { ++switches; }
    void update_scheduled(bool) { ++scheduled; }
    void report_metrics()
    {
        reported_updates.push_back(m_metrics_updates);
        ++m_metrics_samples;
        m_metrics_time = Device.dwTimeGlobal;
        m_metrics_updates = 0;
        m_metrics_switch_ms = m_metrics_offline_scheduled_ms = 0;
    }
    void update();
};
#include "metrics-update.inc"
void require(bool condition) { if (!condition) throw std::runtime_error("Invalid metrics interval"); }
int main()
{
    try {
        for (std::uint32_t start : {0u, 11872u, UINT32_MAX - 500u}) {
            CALifeUpdateManager manager;
            Device.dwTimeGlobal = start;
            auto before = timers;
            manager.update();
            require(timers == before && manager.switches == 1 && manager.scheduled == 1 && manager.reported_updates.empty());
            manager.m_alife_metrics = true;
            manager.update();
            require(manager.reported_updates.empty());
            Device.dwTimeGlobal = start + 999u;
            manager.update();
            require(manager.reported_updates.empty());
            Device.dwTimeGlobal = start + 1000u;
            manager.update();
            require(manager.reported_updates == std::vector<unsigned>{3});
            Device.dwTimeGlobal = start + 1001u;
            manager.update();
            require(manager.reported_updates.size() == 1);
            Device.dwTimeGlobal = start + 2000u;
            manager.update();
            require(manager.reported_updates == std::vector<unsigned>({3, 2}));
            require(manager.switches == 6 && manager.scheduled == 6);
        }
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "Metrics intervals pass at startup, after loading and across clock wrap\n";
}
