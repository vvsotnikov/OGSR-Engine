#include <map>
#include <vector>
#include <iostream>

struct Object
{
    std::vector<Object>* peers;
    bool alive = true;
    unsigned callbacks = 0, deletions = 0;
    bool& failed;
    void on_unregister()
    {
        ++callbacks;
        // A callback may dereference any peer, regardless of registry ID order.
        for (const auto& peer : *peers)
            if (!peer.alive) failed = true;
    }
};
// Record destruction without freeing fixture storage so a regression fails
// deterministically instead of making the test itself dereference freed memory.
void xr_delete(Object*& object)
{
    for (const auto& peer : *object->peers)
        if (peer.callbacks != 1) object->failed = true;
    object->alive = false;
    ++object->deletions;
    object = nullptr;
}
struct CALifeObjectRegistry
{
    using OBJECT_REGISTRY = std::map<unsigned, Object*>;
    OBJECT_REGISTRY m_objects;
    ~CALifeObjectRegistry();
};
#include "registry-destructor.inc"

int main()
{
    for (unsigned count : {0u, 1u, 3u})
        for (bool reverse : {false, true})
        {
            bool failed = false;
            std::vector<Object> objects;
            for (unsigned i = 0; i < count; ++i)
                objects.push_back({&objects, true, 0, 0, failed});
            {
                CALifeObjectRegistry registry;
                for (unsigned i = 0; i < count; ++i)
                    registry.m_objects.emplace(reverse ? count - i : i, &objects[i]);
            }
            for (const auto& object : objects)
                if (object.alive || object.callbacks != 1 || object.deletions != 1) failed = true;
            if (failed)
            {
                std::cerr << "Unsafe registry teardown: count=" << count << " reverse=" << reverse << '\n';
                return 1;
            }
        }
    std::cout << "Registry callbacks preserve peer lifetime in both ID orders\n";
}
