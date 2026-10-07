#pragma once

inline std::string get_string(const Fvector& value)
{
    return make_string("(%g, %g, %g)", value.x, value.y, value.z);
}
inline std::string get_string(const Fmatrix& value)
{
    return make_string("[%g %g %g %g; %g %g %g %g; %g %g %g %g; %g %g %g %g]",
        value._11, value._12, value._13, value._14, value._21, value._22, value._23, value._24,
        value._31, value._32, value._33, value._34, value._41, value._42, value._43, value._44);
}
inline std::string dump_string(const char* name, const Fmatrix& value)
{
    return std::string(name) + ": " + get_string(value);
}
