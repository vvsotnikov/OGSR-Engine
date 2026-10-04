local function dofile(path) return assert(loadfile(path))() end
tostring = function(value) assert(type(value) == "boolean"); return value and "true" or "false" end
local root = assert(...)
dofile(root .. "/Test-SpawnQueue.lua")(dofile(root .. "/SpawnQueue.lua"))
local clock, object, selected = 0, nil, nil
local function position(distance)
    return {distance_to=function() return distance end}
end
local actor = {position=function() return position(0) end, game_vertex_id=function() return 0 end}
db = {actor=actor}
system_ini = function() return {r_float=function() return .1 end} end
local vertices = {position(103), position(250), position(150)}
level = {
    vertex_count=function() return #vertices end,
    vertex_position=function(id) return vertices[id+1] end,
    is_accessible_vertex_id=function() return true end,
    object_by_id=function() return object and object.online and object or nil end,
}
local graph = {valid_vertex_id=function() return true end, vertex=function() return {level_id=function() return 1 end} end}
game_graph = function() return graph end
cross_table = function() return {vertex=function(_,id) return {game_vertex_id=function() return id end} end} end
local world = {
    set_switch_distance=function() end, set_switch_online=function() end, set_switch_offline=function() end,
    create=function(_,section,pos,node) selected=node;object={id=1,position=pos,online=true};return object end,
    object=function() return object end,
}
alife = function() return world end
log1 = function() end
local probe = dofile(root .. "/PolicyProbe.lua")(function() return clock end,"whole-map")
assert(selected == 1, "Probe did not select farthest vertex")
assert(not probe())
object.position=position(24) -- Outside actual 22m gate, within the placement margin.
clock=16000;assert(probe(), "Placement margin was incorrectly used as the gate")
object.position=position(21);assert(not pcall(probe), "Crossing actual gate must invalidate the probe")


