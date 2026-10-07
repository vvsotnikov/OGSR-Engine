#pragma once

#define VPUSH(a) a.x, a.y, a.z

void XRCORE_API __cdecl Msg(const char* format, ...);
void XRCORE_API Log(const std::string& msg);
void XRCORE_API Log(const char* msg);
void XRCORE_API Log(const char* msg, const Fvector& dop);
void XRCORE_API Log(const char* msg, const Fmatrix& dop);

using LogCallback = std::function<void(const char*)>;
void XRCORE_API SetLogCB(LogCallback cb);
void CreateLog(BOOL no_log = FALSE);

extern XRCORE_API xr_vector<std::string> LogFile;
extern XRCORE_API string_path logFName;

#ifdef DEBUG
// Legacy diagnostic dumps include scalar values and labels as separate arguments.
inline void Log(const char* label, const char* value) { Msg("%s%s", label, value); }
template <typename T> requires std::is_arithmetic_v<T>
inline void Log(const char* label, T value) { Log(std::string(label) + std::to_string(value)); }
#endif
