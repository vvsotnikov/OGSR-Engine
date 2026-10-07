#pragma once

#if defined(_DEBUG) && !defined(DEBUG) // Visual Studio defines _DEBUG when you specify the /MTd or /MDd option
#define DEBUG
#endif

#if defined(_DEBUG) && defined(NDEBUG)
#error Something strange...
#endif

#if defined(DEBUG) && defined(NDEBUG)
#error Something strange...
#endif

#if defined(_DEBUG) && defined(DISABLE_DBG_ASSERTIONS)
#define NDEBUG
#undef DEBUG
#endif

#if defined(OGSR_REQUIRE_DEBUG_ASSERTIONS) && (!defined(_DEBUG) || !defined(DEBUG) || defined(NDEBUG) || defined(DISABLE_DBG_ASSERTIONS))
#error Local validation requires Debug assertions to be enabled.
#endif
