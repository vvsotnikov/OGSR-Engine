
-- Private regular-build validation only; original installation is untouched.
local original_start_game_callback = start_game_callback
function start_game_callback()
    original_start_game_callback()
    local root = getFS():update_path("$app_data_root$", "")
    local config_file = io.open(root .. "regular-config.lua", "r")
    if config_file then
        config_file:close()
        dofile(root .. "RegularDriver.lua")(dofile(root .. "regular-config.lua"))
    end
end
