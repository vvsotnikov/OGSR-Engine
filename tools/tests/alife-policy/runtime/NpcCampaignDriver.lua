-- The seed was saved by the pre-migration engine with three real camp jobs.
-- This driver never enrolls a planner or supplies it with destination knowledge.
return function(cfg)
    local stage, started, since, sent = cfg.stage or 0, nil, nil, false
    local positioned=false
    local radius = ini_file("scripts\\npc_campaign.ltx"):r_float("esc_farm_lager", "home_radius")
    local outside, outside_since, outside_complete
    local camp_displaced, return_seen, rest_since, no_supply_since
    local rest_gate_started
    local function check_home(id, camp)
        local point = vector()
        assert(alife():supply_trip_home(id, point), "Missing planner home: " .. id)
        assert(point:distance_to(camp.position) <= radius + 0.001, "Planner home outside configured camp radius")
    end
    local inventory_reset_at
    local supplies, owners = cfg.supplies or {}, cfg.owners or {}
    local combat_started, combat_seen, combat_released = nil, false, false
    local npcs, camp_id, item, winner = cfg.npcs, cfg.camp, cfg.item, cfg.winner
    local function server(id) return assert(alife():object(id), "Missing server object "..id) end
    local function persist(next_stage)
        local f=assert(io.open(getFS():update_path("$app_data_root$","npc-campaign-state.lua"),"w"))
        f:write(string.format("return {stage=%d,camp=%d,npcs={%d,%d,%d},item=%s,winner=%s,supplies={%s},owners={%s}}",
            next_stage,camp_id,npcs[1],npcs[2],npcs[3],tostring(item),tostring(winner),table.concat(supplies,","),table.concat(owners,",")))
        f:close(); sent=true
    end
    local function reload(next_stage)
        persist(next_stage)
        get_console():execute("save npc_campaign_pending")
        get_console():execute("load npc_campaign_pending")
    end
    local function depart(next_stage, map)
        persist(next_stage); get_console():execute("jump_to_level "..map)
    end
    local function newcomer(camp)
        local respawner
        for id=0,65534 do
            local o=alife():object(id)
            if o and o:name()=="esc2_village_stalker_respawn" then respawner=o; break end
        end
        assert(respawner,"Missing campaign respawner")
        -- Move only the spawn origin for this fixture. Selection, acceptance,
        -- tracking and the new NPC's binder are the actual campaign code.
        local p,l,g=respawner.position,respawner.m_level_vertex_id,respawner.m_game_vertex_id
        respawner.position=camp.position
        respawner.m_level_vertex_id=camp.m_level_vertex_id
        respawner.m_game_vertex_id=camp.m_game_vertex_id
        local count=#respawner.spawned_obj
        local accepted=respawner:create(100)
        respawner.position=p;respawner.m_level_vertex_id=l;respawner.m_game_vertex_id=g
        if not accepted then
            assert(#respawner.spawned_obj==count,"Rejected spawn changed respawner tracking")
            return nil
        end
        assert(#respawner.spawned_obj==count+1,"Accepted spawn lost respawner tracking")
        return server(respawner.spawned_obj[#respawner.spawned_obj])
    end
    local function tick()
        if sent or not db.actor or not app_ready() or device().precache_frame~=0 then return end
        local now=time_global()
        if not started then
            started=now; get_console():execute("g_god on"); level.disable_input()
        end
        assert(now-started<150000,"Campaign test timed out at stage "..stage)
        local camp=server(camp_id)
        assert(camp:name()=="esc_farm_lager","Seed camp binding changed")
        if level.name()=="l01_escape" and not positioned then
            local observer=level.vertex_in_direction(camp.m_level_vertex_id,vector():set(-1,0,0),30)
            local p=level.vertex_position(observer)
            db.actor:set_actor_position(vector():set(p.x,p.y+1.1,p.z))
            local resident=level.object_by_id(npcs[1])
            if not resident then return end
            for id=0,65534 do
                local n=alife():object(id)
                local client=level.object_by_id(id)
                if n and client and id~=db.actor:id() and (IsStalker(n) or IsMonster(n))
                    and n.position:distance_to(camp.position)<150 and client:alive()
                    and client:relation(resident)==game_object.enemy then
                    alife():release(n,true)
                end
            end
            positioned=true
        end
        for _,id in ipairs(npcs) do
            if stage<5 or id~=winner then
                local n=server(id)
                assert(n:alive(),"Resident unexpectedly died")
                local client=level.object_by_id(id)
                if client then
                    -- Keep ambient encounters out of this persistence test.
                    -- Combat arbitration has its own native gameplay scenario.
                    client:invulnerable(true)
                    if not combat_started or combat_released or id ~= npcs[1] then
                        client:set_enemy_callback(function() return false end)
                    end
                end
                if alife():supply_trip_phase(id)<0 then assert(stage==0,"Lost persistent ownership"); return end
                assert(n:smart_terrain_id()==65535,"Legacy job reclaimed resident")
                assert(not camp.npc_info[id],"Legacy camp retained migrated resident")
                if stage==0 then
                    local st=db.storage[id]
                    if not st or not st.ini then return end
                    assert(not st.active_section and st.gulag_name=="","Camp script still owns execution")
                end
            end
        end
        if stage==0 then
            if not since then
                if not camp_displaced then
                    if not rest_gate_started then rest_gate_started = now end
                    for _, id in ipairs(npcs) do
                        if alife():supply_trip_phase(id) ~= 7 then
                            rest_since = nil
                            assert(now - rest_gate_started < 60000, "Resident did not settle at home: " .. id .. " phase=" .. alife():supply_trip_phase(id))
                            return
                        end
                    end
                    if not rest_since then rest_since = now; return end
                    if now - rest_since < 3000 then return end
                    log1("[npc campaign fixture] residents_resting")
                    local client = assert(level.object_by_id(npcs[1]))
                    local home = vector()
                    assert(alife():supply_trip_home(npcs[1], home), "Missing resident home")
                    local destination
                    for _, direction in ipairs({vector():set(1,0,0),vector():set(-1,0,0),vector():set(0,0,1),vector():set(0,0,-1)}) do
                        local node = level.vertex_in_direction(client:level_vertex_id(), direction, 12)
                        local p = level.vertex_position(node)
                        if p:distance_to(home) > 5 then destination = p; break end
                    end
                    assert(destination, "No reachable camp displacement point")
                    client:set_npc_position(destination, true)
                    camp_displaced = true
                    return
                end
                local phase = alife():supply_trip_phase(npcs[1])
                if phase == 2 then return_seen = true end
                if phase ~= 7 or not return_seen then return end
                local home = vector()
                assert(alife():supply_trip_home(npcs[1], home), "Missing resident home")
                assert(level.object_by_id(npcs[1]):position():distance_to(home) <= 3, "Rest reported away from home")
                log1("[npc campaign fixture] displaced_resident_returned")
                since=now
                local extra=newcomer(camp)
                if extra then
                    assert(extra:smart_terrain_id()~=camp.id,"Migration opened an extra camp slot")
                    alife():release(extra,true)
                end
                for _,id in ipairs(npcs) do
                    local client=assert(level.object_by_id(id))
                    xr_logic.pstor_store(client,"campaign_fixture",42)
                    check_home(id, camp)
                end
                local fighter = assert(level.object_by_id(npcs[1]))
                fighter:set_goodwill(-10000, db.actor)
                fighter:set_enemy_callback(function(_, enemy) return enemy:id() == db.actor:id() end)
                local stimulus = hit()
                stimulus.draftsman, stimulus.type, stimulus.power, stimulus.impulse = db.actor, hit.fire_wound, 0.01, 0
                stimulus.direction = vector():set(1, 0, 0)
                fighter:hit(stimulus)
                combat_started = now
                log1("[npc campaign fixture] legacy_migrated_capacity_preserved")
            end
            if not combat_released then
                local fighter = assert(level.object_by_id(npcs[1]))
                if fighter:best_enemy() then combat_seen = true end
                if now - combat_started < 20000 then return end
                assert(combat_seen, "Migrated resident never entered combat")
                fighter:set_enemy_callback(function() return false end)
                fighter:set_relation(game_object.neutral, db.actor)
                combat_released = true
                inventory_reset_at = now
                log1("[npc campaign fixture] combat_released")
                for _, id in ipairs(npcs) do
                    local client = assert(level.object_by_id(id))
                    local remove = {}
                    client:iterate_inventory(function(_, it)
                        if it:section() == "bandage" then remove[#remove + 1] = it:id() end
                    end, client)
                    for _, item_id in ipairs(remove) do alife():release(server(item_id), true) end
                end
                return
            end
            if #supplies == 0 then
                for _, id in ipairs(npcs) do
                    if assert(level.object_by_id(id)):object("bandage") then
                        assert(now - inventory_reset_at < 3000, "Resident inventory did not clear: " .. id)
                        return
                    end
                end
                for _, id in ipairs(npcs) do
                    if alife():supply_trip_phase(id) ~= 7 then
                        no_supply_since = nil
                        assert(now - inventory_reset_at < 60000, "Unsupplied resident did not return to camp: " .. id)
                        return
                    end
                end
                if not no_supply_since then no_supply_since = now; return end
                if now - no_supply_since < 3000 then return end
                log1("[npc campaign fixture] unsupplied_residents_resting")
                for _, id in ipairs(npcs) do
                    local client = assert(level.object_by_id(id))
                    local node = level.vertex_in_direction(client:level_vertex_id(), client:direction(), 5)
                    supplies[#supplies + 1] = assert(alife():create("bandage", level.vertex_position(node), node,
                        cross_table():vertex(node):game_vertex_id())).id
                end
                item = supplies[1]
            end
            local completed = 0
            for _, id in ipairs(npcs) do
                local owns_supply = false
                for _, supply in ipairs(supplies) do
                    if server(supply).parent_id == id then owns_supply = true end
                end
                if owns_supply and alife():supply_trip_phase(id) == 7 then completed = completed + 1 end
            end
            if completed == #npcs then
                for i, supply in ipairs(supplies) do owners[i] = server(supply).parent_id end
                winner = server(item).parent_id
                log1("[npc campaign fixture] multiple_residents_returned")
                log1("[npc campaign fixture] real_supply_acquired")
                reload(1)
            end
        elseif stage==1 or stage==4 then
            for _,id in ipairs(npcs) do
                local client=level.object_by_id(id)
                if not client or not db.storage[id] or not db.storage[id].ini then return end
                assert(xr_logic.pstor_retrieve(client,"campaign_fixture",0)==42,"Lost binder state")
            end
            assert(#supplies == 3 and #owners == 3, "Missing inventory bindings")
            for i, supply in ipairs(supplies) do
                assert(server(supply).parent_id == owners[i], "Reload changed a resident inventory")
                assert(alife():supply_trip_phase(owners[i]) == 7, "Reload lost resident rest activity")
            end
            if stage==1 then
                log1("[npc campaign fixture] online_reload_preserved")
                depart(2,"l02_garbage")
            else
                log1("[npc campaign fixture] returned_with_same_residents")
                local client=assert(level.object_by_id(winner))
                client:invulnerable(false)
                client:kill(db.actor)
                stage=5; since=now
            end
        elseif stage==2 or stage==3 then
            assert(level.name()=="l02_garbage")
            for _,id in ipairs(npcs) do
                assert(not server(id).online and not level.object_by_id(id),"Resident remained on previous map")
                server(id):brain():update(true)
                assert(alife():supply_trip_phase(id) == 7, "Offline resident lost rest activity")
                assert(server(id):smart_terrain_id()==65535,"Forced legacy update reclaimed resident")
            end
            if now-started<3000 then return end
            if stage==2 then
                log1("[npc campaign fixture] offline_ownership_preserved"); reload(3)
            else
                log1("[npc campaign fixture] offline_reload_preserved"); depart(4,"l01_escape")
            end
        elseif stage==5 then
            if server(winner):alive() then return end
            if now-since<2000 then return end
            local replacement=assert(newcomer(camp),"Respawner rejected a vacant camp")
            assert(replacement:smart_terrain_id()==camp.id,"Death did not release camp capacity")
            for i,id in ipairs(npcs) do if id==winner then npcs[i]=replacement.id end end
            winner=replacement.id;stage=6; since=now
            for _, direction in ipairs({vector():set(1,0,0), vector():set(-1,0,0), vector():set(0,0,1), vector():set(0,0,-1)}) do
                local node = level.vertex_in_direction(camp.m_level_vertex_id, direction, radius + 15)
                local point = level.vertex_position(node)
                if point:distance_to(camp.position) > radius + 5 then
                    outside = point
                    alife():teleport_object(winner, point, node, cross_table():vertex(node):game_vertex_id())
                    break
                end
            end
            assert(outside, "No outside-radius fixture position")
        elseif stage==6 then
            if not outside_complete then
                assert(alife():supply_trip_phase(winner) < 0, "Outside-radius resident migrated")
                local point = vector()
                assert(not alife():supply_trip_home(winner, point), "Unenrolled resident has a planner home")
                local client = level.object_by_id(winner)
                if not client then return end
                -- Hold this real job candidate outside across an eligibility retry.
                client:set_npc_position(outside, true)
                if not npc_sim_bridge.campaign_eligible(winner, camp_id) then
                    outside_since = nil
                    local st = db.storage[winner] or {}
                    assert(now - since < 30000, string.format("Outside candidate not eligible: begun=%s gulag=%s logic=%s active=%s",
                        tostring(camp.gulag.Object_begin_job[winner]), tostring(st.gulag_name), tostring(st.section_logic), tostring(st.active_section)))
                    return
                end
                if not outside_since then outside_since = now end
                if now - outside_since < 11000 then return end
                log1("[npc campaign fixture] outside_radius_rejected npc=" .. winner)
                client:set_npc_position(level.vertex_position(camp.m_level_vertex_id), true)
                outside_complete = true
                return
            end
            if alife():supply_trip_phase(winner)<0 then return end
            check_home(winner, camp)
            assert(server(winner):smart_terrain_id()==65535,"Replacement kept legacy job")
            log1("[npc campaign fixture] real_respawner_replacement_enrolled")
            log1("[npc fixture] complete scenario=campaign")
            sent=true;get_console():execute("quit")
        end
    end
    level.add_call(function()
        local ok,err=xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED "..tostring(err));sent=true;get_console():execute("quit") end
        return false
    end,function() end)
end
