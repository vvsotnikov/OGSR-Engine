#include "stdafx.h"
#include "xrSheduler.h"
#include "xr_object.h"

ISheduled::ISheduled()
{
    shedule.t_min = 20;
    shedule.t_max = 1000;
    shedule.b_locked = FALSE;
    shedule.b_registered = FALSE;
    shedule.b_retired = FALSE;
#ifdef DEBUG
    dbg_update_shedule = u32(-1);
#endif
}

ISheduled::~ISheduled()
{
    VERIFY2(!Engine.Sheduler.Registered(this), make_string("%p : %s", static_cast<void*>(this), *shedule_Name()));

    // sad, but true
    // we need this to become MASTER_GOLD
#ifndef DEBUG
    if (shedule.b_registered || shedule.b_retired)
        Engine.Sheduler.Unregister(this);
#endif // DEBUG
}

void ISheduled::shedule_register() { Engine.Sheduler.Register(this); }

void ISheduled::shedule_unregister(bool force) { Engine.Sheduler.Unregister(this, force); }

void ISheduled::shedule_Update(u32 dt)
{
#ifdef DEBUG
    if (Device.dwFrame == dbg_update_shedule)
    {
        LPCSTR name = "unknown";
        CObject* O = smart_cast<CObject*>(this);
        if (O)
            name = *O->cName();
        Debug.fatal(DEBUG_INFO, "'shedule_Update' called twice per frame for %s", name);
    }
    dbg_update_shedule = Device.dwFrame;
#endif
}
