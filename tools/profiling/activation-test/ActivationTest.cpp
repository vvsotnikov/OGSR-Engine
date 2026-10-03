#include "../../../ogsr_engine/xrGame/alife_activation_queue.h"
#include <stdexcept>
#include <vector>
#include <iostream>

void check(bool value) { if (!value) throw std::runtime_error("activation regression"); }
int main()
{
    ALifeActivationQueue queue;
    double time = 0;
    auto clock = [&]() { return time; };
    std::vector<unsigned> activated;
    auto consume = [&](unsigned id) { activated.push_back(id); time += 2; };
    for (unsigned id = 1; id <= 5; ++id) { queue.enqueue(id); queue.enqueue(id); }
    check(queue.size() == 5);
    check(queue.drain(clock, consume, 3, 32) == 2);
    check((activated == std::vector<unsigned>{1, 2}) && queue.size() == 3);
    queue.cancel(3); // destroy, then reuse ID while the old request is pending
    queue.enqueue(3);
    check(queue.drain(clock, consume, 3, 32) == 3);
    check((activated == std::vector<unsigned>{1, 2, 4, 5}));
    check(queue.drain(clock, consume, 0, 32) == 1);
    check(activated.back() == 3 && queue.size() == 0);
    queue.enqueue(8); queue.enqueue(9);
    check(queue.drain(clock, consume, 100, 1) == 1 && queue.contains(9));
    queue.ready = true;
    queue.clear(); // same IDs loaded into a different world must not inherit work
    check(!queue.ready && queue.size() == 0);
    queue.enqueue(9);
    check(queue.drain(clock, consume, 100, 32) == 1);
    queue.enqueue(10); queue.enqueue(11);
    check(queue.drain(clock, [&](unsigned id) {
        check(id == 10); queue.clear(); queue.enqueue(12);
    }, 100, 32) == 1); // reset from callback cannot consume the new world's work
    check(queue.contains(12));
    queue.clear();
    for (unsigned id = 0; id < 100; ++id) { queue.enqueue(id); queue.cancel(id); }
    unsigned callbacks = 0;
    check(queue.drain(clock, [&](unsigned) { ++callbacks; }, 100, 32) == 32);
    check(callbacks == 0); // stale cleanup has an attempt cap
    queue.clear();
    queue.enqueue(50); queue.enqueue(51);
    check(queue.drain(clock, [&](unsigned) { time += 50; }, 3, 32) == 1);
    check(queue.contains(51)); // indivisible overrun stops the next activation
    queue.set_level(1);
    check(queue.size() == 0 && !queue.ready);
    queue.enqueue(52); queue.ready = true;
    queue.set_level(1);
    check(queue.contains(52) && queue.ready);
    queue.set_level(2);
    check(queue.size() == 0 && !queue.ready);
    std::cout << "FIFO, deduplication, ID reuse, reset, stale cleanup and budgets passed\n";
}
