local Track = require "track"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local json = require 'dependencies/json'

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
local function calculate_mean_position(positions)
    local x = 0.
    local y = 0.
    local rad = 0.
    local count = 0.
    local frame_id = nil
    msg.error("calculate mean rotation:")
    for k, position in pairs(positions) do
        if frame_id then
            assert(frame_id == position.frame_id)
        else
            frame_id = position.frame_id
        end
        x = x + position.x
        y = y + position.y
        rad = rad + position.rad
        msg.error(" --",position.rad)
        count = count +1
    end
    msg.error("--",rad/count)
    return {x = x/count, y = y/count, rad = rad/count, frame_id = frame_id}
end
function Person:position(time)
    assert(time)
    local positions = {}
    for k,track in pairs(self.tracks) do
        local position = track:position(time)
        if position.position then
            local home_position = self.tf:transform_to_home(position.position)
            --local home_position = self.tf:transform_to(position.position, 'Home')
            msg.error('rotation from',position.position.frame_id,'to Home:',position.position.rad*(180/math.pi),' -> ',home_position.rad*(180/math.pi))
            table.insert(positions,home_position)
        end
    end
    local result = { position = calculate_mean_position(positions), interpolated = true, endpoint = false }
    msg.error(dump_pp(result))
    return result
end

return Person