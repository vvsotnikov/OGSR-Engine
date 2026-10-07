return function(cfg)
    local function path(name) return getFS():update_path("$app_data_root$",name) end
    local fixture=dofile(path("LegacyGroupFixture.lua"))
    local ids=cfg.stage~="setup" and dofile(path("legacy-ids.lua")) or nil
    local phase,start,stable,deadline,done=0,nil,nil,nil,false
    local control_start, seen_online, seen_offline
    local maps={"l05_bar","l02_garbage","l05_bar","l02_garbage","l05_bar"}
    local trip=1
    if cfg.stage=="roundtrip" then
        local f=io.open(path("legacy-roundtrip-phase.txt"),"r")
        if f then trip=assert(tonumber(f:read("*a")));f:close() end
        assert(trip>=1 and trip<=#maps)
    end
    local function advance()
        phase=phase+1; stable=nil; deadline=device():time_global()+30000
        local on={true,true,true,true}; local off={true,true,true,true}
        local group_on,group_off=true,true
        if phase==2 then on[2]=false end
        if phase==3 then on[2]=false;off[2]=false end
        if phase==5 then on[2]=false;off[2]=false end
        if phase==6 then group_on=false end
        if phase==8 then group_on=false;group_off=false end
        if phase==10 then
            assert(level.object_by_id(ids.members[1])):kill(db.actor)
            assert(level.object_by_id(ids.members[3])):kill(db.actor)
        elseif phase==11 then
            alife():release(assert(alife():object(ids.members[4])),true)
        elseif phase==12 then
            get_console():execute("save legacy_group_result")
            log1("[legacy policy] complete stage=policy")
            done=true;get_console():execute("quit");return
        end
        alife():set_switch_online(ids.group,group_on);alife():set_switch_offline(ids.group,group_off)
        for i,id in ipairs(ids.members) do
            if alife():object(id) then
                alife():set_switch_online(id,on[i]);alife():set_switch_offline(id,off[i])
            end
        end
    end
    local function tick()
        if done or not db.actor or not app_ready() or device().precache_frame~=0 then return end
        local now=device():time_global()
        if not start then
            start=now;get_console():execute("g_god on");alife():set_switch_distance(1)
            if cfg.stage=="control" or cfg.stage=="roundtrip" or cfg.stage=="ownership" then alife():set_switch_online(ids.group,true) end
            if cfg.stage=="roundtrip" or cfg.stage=="ownership" then alife():set_switch_online(ids.members[2],false) end
        end
        if now-start<15000 then return end
        if cfg.stage=="setup" then
            ids=fixture.create(cfg.node,cfg.graph)
            local f=assert(io.open(path("legacy-ids.lua"),"w"))
            f:write(string.format("return {group=%d,members={%s}}",ids.group,table.concat(ids.members,",")));f:close()
            get_console():execute("save legacy_group_fixture")
            log1(string.format("[legacy policy] complete stage=setup group=%d members=%s",ids.group,table.concat(ids.members,",")))
            done=true;get_console():execute("quit");return
        end
        if cfg.stage=="control" then
            local group=assert(alife():object(ids.group))
            if not control_start then control_start=now end
            if now-control_start<4000 then
                if cfg.mode=="distance" then
                    assert(not group.online,"Distant normal-mode group came online")
                    for _,id in ipairs(ids.members) do assert(not level.object_by_id(id),"Distant member has client") end
                else
                    assert(group.online,"Whole-map group switched offline")
                    for _,id in ipairs(ids.members) do
                        assert(assert(alife():object(id)).online and level.object_by_id(id),"Whole-map member lost client")
                    end
                end
                return
            end
            if seen_online==nil then seen_online=false; seen_offline=false;alife():set_switch_distance(10000) end
            if group.online then seen_online=true else seen_offline=true end
            if now-control_start<10000 then return end
            assert(seen_online,"Near control never activated")
            if cfg.mode=="distance" then assert(seen_offline,"Expected inherited normal-mode group switching")
            else assert(not seen_offline,"Whole-map group churned") end
            log1(string.format("[legacy policy] complete stage=control mode=%s near_online=%s near_offline=%s",cfg.mode,tostring(seen_online),tostring(seen_offline)))
            done=true;get_console():execute("quit");return
        end
        if cfg.stage=="ownership" then
            if phase==0 then
                local excluded=assert(alife():object(ids.members[2]))
                assert(not excluded.online and not level.object_by_id(excluded.id),"Excluded member unexpectedly online")
                alife():release(excluded,true);phase=1;deadline=now+30000;return
            end
            assert(now<deadline,"Legacy ownership phase timed out")
            assert(not alife():object(ids.members[2]),"Offline release left member registered")
            local group=alife():object(ids.group)
            if phase==1 then
                assert(group and #fixture.members(group)==3,"Offline release left stale membership")
            elseif group then return end
            for _,i in ipairs({1,3,4}) do
                local member=assert(alife():object(ids.members[i]),"Owner release lost a survivor")
                if not member.online or not level.object_by_id(member.id) then stable=nil;return end
            end
            stable=stable or now
            if now-stable<2000 then return end
            if phase==1 then
                assert(group.online,"Expected online owner before release")
                alife():release(group,true);phase=2;stable=nil;return
            end
            log1("[legacy policy] complete stage=ownership offline_member_released=true survivors=3")
            done=true;get_console():execute("quit");return
        end
        if cfg.stage=="roundtrip" then
            assert(level.name()==maps[trip],"Wrong roundtrip map")
            local group=assert(alife():object(ids.group),"Group lost across level change")
            assert(#fixture.members(group)==4,"Membership lost across level change")
            local on=maps[trip]=="l05_bar"
            assert(group.online==on,"Group active on wrong map")
            for i,id in ipairs(ids.members) do
                local member=assert(alife():object(id),"Member lost across level change")
                local expected=on and i~=2
                assert(member.online==expected and (level.object_by_id(id)~=nil)==expected,"Member activation after level change")
            end
            log1(string.format("[legacy trip] phase=%d map=%s group=%d",trip,level.name(),ids.group))
            done=true
            if trip==#maps then log1("[legacy policy] complete stage=roundtrip");get_console():execute("quit")
            else
                local f=assert(io.open(path("legacy-roundtrip-phase.txt"),"w"));f:write(tostring(trip+1));f:close()
                get_console():execute("jump_to_level "..maps[trip+1])
            end
            return
        end
        if cfg.stage=="verify" then
            if phase==1 then
                assert(now<deadline,"Empty legacy group was not removed")
                if alife():object(ids.group) then return end
                local corpse=assert(alife():object(ids.members[2]),"Final corpse disappeared with its owner")
                assert(not corpse.is_alive,"Final corpse resurrected")
                log1("[legacy policy] complete stage=verify empty_owner_removed=true")
                done=true;get_console():execute("quit");return
            end
            local group=assert(alife():object(ids.group),"Group lost on reload")
            local members=fixture.members(group)
            assert(#members==1 and members[1]==ids.members[2],"Saved membership did not survive reload")
            local live=assert(alife():object(ids.members[2])); local client=level.object_by_id(live.id)
            assert(group.online and live.online and client and client:alive(),"Survivor not active after reload")
            assert(not alife():object(ids.members[4]),"Released member resurrected")
            for _,i in ipairs({1,3}) do assert(not assert(alife():object(ids.members[i])).is_alive,"Corpse resurrected") end
            log1("[legacy policy] reload_verified survivor="..live.id)
            client:kill(db.actor);phase=1;deadline=now+30000;return
        end
        if phase==0 then advance();return end
        assert(now<deadline,"Legacy policy phase timed out: "..phase)
        local group=assert(alife():object(ids.group),"Group disappeared")
        local expected_online=phase~=6
        local matches=group.online==expected_online
        local members=fixture.members(group)
        local expected_count=phase<10 and 4 or (phase==10 and 2 or 1)
        matches=matches and #members==expected_count
        for i,id in ipairs(ids.members) do
            local member=alife():object(id);local client=level.object_by_id(id)
            if phase==11 and i==4 then matches=matches and member==nil and client==nil
            elseif phase>=10 and (i==1 or i==3) then
                matches=matches and member~=nil and not member.is_alive and client~=nil and not client:alive()
            else
                local expected=expected_online and not (i==2 and (phase==2 or phase==3))
                matches=matches and member~=nil and member.online==expected and (client~=nil)==expected
                if client then assert(client:alive(),"Living fixture member unexpectedly died") end
            end
        end
        if matches then stable=stable or now else stable=nil end
        if not stable or now-stable<2000 then return end
        log1(string.format("[legacy policy] phase=%d group=%d members=%s online=%s",phase,ids.group,table.concat(members,","),tostring(group.online)))
        advance()
    end
    level.add_call(function()
        local ok,err=xpcall(tick,debug.traceback)
        if not ok then done=true;log1("[legacy policy] FAILED "..err);get_console():execute("quit") end
        return false
    end,function() end)
end
