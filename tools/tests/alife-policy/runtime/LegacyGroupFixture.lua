-- Build only the saved fixture here. A fresh process restores the engine's
-- registries from these serialized ownership flags before any policy test.
local M = {}
function M.packet(object)
    local p=net_packet(); p:w_begin(0); object:STATE_Write(p); p:r_seek(0); return p
end
function M.members(group)
    local p=M.packet(group)
    -- Legacy group STATE_Write ends with create-position:u32, count:u16,
    -- member-vector-size:u32 and the u16 IDs. Use a known fixture count bound.
    for count=0,8 do
        local tail=p:w_tell()-10-2*count
        if tail>=2 then
            p:r_seek(tail)
            local create, population, size=p:r_u32(),p:r_u16(),p:r_u32()
            if create<=1 and population==count and size==count then
                local ids={}; for i=1,count do ids[i]=p:r_u16() end
                return ids
            end
        end
    end
    error("Legacy membership tail is invalid")
end
local function indirect(object)
    local old=M.packet(object); local p=net_packet(); p:w_begin(0); old:r_seek(2)
    -- CSE_ALifeObject::STATE_Write: graph:u16, distance:f32, direct:u32.
    for offset=2,old:w_tell()-1 do
        local byte=old:r_u8()
        if offset>=8 and offset<12 then byte=0 end
        p:w_u8(byte)
    end
    p:r_seek(2); object:STATE_Read(p,p:w_tell()-2)
end
function M.create(node,graph)
    local position=level.vertex_position(node)
    local raw=assert(alife():create("validation_flesh_group",position,node,graph))
    local group=assert(alife():object(raw.id))
    alife():set_switch_online(group.id,false)
    local initial=M.packet(group); initial:r_seek(initial:w_tell()-4)
    assert(initial:r_u32()==0,"Fixture group must start empty")
    local ids={}
    for i=1,4 do
        local member=assert(alife():create("validation_flesh",position,node,graph))
        assert(not member.online,"Fixture mutation requires offline members")
        indirect(member); ids[i]=member.id
    end
    local old=M.packet(group); local p=net_packet(); p:w_begin(0); old:r_seek(2)
    for offset=2,old:w_tell()-11 do p:w_u8(old:r_u8()) end
    p:w_u32(0); p:w_u16(#ids); p:w_u32(#ids)
    for _,id in ipairs(ids) do p:w_u16(id) end
    p:r_seek(2); group:STATE_Read(p,p:w_tell()-2)
    local actual=M.members(group)
    assert(#actual==#ids)
    for i,id in ipairs(ids) do assert(actual[i]==id) end
    return {group=group.id,members=ids}
end
return M
