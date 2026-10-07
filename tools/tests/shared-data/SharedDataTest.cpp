#include <map>
#include <stdexcept>
#include <utility>
#include <vector>

using LPCSTR = const char*;
template <typename K, typename V> using xr_map = std::map<K, V>;
template <typename T, typename... A> T* xr_new(A&&... args) { return new T(std::forward<A>(args)...); }
template <typename T> void xr_delete(T*& pointer) { delete pointer; pointer = nullptr; }
#define mk_pair std::make_pair
#define VERIFY(condition) check(condition)
void check(bool condition) { if (!condition) throw std::runtime_error("shared-data ownership invariant failed"); }
template <typename... A> void Msg(A...) {}
#include "../../../ogsr_engine/COMMON_AI/shared_data.h"

struct Resource : CSharedResource
{
    static inline unsigned destroyed = 0;
    ~Resource() { ++destroyed; }
};

int main()
{
    using Manual = CSharedClass<Resource, int, false>;
    {
        Manual original;
        original.load_shared(1, nullptr);
        auto* first = original.get_sd();
        {
            Manual copy(original);
            check(copy.get_sd() == first);
            Manual assigned;
            assigned.load_shared(2, nullptr);
            assigned = copy;
            assigned = assigned;
            check(assigned.get_sd() == first);
            std::vector<Manual> articles;
            for (int i = 0; i < 100; ++i) articles.push_back(copy);
            articles.erase(articles.begin(), articles.begin() + 50);
            check(Resource::destroyed == 0);
        }
        check(original.get_sd() == first && Resource::destroyed == 0);
    }
    Manual::DeleteSharedData(); // Must have exactly zero owners after vector relocation and destruction.
    check(Resource::destroyed == 2);

    using Automatic = CSharedClass<Resource, int, true>;
    {
        Automatic original;
        original.load_shared(3, nullptr);
        {
            Automatic copy(original);
            Automatic assigned;
            assigned = copy;
            check(Resource::destroyed == 2);
        }
        check(Resource::destroyed == 2); // A copy's destruction must not free the original's data.
    }
    check(Resource::destroyed == 3);
}
