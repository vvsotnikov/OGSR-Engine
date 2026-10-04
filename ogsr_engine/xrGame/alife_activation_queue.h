#pragma once
#include <bitset>
#include <cstddef>
#include <cstdint>
#include <deque>

// Standalone types allow the queue invariant to be tested without engine headers.
// At most one FIFO slot exists per ID. Reused IDs inherit that slot, and the
// consumer must re-evaluate the current object. No pointers or saved state live here.
class ALifeActivationQueue
{
    std::deque<std::uint16_t> m_requests;
    std::bitset<65536> m_queued, m_wanted;
public:
    bool contains(std::uint16_t id) const { return m_wanted[id]; }
    std::size_t size() const { return m_wanted.count(); }
    std::size_t slots() const { return m_requests.size(); }
    void enqueue(std::uint16_t id)
    {
        m_wanted.set(id);
        if (!m_queued[id]) { m_queued.set(id); m_requests.push_back(id); }
    }
    void cancel(std::uint16_t id) { m_wanted.reset(id); }
    void clear() { m_requests.clear(); m_queued.reset(); m_wanted.reset(); }
    // Consumption does not reset the world or recursively drain this queue.
    // One attempt guarantees progress; a single activation remains indivisible.
    template <typename Clock, typename Consume>
    unsigned drain(Clock clock, Consume consume, double budget_ms, unsigned limit)
    {
        const auto start = clock();
        unsigned attempts = 0;
        while (!m_requests.empty() && attempts < limit)
        {
            if (attempts && clock() - start >= budget_ms) break;
            const auto id = m_requests.front(); m_requests.pop_front();
            m_queued.reset(id); ++attempts;
            if (!m_wanted[id]) continue;
            m_wanted.reset(id); consume(id);
        }
        return attempts;
    }
};
