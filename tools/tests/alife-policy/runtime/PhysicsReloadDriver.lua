-- The saved world must contain broken physics objects. Use the same seed for
-- the failing control and fixed build; an intact new game is not a substitute.
return function()
    local state_path=getFS():update_path("$app_data_root$","physics-reload-state.lua")
    local f=io.open(state_path,"r")
    local stage=0
    if f then f:close();stage=dofile(state_path) end
    local started,sent=nil,false
    local function next_stage(value)
        local out=assert(io.open(state_path,"w"));out:write("return "..value);out:close()
        sent=true
    end
    local function tick()
        if sent or not db.actor or not app_ready() or device().precache_frame~=0 then return end
        local now=time_global()
        if not started then started=now;get_console():execute("g_god on");level.disable_input() end
        if stage==0 then
            assert(level.name()=="l05_bar","Expected the Bar regression seed")
            next_stage(1);get_console():execute("jump_to_level l01_escape")
        else
            assert(level.name()=="l01_escape")
            if now-started<10000 then return end
            if stage==1 then
                log1("[physics reload] saved_world_loaded")
                next_stage(2)
                get_console():execute("save physics_reload")
                get_console():execute("load physics_reload")
            else
                log1("[physics reload] complete")
                sent=true;get_console():execute("quit")
            end
        end
    end
    level.add_call(function()
        local ok,err=xpcall(tick,debug.traceback)
        if not ok then log1("[physics reload] FAILED "..tostring(err));sent=true;get_console():execute("quit") end
        return false
    end,function() end)
end
