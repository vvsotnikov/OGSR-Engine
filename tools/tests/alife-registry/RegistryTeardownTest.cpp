#include <map>
#include <iostream>

struct Object
{
    Object* group = nullptr;
    bool alive = true;
    unsigned callbacks = 0, deletions = 0, members = 0;
    bool failed = false;
    void on_unregister()
    {
        ++callbacks;
        // Only a member dereferences its group, as in the engine callback.
        if (group)
        {
            if (!group->alive || group->members != 1) failed = true;
            else --group->members;
        }
    }
};
// Retain fixture storage after simulated destruction to detect the dangling
// group access deterministically, without invoking undefined behavior here.
void xr_delete(Object*& object)
{
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
    for (bool groupFirst : {true, false})
    {
        Object group, member;
        group.members = 1;
        member.group = &group;
        {
            CALifeObjectRegistry registry;
            registry.m_objects.emplace(groupFirst ? 1 : 2, &group);
            registry.m_objects.emplace(groupFirst ? 2 : 1, &member);
        }
        if (member.failed || group.members != 0 || group.alive || member.alive ||
            group.callbacks != 1 || member.callbacks != 1 || group.deletions != 1 || member.deletions != 1)
        {
            std::cerr << "Member callback accessed deleted group: groupFirst=" << groupFirst << '\n';
            return 1;
        }
    }
    std::cout << "Member detaches from live group in both registry ID orders\n";
}
