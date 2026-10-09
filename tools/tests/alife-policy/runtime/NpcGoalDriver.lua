-- Change real world inputs; the production planner owns all NPC travel/collection.
return function(cfg)
    local npc, donor, gift, first, second, third, rival = cfg.npc, cfg.donor, cfg.gift, cfg.first, cfg.second, cfg.third, cfg.rival
    local stage, started, sampled, finished = cfg.stage or 1, nil, nil, false
    local sent, attacked, fought, released, waited
    local switching, switched
    local home
    local function object(id) return id and alife():object(id) end
    local function path(name) return getFS():update_path("$app_data_root$",name) end
    local function transfer(item_id, recipient_id)
        local item = assert(object(item_id))
        if item.parent_id == recipient_id then return true end
        if cfg.offline then return alife():transfer_item_offline(item_id,recipient_id) end
        local owner, recipient, client = level.object_by_id(item.parent_id), level.object_by_id(recipient_id), level.object_by_id(item_id)
        if not owner or not recipient or not client then return false end
        owner:transfer_item(client,recipient)
        return true
    end
    local function ids()
        local file = assert(io.open(path("npc-trip-ids.lua"),"w"))
        file:write(string.format("return {npc=%d,donor=%d,gift=%d,first=%d,second=%d,third=%d,rival=%s,stage=%d,offline=%s}",
            npc,donor,gift,first,second,third,tostring(rival),stage,tostring(cfg.offline)))
        file:close()
    end
    local function save()
        ids(); finished = true
        get_console():execute("save npc_trip_pending")
        log1("[npc fixture] saved_pending")
        get_console():execute("quit")
    end
    local function complete()
        log1("[npc fixture] complete scenario=" .. cfg.scenario)
        finished = true; get_console():execute("quit")
    end
    local function tick()
        if finished or not db.actor or not app_ready() or device().precache_frame ~= 0 then return end
        local now = device():time_global()
        if not started then
            started = now
            home = level.vertex_position(34548)
            assert(level.name() == "l05_bar")
            get_console():execute("g_god on"); level.disable_input()
            db.actor:set_actor_position(vector():set(home.x,home.y+1.1,home.z))
            if not npc then
                local candidates = {}
                for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                    local node = level.vertex_in_direction(34548,vector():set(d[1],0,d[2]),20)
                    if home:distance_to(level.vertex_position(node)) > 6 then candidates[#candidates+1] = node end
                end
                assert(#candidates > 0,"No route")
                table.sort(candidates,function(a,b) return home:distance_to(level.vertex_position(a)) < home:distance_to(level.vertex_position(b)) end)
                local a = candidates[1]
                local b = level.vertex_in_direction(34548,vector():set(1,0,0),4)
                -- Different remembered positions, with the farther source selected second.
                if home:distance_to(level.vertex_position(b)) < home:distance_to(level.vertex_position(a)) then a,b = b,a end
                assert(a ~= b and home:distance_to(level.vertex_position(a)) > 2,"Two distinct sources required")
                local function spawn(section,node,parent)
                    local result = assert(alife():create(section,level.vertex_position(node),node,cross_table():vertex(node):game_vertex_id(),parent or 65535))
                    if cfg.offline then alife():set_switch_online(result.id,false) end
                    return result.id
                end
                npc = spawn("npc_trip_stalker",34548)
                donor = cfg.offline and spawn("npc_trip_stalker",34548) or db.actor:id()
                gift = spawn("bandage",34548,donor)
                first,second,third = spawn("bandage",a),spawn("bandage",b),spawn("bandage",b)
                assert(alife():start_supply_goal(npc))
                assert(alife():remember_supply(npc,first) and alife():remember_supply(npc,second))
                if cfg.scenario == "goal-competition" then
                    rival = spawn("npc_trip_stalker",34548)
                    assert(alife():start_supply_goal(rival))
                    assert(alife():remember_supply(rival,first) and alife():remember_supply(rival,second))
                end
                ids()
            else
                log1("[npc fixture] restored_pending")
            end
        end
        assert(now-started < 240000,"Goal scenario timed out stage=" .. stage)
        local server = assert(object(npc))
        local client = level.object_by_id(npc)
        local here = client and client:position() or server.position
        local phase = alife():supply_trip_phase(npc)
        assert(phase ~= 4 and phase ~= 5,"Goal failed/died")
        if cfg.offline then assert(not server.online,"Offline test activated NPC") end
        if not sampled or now-sampled > 1000 then
            sampled = now
            log1(string.format("[npc goal fixture] stage=%d phase=%d online=%s distance=%.3f",stage,phase,tostring(server.online),here:distance_to(home)))
        end
        if rival then
            if phase == 3 and alife():supply_trip_phase(rival) == 3 then
                local x,y = assert(object(first)).parent_id,assert(object(second)).parent_id
                assert((x == npc and y == rival) or (x == rival and y == npc),"Competing NPCs did not each obtain a distinct item")
                complete()
            end
            return
        end
        if stage == 1 and phase == 0 and (cfg.offline or here:distance_to(home) > 2) then
            if cfg.scenario == "goal-combat" then
                if not attacked then
                    attacked = now
                    client:set_goodwill(-10000,db.actor)
                    client:set_enemy_callback(function(_,enemy) return enemy:id() == db.actor:id() end)
                    local stimulus = hit()
                    stimulus.draftsman,stimulus.type,stimulus.power,stimulus.impulse = db.actor,hit.fire_wound,0.01,0
                    stimulus.direction = vector():set(1,0,0); client:hit(stimulus)
                end
                if client:best_enemy() then fought = true end
                if not fought then return end
            end
            if transfer(gift,npc) then stage,sent = 2,nil; log1("[npc goal fixture] gift_sent") end
        end
        if attacked and not released and now-attacked > 70000 then
            assert(fought)
            client:set_enemy_callback(function() return false end)
            client:set_relation(game_object.neutral,db.actor)
            released = true; log1("[npc fixture] combat_observed")
        end
        if stage == 2 and object(gift).parent_id == npc then
            if cfg.scenario == "goal-switch" and not switched then
                if not switching then
                    alife():set_switch_online(npc,false)
                    switching = true
                elseif not server.online and not client then
                    assert(object(gift).parent_id == npc,"Switch lost inventory")
                    log1("[npc goal fixture] observed_offline")
                    alife():set_switch_online(npc,true)
                    switched = true
                end
                return
            end
            if cfg.scenario == "goal-switch" then
                if not server.online or not client then return end
                if switching then log1("[npc goal fixture] returned_online"); switching = false end
            end
            if cfg.scenario == "goal-save" and (phase == 2 or phase == 3) then save(); return end
            if phase == 3 and (not attacked or released) then
                assert(object(first).parent_id == 65535 and object(second).parent_id == 65535,"Collected despite gift satisfying need")
                if transfer(gift,donor) then stage = 3; log1("[npc goal fixture] gift_removed") end
            end
        elseif stage == 3 and object(gift).parent_id == donor and phase == 0 then
            alife():release(assert(object(first)),true)
            stage = 4; log1("[npc goal fixture] remembered_source_removed")
        elseif stage == 4 and phase == 3 then
            assert(not object(first) and object(second).parent_id == npc,"Did not learn source loss and collect alternative")
            if transfer(second,donor) then stage = 5; log1("[npc goal fixture] alternative_removed") end
        elseif stage == 5 and object(second).parent_id == donor and phase == 6 then
            waited = waited or now
            if now-waited > 3000 then
                if cfg.scenario == "goal-wait-save" then save(); return end
                assert(alife():remember_supply(npc,third))
                stage = 6; log1("[npc goal fixture] new_information")
            end
        elseif stage == 6 and phase == 3 then
            assert(object(third).parent_id == npc and here:distance_to(home) <= 1.6,"New information did not produce a completed trip")
            complete()
        end
    end
    level.add_call(function()
        local ok,err = xpcall(tick,debug.traceback)
        if not ok then log1("[npc fixture] FAILED " .. tostring(err)); finished = true; get_console():execute("quit") end
        return false
    end,function() end)
end
