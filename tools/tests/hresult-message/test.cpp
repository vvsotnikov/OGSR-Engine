#include <comdef.h>
#include <cstdio>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

struct xrDebug { std::string DXerror2string(HRESULT code) const; };
#include "method.inc"

void check(bool condition)
{
    if (!condition) throw std::runtime_error("HRESULT text lifetime regression");
}

void exercise()
{
    xrDebug debug;
    // Derive expectations from live owners, independent of Windows language.
    _com_error unregistered(REGDB_E_CLASSNOTREG), denied(E_ACCESSDENIED);
    const std::string expected = unregistered.ErrorMessage();
    const std::string other = denied.ErrorMessage();
    const auto retained = debug.DXerror2string(REGDB_E_CLASSNOTREG);
    check(!retained.empty() && retained == expected);
    for (int i = 0; i < 1000; ++i)
    {
        const auto next = debug.DXerror2string(E_ACCESSDENIED);
        std::vector<std::string> churn(32, std::string(expected.size(), 'x'));
        check(next == other && retained == expected);
        char message[4096];
        std::snprintf(message, sizeof(message), "%s | %s",
            debug.DXerror2string(REGDB_E_CLASSNOTREG).c_str(), debug.DXerror2string(E_ACCESSDENIED).c_str());
        check(message == expected + " | " + other);
    }
}

int main()
{
    exercise();
    std::vector<std::thread> threads;
    for (int i = 0; i < 4; ++i) threads.emplace_back(exercise);
    for (auto& thread : threads) thread.join();
    std::cout << "Owned messages survive later calls and allocation churn; concurrent formatting passed\n";
}
