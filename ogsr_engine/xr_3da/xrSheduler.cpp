#include "stdafx.h"
#include "xrSheduler.h"
#include "xr_object.h"

float psShedulerCurrent = 10.f;
float psShedulerTarget = 10.f;
float psShedulerMax = 10.f;
constexpr float psShedulerReaction = 1.f; // 0.1f;

void CSheduler::Initialize() { m_processing_now = false; }

void CSheduler::Destroy()
{
    internal_Registration();

    ItemsRT.clear();
    Items.clear();
    Registration.clear();
}

void CSheduler::internal_Registration()
{
    for (u32 it = 0; it < Registration.size(); it++)
    {
        ItemReg& R = Registration[it];
        if (R.OP)
        {
            // register
            // search for paired "unregister"

            BOOL bFoundAndErased = FALSE;
            for (u32 pair = it + 1; pair < Registration.size(); pair++)
            {
                ItemReg& R_pair = Registration[pair];
                if ((!R_pair.OP) && (R_pair.Object == R.Object))
                {
                    bFoundAndErased = TRUE;
                    Registration.erase(Registration.begin() + pair);
                    break;
                }
            }

            // register if non-paired
            if (!bFoundAndErased)
            {
                //Msg("SCHEDULER: internal register [%s][%x][%s]", *R.Object->shedule_Name(), R.Object, R.RT ? "true" : "false");
                internal_Register(R.Object, R.RT);
            }
            //else
            //    Msg("SCHEDULER: internal register skipped, because unregister found [%s][%x][%s]", "unknown", R.Object, R.RT ? "true" : "false");
        }
        else
        {
            // unregister
            internal_Unregister(R.Object, R.RT);
        }
    }

    Registration.clear();
}

void CSheduler::internal_Register(ISheduled* object, BOOL RT)
{
    VERIFY(!object->shedule.b_locked);

    if (RT)
    {
        // Fill item structure
        auto& TNext = ItemsRT.emplace_back();
        TNext.dwTimeForExecute = Device.dwTimeGlobal;
        TNext.dwTimeOfLastExecute = Device.dwTimeGlobal;
        TNext.Object = object;
        TNext.scheduled_name = object->shedule_Name();
        object->shedule.b_RT = TRUE;
    }
    else
    {
        // Fill item structure && Insert into priority Queue
        auto& TNext = Items.emplace_back();
        TNext.dwTimeForExecute = Device.dwTimeGlobal;
        TNext.dwTimeOfLastExecute = Device.dwTimeGlobal;
        TNext.Object = object;
        TNext.scheduled_name = object->shedule_Name();
        object->shedule.b_RT = FALSE;
    }
}

bool CSheduler::internal_Unregister(const ISheduled* object, BOOL RT)
{
    if (RT)
    {
        for (u32 i = 0; i < ItemsRT.size(); i++)
        {
            if (ItemsRT[i].Object == object)
            {
                // Callbacks may remove this entry or a neighbor during RT dispatch.
                // Keep vector references stable until traversal has finished.
                if (m_processing_now)
                    ItemsRT[i].Object = nullptr;
                else
                    ItemsRT.erase(ItemsRT.begin() + i);
                return true;
            }
        }
    }
    else
    {
        for (auto& Item : Items)
        {
            if (Item.Object == object)
            {
                Item.Object = nullptr;
                return true;
            }
        }
    }

    if (m_current_step_obj == object)
    {
        m_current_step_obj = nullptr;
        return true;
    }

    return false;
}

#ifdef DEBUG
bool CSheduler::Registered(ISheduled* object) const
{
    // Membership includes the detached current callback and the temporary
    // processed queue, then pending operations in the order they were requested.
    size_t count = m_current_step_obj == object ? 1 : 0;
    const auto matches = [object](const xr_vector<Item>& items) {
        return std::count_if(items.begin(), items.end(), [object](const Item& item) { return item.Object == object; });
    };
    count += matches(ItemsRT) + matches(Items);
    if (m_debug_processed)
        count += matches(*m_debug_processed);
    VERIFY(count <= 1);
    for (const auto& operation : Registration)
    {
        if (operation.Object != object)
            continue;
        VERIFY(operation.OP ? count == 0 : count == 1);
        count = operation.OP ? 1 : 0;
    }
    return count != 0;
}
#endif // DEBUG

void CSheduler::Register(ISheduled* A, BOOL RT)
{
    VERIFY(!Registered(A));

    auto& R = Registration.emplace_back();
    R.OP = TRUE;
    R.RT = RT;
    R.Object = A;
    R.Object->shedule.b_RT = RT;

    //Msg("SCHEDULER: register [%s][%x]", *A->shedule_Name(), A);
}

void CSheduler::Unregister(ISheduled* A, bool force)
{
    VERIFY(Registered(A));

    if (m_processing_now || force)
    {
        if (internal_Unregister(A, A->shedule.b_RT))
            return;
    }

    auto& R = Registration.emplace_back();
    R.OP = FALSE;
    R.RT = A->shedule.b_RT;
    R.Object = A;
}

