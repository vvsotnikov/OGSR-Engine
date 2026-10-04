#include <cmath>
#include <iostream>
struct Graph { float seconds = -1; void set_process_time(float value) { seconds = value; } };
struct CALifeUpdateManager
{
    Graph registry;
    float factor = 0;
    Graph& graph() { return registry; }
    float update_monster_factor() const { return factor; }
    void set_process_time(int microseconds);
};
#include "budget.inc"
int main()
{
    struct Case { int microseconds; float factor, seconds; };
    for (const auto& c : {Case{900, .1f, .00081f}, {1000000, .25f, .75f}, {1000, 0, .001f}, {1000, 1, 0}, {0, .1f, 0}})
    {
        CALifeUpdateManager manager;
        manager.factor = c.factor;
        manager.set_process_time(c.microseconds);
        if (std::abs(manager.registry.seconds - c.seconds) > 1e-7f)
        {
            std::cerr << "Wrong seconds budget: " << manager.registry.seconds << " expected " << c.seconds << '\n';
            return 1;
        }
    }
}
