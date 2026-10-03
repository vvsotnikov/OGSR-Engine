#pragma once

#include <cstdint>
#include <deque>
#include <map>

// Runtime-only requests owned by the object registry. Cancellation invalidates
// the ticket, including when an object ID is immediately reused.
class ALifeActivationQueue
{
    struct Request { std::uint16_t id; std::uint64_t ticket; };
    std::deque<Request> m_requests;
    std::map<std::uint16_t, std::uint64_t> m_pending;
    std::uint64_t m_ticket = 0;
    std::uint64_t m_epoch = 0;
    std::uint32_t m_level = ~std::uint32_t(0);

public:
    bool ready = false;
    void set_level(std::uint32_t level)
    {
        if (level == m_level) return;
        clear();
        m_level = level;
    }
    bool contains(std::uint16_t id) const { return m_pending.find(id) != m_pending.end(); }
    void enqueue(std::uint16_t id)
    {
        if (contains(id)) return;
        const auto ticket = ++m_ticket;
        m_pending.emplace(id, ticket);
        m_requests.push_back({id, ticket});
    }
    void cancel(std::uint16_t id) { m_pending.erase(id); }
    void clear()
    {
        m_requests.clear();
        m_pending.clear();
        ++m_epoch;
        ready = false;
    }
    std::size_t size() const { return m_pending.size(); }

    // Time is milliseconds. Always attempt one item for progress. A single
    // activation (including its children/group) is indivisible and may overrun.
    template <typename Clock, typename Consume>
    unsigned drain(Clock clock, Consume consume, double budget_ms, unsigned limit)
    {
        const auto epoch = m_epoch;
        const auto start = clock();
        unsigned attempts = 0;
        while (!m_requests.empty() && attempts < limit && epoch == m_epoch)
        {
            if (attempts && clock() - start >= budget_ms) break;
            const auto request = m_requests.front();
            m_requests.pop_front();
            ++attempts; // stale entries count too, bounding cleanup work
            const auto found = m_pending.find(request.id);
            if (found == m_pending.end() || found->second != request.ticket) continue;
            m_pending.erase(found);
            consume(request.id);
        }
        return attempts;
    }
};