void CSheduler::ProcessStep()
{
    ZoneScopedN("CSheduler::ProcessStep");

    // Normal priority
    u32 dwTime = Device.dwTimeGlobal;

    const bool prefetch = Device.dwPrecacheFrame > 0;
    decltype(Items) ItemsProcessed;
#ifdef DEBUG
    m_debug_processed = &ItemsProcessed;
#endif
    bool stopped{};
    size_t objects_evaluated{};
    //size_t cnt{};
    CTimer t_total;
    t_total.Start();

    for (size_t it{}; it < Items.size();)
    {
        Item curr = Items.at(it++);
        bool skip{curr.Object == nullptr}, shed_need{true};

        if (curr.dwTimeForExecute >= dwTime)
        {
            continue;
        }

        if (!skip)
        {
            ++objects_evaluated;
            __try
            {
                shed_need = curr.Object->shedule_Needed();
            }
            __except (ExceptStackTrace("[CSheduler::ProcessStep] stack trace:\n"))
            {
                Msg("Scheduler tried to update object %s", *curr.scheduled_name);
                skip = true;
            }
        }

        if (!Items[it - 1].Object) // The needed callback may unregister (and destroy) this object.
            skip = true;

        // Hide processed slots from Unregister just as erasing them would.
        // Remove the tombstones together below, preserving survivor order.
        Items[it - 1].Object = nullptr;

        // All callback exits converge on the budget check below.
        do
        {
            if (skip || !shed_need)
            {
                break;
            }

            __try
            {
                m_current_step_obj = curr.Object;

                // Calc next update interval
                const u32 dwMin = std::max(30u, curr.Object->shedule.t_min);
                const u32 dwMax = (1000u + curr.Object->shedule.t_max) / 2;

                const float scale = curr.Object->shedule_Scale();
                if (!m_current_step_obj) // Scale callbacks may unregister (and destroy) the object.
                    break;

                u32 dwUpdate = dwMin + iFloor(float(dwMax - dwMin) * scale);
                clamp(dwUpdate, std::max(dwMin, 20u), dwMax);

                const u32 elapsed = dwTime - curr.dwTimeOfLastExecute;

                // if (!Core.DebugFlags.test(xrCore::dbg_DisableObjectsScheduler))
                curr.Object->shedule_Update(std::clamp(elapsed, 1u, std::max(curr.Object->shedule.t_max, 1000u)));

                if (!m_current_step_obj)
                {
                    break;
                }

                m_current_step_obj = nullptr;

                // Fill item structure
                auto& next = ItemsProcessed.emplace_back();
                next.dwTimeForExecute = dwTime + dwUpdate;
                next.dwTimeOfLastExecute = dwTime;
                next.Object = curr.Object;
                next.scheduled_name = curr.Object->shedule_Name();

                //cnt++;
            }
            __except (ExceptStackTrace("[CSheduler::ProcessStep2] stack trace:\n"))
            {
                Msg("Scheduler tried to update object %s", *curr.scheduled_name);
                m_current_step_obj = nullptr;
                break;
            }
        } while (false);

        if (!prefetch && t_total.GetElapsed_ms() > static_cast<u32>(std::floor(psShedulerCurrent)))
        {
            // we have maxed out the load - increase heap
            psShedulerTarget += (psShedulerReaction * 3);

            if (objects_evaluated == 1)
                Msg("! Single item [%s] took whole update frame!!!", curr.scheduled_name.c_str());

            stopped = true;
            break;
        }
    }

    //if (/*Core.DebugFlags.test(xrCore::dbg_TraceScheduler) &&*/ !prefetch && t_total.GetElapsed_ms() > 20)
    //    Msg("Long ProcessStep !!! duration [%u]ms. updated: [%u] objects!", t_total.GetElapsed_ms(), cnt);

    //if (prefetch)
    //    Msg("Prefetch frame, updated: [%u] objects!", cnt);

    // Push "processed" back
    Items.erase(std::remove_if(Items.begin(), Items.end(), [](const Item& item) { return !item.Object; }), Items.end());
    Items.insert(Items.end(), std::make_move_iterator(ItemsProcessed.begin()), std::make_move_iterator(ItemsProcessed.end()));
#ifdef DEBUG
    m_debug_processed = nullptr;
#endif

    if (!stopped)
    {
        // always try to decrease target
        psShedulerTarget -= psShedulerReaction;
    }
}

void CSheduler::Update()
{
    ZoneScoped;

    // Initialize
    Device.Statistic->Sheduler.Begin();

    internal_Registration();

    m_processing_now = true;

    u32 dwTime = Device.dwTimeGlobal;

    {
        ZoneScopedN("ItemsRT");

        // Realtime priority
        for (auto& curr : ItemsRT)
        {
            if (!curr.Object)
                continue;

            const bool needed = curr.Object->shedule_Needed();
            if (!curr.Object) // The needed callback may unregister this entry.
                continue;

            if (!needed)
            {
                curr.dwTimeOfLastExecute = dwTime;
                continue;
            }

            const u32 elapsed = dwTime - curr.dwTimeOfLastExecute;
            curr.Object->shedule_Update(elapsed);
            curr.dwTimeOfLastExecute = dwTime;
        }
    }

    // Normal (sheduled)
    ProcessStep();

    clamp(psShedulerTarget, 3.f, psShedulerMax);

    psShedulerCurrent = 0.9f * psShedulerCurrent + 0.1f * psShedulerTarget;
    Device.Statistic->fShedulerLoad = psShedulerCurrent;

    ItemsRT.erase(std::remove_if(ItemsRT.begin(), ItemsRT.end(), [](const Item& item) { return !item.Object; }), ItemsRT.end());
    m_processing_now = false;

    internal_Registration();

    Device.Statistic->Sheduler.End();
}
