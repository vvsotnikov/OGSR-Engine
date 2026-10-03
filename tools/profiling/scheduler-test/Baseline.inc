// Frozen pre-compaction ProcessStep from ea325cc57; provenance only, no Git dependency.
void CSheduler::ProcessStep()
{
    ZoneScoped;

    // Normal priority
    u32 dwTime = Device.dwTimeGlobal;

    const bool prefetch = Device.dwPrecacheFrame > 0;
    decltype(Items) ItemsProcessed;
    bool stopped{};
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

        Items.erase(Items.begin() + (--it));

        if (skip || !shed_need)
        {
            continue;
        }

        __try
        {
            // Calc next update interval
            const u32 dwMin = std::max(30u, curr.Object->shedule.t_min);
            const u32 dwMax = (1000u + curr.Object->shedule.t_max) / 2;

            const float scale = curr.Object->shedule_Scale();

            u32 dwUpdate = dwMin + iFloor(float(dwMax - dwMin) * scale);
            clamp(dwUpdate, std::max(dwMin, 20u), dwMax);

            const u32 elapsed = dwTime - curr.dwTimeOfLastExecute;

            m_current_step_obj = curr.Object;

            // if (!Core.DebugFlags.test(xrCore::dbg_DisableObjectsScheduler))
            curr.Object->shedule_Update(std::clamp(elapsed, 1u, std::max(curr.Object->shedule.t_max, 1000u)));

            if (!m_current_step_obj)
            {
                continue;
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
            curr.Object = nullptr;
            continue;
        }

        if (!prefetch && t_total.GetElapsed_ms() > static_cast<u32>(std::floor(psShedulerCurrent)))
        {
            // we have maxed out the load - increase heap
            psShedulerTarget += (psShedulerReaction * 3);

            // if (Core.DebugFlags.test(xrCore::dbg_TraceScheduler))
            {
                // Msg("Break ProcessStep. Processed: [%u], left in queue: [%u]", ItemsProcessed.size(), Items.size());
                if (ItemsProcessed.size() == 1) // кто то жрет все время на кадре
                    Msg("! Single item [%s] took whole update frame!!!", ItemsProcessed.front().scheduled_name.c_str());
            }

            stopped = true;
            break;
        }
    }

    //if (/*Core.DebugFlags.test(xrCore::dbg_TraceScheduler) &&*/ !prefetch && t_total.GetElapsed_ms() > 20)
    //    Msg("Long ProcessStep !!! duration [%u]ms. updated: [%u] objects!", t_total.GetElapsed_ms(), cnt);

    //if (prefetch)
    //    Msg("Prefetch frame, updated: [%u] objects!", cnt);

    // Push "processed" back
    Items.insert(Items.end(), std::make_move_iterator(ItemsProcessed.begin()), std::make_move_iterator(ItemsProcessed.end()));

    if (!stopped)
    {
        // always try to decrease target
        psShedulerTarget -= psShedulerReaction;
    }
}
