#include <cassert>
#include <map>
#include <stdexcept>
#define IC
#define VERIFY(condition) do { if (!(condition)) throw std::runtime_error("iterator invariant"); } while (false)
using u32 = unsigned;
struct SliceIterator
{
    using _iterator = std::map<int, int>::iterator;
    std::map<int, int> m_objects{{1, 0}, {2, 0}, {3, 0}};
    _iterator cursor = m_objects.begin();
    bool m_first_update = false;
    bool expired = true;
    unsigned m_cycle_count = 0;
    bool empty() const { return m_objects.empty(); }
    void start_timer() {}
    bool time_over() const { return expired && !m_first_update; }
    _iterator& next() { return cursor; }
    void update_next() { if (++cursor == m_objects.end()) cursor = m_objects.begin(); }
    template <typename Predicate> u32 update(const Predicate&);
};
#include "slice.inc"
struct Predicate
{
    bool operator()(SliceIterator::_iterator entry, unsigned cycle, bool) const { return entry->second != int(cycle); }
    void operator()(SliceIterator::_iterator entry, unsigned cycle) const { entry->second = int(cycle); }
};
int main()
{
    SliceIterator iterator;
    Predicate predicate;
    for (int i = 0; i < 3; ++i)
        if (iterator.update(predicate) != 1) return 1;
    for (const auto& entry : iterator.m_objects)
        if (entry.second == 0) return 2;
    iterator.expired = false;
    if (iterator.update(predicate) != 3) return 3;
    iterator.expired = true;
    iterator.m_first_update = true;
    if (iterator.update(predicate) != 3) return 4;
    iterator.m_objects.clear();
    if (iterator.update(predicate) != 0) return 5;
}
