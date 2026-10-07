#include "alife_switch_policy.h"
#include <iostream>
#include <stdexcept>
#include <vector>
#include <string>
struct Operations
{
    bool attached_value, activates, keep, is_online = false, data = true;
    std::vector<std::string> calls;
    bool attached() const { return attached_value; }
    void verify_parent() { calls.push_back("parent"); }
    void verify_offline() { calls.push_back("offline"); }
    void try_online() { calls.push_back("try"); is_online = activates; }
    bool online() const { return is_online; }
    bool keep_data() const { return keep; }
    void clear_data() { calls.push_back("clear"); data = false; }
};
int main()
{
    for (bool attached : {false, true})
        for (bool activates : {false, true})
            for (bool keep : {false, true})
            {
                Operations op{attached, activates, keep};
                alife_switch_policy::manager_online(op);
                std::vector<std::string> expected = attached ? std::vector<std::string>{"parent"} : std::vector<std::string>{"offline", "try"};
                const bool clear = !attached && !activates && !keep;
                if (clear) expected.push_back("clear");
                if (op.calls != expected || op.data == clear)
                { std::cerr << "Manager dispatch/cleanup failed: attached=" << attached << " activates=" << activates << " keep=" << keep << '\n'; return 1; }
            }
    std::cout << "Production manager dispatch and saved-data cleanup passed\n";
}
