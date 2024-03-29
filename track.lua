local Annotations = require "annotations"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local ut = require 'utils'
local uuid = require 'dependencies/uuid'
local json = require 'dependencies/json'

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
local function normalize_rotation(radian)
    if not radian then return nil end
    local x = math.cos(radian)
    local y = math.sin(radian)
    if false then
        x = -math.cos(radian-math.pi/2)
        y = math.sin(radian-math.pi/2)
    end
    return math.atan2(y,x)
end
function Track:add_annotation(time,x_postition,y_position,rotation_radian,frame_id)
    assert(time)
    assert(x_postition)
    assert(y_position)
    Track.add(self,time,{x=x_postition,y=y_position,rad=rotation_radian,frame_id=frame_id})
end
function Track:remove_annotation(time)
    assert(time)
    Track.remove(self,time)
end
function Track:interpolate_angles(a,b,qt)
    if not a then return b end
    if not b then return a end
    local max = math.pi*2
    local da = (b-a) % max
    local va = 2 * da % max - da
    return a + va * qt
end
function Track:interpolate(p,n,dt_before,dt_after)
    assert(p.frame_id == n.frame_id)
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
    return { x=(px+vx*dt_before), y=(py+vy*dt_before), rad=self:interpolate_angles(pa,na,dt_before/(dt_before+dt_after)), frame_id=p.frame_id }
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
function Track:serialize(do_not_encode)
    local annotations = {}
    for key, value in pairs(self.data) do
        table.insert(annotations, {time = key, x = value.x, y = value.y, rad = value.rad, frame_id = value.frame_id})
    end
    local data = {}
    if annotations[1] then -- only create annotation when it contains data
        data = {
            id = self.id, 
            person_id = self.person_id, 
            start_time = self.start_time, 
            end_time = self.end_time,
            annotations = annotations
        }
    end
    if do_not_encode then return data else return Track.pretty_encode_track(data) end
end
function Track:serialize_tracks(tracks, do_not_encode)
    local data = {}
    for key, value in pairs(tracks) do
        table.insert(data,value:serialize(true))
    end
    if do_not_encode then return data else return Track.pretty_encode_tracks(data) end
end
local function json_element(name, value)
    local result = '"'..name..'": '
    if type(value) == 'string' then
        result = result .. '"' .. value .. '"'
    else
        result = result .. value
    end
    return result
end
local function if_exists(name, data, prefix, suffix)
    if data[name] then
        return prefix .. json_element(name, data[name]) .. suffix
    else
        return ""
    end
end
function Track.pretty_encode_annotation(annotation)
    local result = '{ ' .. 
        if_exists('time', annotation, '', ', ') .. 
        if_exists('x', annotation, '', ', ') .. 
        if_exists('y', annotation, '', ', ') .. 
        if_exists('rad', annotation, '', ', ') .. 
        if_exists('frame_id', annotation, '', ', ')
    return string.gsub(result, ', $', ' }')
end
function Track.pretty_encode_annotations(annotations, indent)
    local result = '['
    local timed_annotations = {}
    for k,v in pairs(annotations) do
        timed_annotations[v.time] = v
    end
    for k,v in ut.pairs_by_keys(timed_annotations) do
        result = result .. '\n' .. indent .. Track.pretty_encode_annotation(v) .. ','
    end
    result = string.gsub(result, ',$', '\n') .. indent .. ']'
    return result
end
function Track.pretty_encode_track(track, indent)
    local indent = indent or '    '
    local result = '{\n' .. 
        if_exists('id', track, indent, ',\n') ..
        if_exists('person_id', track, indent, ',\n') ..
        if_exists('start_time', track, indent, ',\n') ..
        if_exists('end_time', track, indent, ',\n') ..
        indent .. '"annotations": ' .. Track.pretty_encode_annotations(track.annotations, indent..'    ') .. 
        '\n'..indent..'}'
    return result
end
function Track.pretty_encode_tracks(tracks, indent)
    local indent = indent or '    '
    local result = '['
    for k,v in pairs(tracks) do
        result = result .. '\n' .. indent .. Track.pretty_encode_track(v,indent..'    ') .. ','
    end
    result = string.gsub(result, ',$', '\n') .. indent .. ']'
    return result
   
end
function Track:deserialize_tracks(data)
    result = {}
    if not data then return result end
    parsed = utils.parse_json(data)
    if not parsed then msg.error("could not parse as json: ", data); return result; end
    for key, parsed_track in pairs(parsed) do
        if not parsed_track.annotations then 
            msg.warn("skipping parsed track. does not contatin anntation: ", dump_pp(parsed_track))
        elseif not parsed_track.id then
            msg.warn("skipping parsed track. does not contatin id: ", dump_pp(parsed_track))
        else
            local track = Track:new()
            track.id = parsed_track.id
            track.person_id = parsed_track.person_id
            track.start_time = parsed_track.start_time
            track.end_time = parsed_track.end_time
            for key, parsed_annotation in pairs(parsed_track.annotations) do
                track:add_annotation(parsed_annotation.time, parsed_annotation.x, parsed_annotation.y, normalize_rotation(parsed_annotation.rad), parsed_annotation.frame_id)
            end
            result[track.id] = track
        end
    end
    return result
end


return Track