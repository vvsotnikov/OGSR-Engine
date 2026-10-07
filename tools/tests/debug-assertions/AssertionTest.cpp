// Control only the fixture configuration; the selection and VERIFY implementation
// below are the same headers used by xrCore.
#undef _DEBUG
#undef DEBUG
#undef NDEBUG
#ifdef ENABLE_DEBUG_CASE
#define _DEBUG
#endif
#include "../../../ogsr_engine/xrCore/debug_assertion_config.h"

struct FailureRecorder
{
    unsigned failures = 0;
    template <typename... Args> void fail(Args...) { ++failures; }
} Debug;
#include "../../../ogsr_engine/xrCore/xrDebug_macros.h"

int main()
{
    unsigned evaluated = 0;
    VERIFY(++evaluated == 0);
#ifdef DEBUG
    return evaluated == 1 && Debug.failures == 1 ? 0 : 1;
#else
    return evaluated == 0 && Debug.failures == 0 ? 0 : 1;
#endif
}
