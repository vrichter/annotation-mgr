local Track = require "track"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local json = require 'dependencies/json'

local tau = 2 * math.pi

local Person = {}
function Person:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.tracks = {}
    o.person_id = nil
    o.tf = {}
    return o
end
function Person:add_track(track)
    table:insert(self.tracks,track)
end
function Person:add_tracks(tracks)
    for k,track in pairs(tracks) do
        table.insert(self.tracks,track)
    end
end
function Person:set_id(id)
    self.person_id = id
end
function Person:set_tf(tf)
    self.tf = tf
end
function Person:create_from_tracks(annotations, tf)
    local person_tracks = {}
    for i,tracks in pairs(annotations) do
        for k,v in pairs(tracks) do
            if v.person_id then
                if not person_tracks[v.person_id] then
                    person_tracks[v.person_id] = {v}
                else
                    table.insert(person_tracks[v.person_id],v)
                end
            end
        end
    end
    local persons = {}
    for id, tracks in pairs(person_tracks) do
        local person = Person:new()
        person:set_id(id)
        person:set_tf(tf)
        person:add_tracks(tracks)
        persons[id] = person
    end
    return persons
end
local function normalize_rotation(rad, min, max)
    -- rotate full circles until angle is between min and max
    local rotation = rad
    while rotation < -min do 
        rotation = rotation + tau
    end
    while rotation > max do 
        rotation = rotation - tau
    end
    return rotation
end
local function normalize_rotation_positive(rad)
    return normalize_rotation(rad,0,2*tau)
end
local function normalize_rotation_pi(rad)
    return normalize_rotation(rad,-math.pi,math.pi)
end
local function normalize_to_short_angle(x,ref)
    return normalize_rotation(x,ref-math.pi, ref+math.pi)
end
local function calculate_mean_rotation(x)
    if #x == 0 then return nil end
    local sum = 0.
    local ref = nil
    for i = 1, #x do
        if not ref then ref = x[i] end
        sum = sum + normalize_to_short_angle(x[i],ref)
    end
    return sum/#x
end
local function calculate_mean(x)
    if #x == 0 then return nil end
    local sum = 0.
    for i = 1, #x do
        sum = sum + x[i]
    end
    return sum/#x
end
local function calculate_mean_position(positions)
    local x = {}
    local y = {}
    local rad = {}
    local frame_id = nil
    for k, position in pairs(positions) do
        if frame_id then
            assert(frame_id == position.frame_id)
        else
            frame_id = position.frame_id
        end
        if position.x then
            table.insert(x,position.x)
        end
        if position.y then
            table.insert(y,position.y)
        end
        if position.rad then
            table.insert(rad,position.rad)
        end
    end
    if #x > 0 then
        return {x = calculate_mean(x), y = calculate_mean(y) , rad = calculate_mean_rotation(rad), frame_id = frame_id}
    else
        return nil
    end
end
function Person.calculate_mean_position(positions)
    return calculate_mean_position(positions)
end
function Person:position(time, target_frame_id)
    assert(time)
    local positions = {}
    for k,track in pairs(self.tracks) do
        local position = track:position(time)
        if position.position then
            local home_position = self.tf:transform_to_home(position.position)
            --local home_position = self.tf:transform_to(position.position, 'Home')
            table.insert(positions,home_position)
        end
    end
    local result = {interpolated = true, endpoint = false, position = calculate_mean_position(positions)}
    if result.position and target_frame_id then
        result.position = self.tf:transform_to(result.position, target_frame_id)
    end
    return result
end

return Person