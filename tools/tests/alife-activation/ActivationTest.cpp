#include "../../../ogsr_engine/xrGame/alife_activation_queue.h"
#include <stdexcept>
#include <vector>
void check(bool x) { if (!x) throw std::runtime_error("activation invariant"); }
int main()
{
    ALifeActivationQueue queue;
    double time = 0;
    double start = 0, budget = 3;
    auto expired = [&]() { return time - start >= budget; };
    std::vector<std::uint16_t> seen;
    auto consume = [&](std::uint16_t id) { seen.push_back(id); time += 2; };
    for (unsigned i=0; i<100000; ++i) { queue.enqueue(7); queue.cancel(7); }
    check(queue.slots() == 1 && queue.size() == 0);
    queue.enqueue(8); queue.enqueue(7); queue.enqueue(9);
    check(queue.drain(expired, consume, 32) == 2);
    check((seen == std::vector<std::uint16_t>{7,8}));
    check(queue.drain([] { return true; }, consume, 32) == 1 && seen.back() == 9);
    queue.enqueue(10);queue.enqueue(11);queue.cancel(10);
    check(queue.drain([] { return false; }, consume, 1) == 1 && queue.contains(11));
    check(queue.drain([] { return false; }, consume, 1) == 1 && seen.back() == 11);
    queue.enqueue(12);queue.clear();check(queue.slots() == 0 && queue.size() == 0);
    for (unsigned i=0; i<65536; ++i) { queue.enqueue(std::uint16_t(i));queue.enqueue(std::uint16_t(i)); }
    check(queue.slots() == 65536 && queue.size() == 65536);
    queue.clear();queue.enqueue(1);queue.enqueue(2);
    check(queue.drain([&] { return time >= 50; },[&](std::uint16_t) { time += 50; },32)==1);
    check(queue.contains(2));
}
