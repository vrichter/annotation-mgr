local Annotations = require "annotations"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local uuid = require 'dependencies/uuid'

local Track = {}
for k, v in pairs(Annotations) do
    Track[k] = v
end
uuid.randomseed(os.time()+os.clock()*1000000)
function Track:new(o)
    o = o or Annotations:new(o)
    setmetatable(o, self)
    self.__index = self
    o.id = uuid.new()
    return o
end
function Track:add_annotation(time,x_postition,y_position,rotation_radian)
    assert(time)
    assert(x_postition)
    assert(y_position)
    rotation_radian = rotation_radian or 0
    Track.add(self,time,{x=x_postition,y=y_position,rad=rotation_radian})
end
function Track:remove_annotation(time)
    assert(time)
    Track.remove(self,time)
end
function Track:interpolate_angles(a,b,qt)
    local max = math.pi*2
    local da = (b-a) % max
    local va = 2 * da % max - da
    return a + va * qt
end
function Track:interpolate(p,n,dt_before,dt_after)
    assert(p)
    assert(n)
    assert(dt_before)
    assert(dt_after)
    local px = p.x
    local py = p.y
    local nx = n.x
    local ny = n.y
    local pa = p.rad
    local na = n.rad
    local vx = (nx-px)/(dt_before+dt_after)
    local vy = (ny-py)/(dt_before+dt_after)
    return { x=(px+vx*dt_before), y=(py+vy*dt_before), rad=self:interpolate_angles(pa,na,dt_before/(dt_before+dt_after)) }
end
function Track:position(time)
    assert(time)
    local time = time or _property_time
    local entry = Track.get_entry(self,time)
    if not (entry == nil) then
        return { position = entry, interpolated = false, endpoint = ((time == Track.get_start_time(self)) or (time == Track.get_end_time(self))) }
    end
    -- need to interpolate
    local neighbours = Track.find_neighbours(self,time)
    local previous = neighbours.previous.annotation
    local next = neighbours.next.annotation
    local dt_before = neighbours.previous.time_delta
    local dt_after = neighbours.next.time_delta
    result = {
        position = nil,
        interpolated = nil,
        endpoint = nil
    }
    if (not previous) and (not next) then
        -- fall through. position should be empty
    elseif (previous) and (next) then
        result = {
            position = self:interpolate(previous,next,dt_before,dt_after),
            interpolated = true,
            endpoint = false
        }
    elseif (not previous) and not (Track.is_start_time(self,neighbours.next.time)) then
        result = {
            position = next,
            interpolated = true,
            endpoint = false
        }
    elseif (not next) and not (Track.is_end_time(self,neighbours.previous.time)) then
        result = {
            position = previous,
            interpolated = true,
            endpoint = false
        }
    end
    return result
end
function Track:serialize_if_exists(name)
    if self[name] then
        return '"' .. name .. '": ' .. self[name] .. ', '
    end
    return ''
end
function Track:serialize()
    result = '{ "id": ' .. self.id .. ', ' .. 
    self:serialize_if_exists("person_id") .. 
    self:serialize_if_exists("start_time") .. 
    self:serialize_if_exists("end_time")
    result = result .. '"annotations": [ '
    for key, value in pairs(self.data) do
        result = result .. '{ "time": ' .. key .. ', "x": ' .. value.x .. ', "y": ' .. value.y .. ', "rad": ' .. value.rad .. ' }, '
    end
    result = result:gsub(", $", " ")
    result = result .. '] }'
    return result
end
function Track:serialize_tracks(data)
    result = '['
    for key, value in pairs(data) do
        result = result .. Track.serialize(value) .. ', '
    end
    result = result:gsub(", $", " ")
    result = result .. ']'
    return result
end
function copy_if(name, from, to)
    local val = from[name]
    if val then to[name] = val end
end
function Track:deserialize_tracks(data)
    result = {}
    if not data then return result end
    parsed = utils.parse_json(data)
    for key, parsed_track in pairs(parsed) do
        assert(parsed_track.annotations)
        assert(parsed_track.id)
        local track = Track:new()
        track.id = parsed_track.id
        copy_if('person_id', parsed_track, track)
        copy_if('start_time', parsed_track, track)
        copy_if('end_time', parsed_track, track)
        for key, parsed_annotation in pairs(parsed_track.annotations) do
            track:add_annotation(parsed_annotation.time, parsed_annotation.x, parsed_annotation.y, parsed_annotation.rad)
        end
        result[track.id] = track
    end
    return result
end


return Track