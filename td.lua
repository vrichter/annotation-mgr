local dump = require 'dump'
local msg = require 'msg'
local track = require 'track'
local json = require 'dependencies/json'

local Td = {}
function Td:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.time_deltas = {}
    return o
end
function Td:add_time_delta(name, td)
    self.time_deltas[name] = td
end
function Td:remove_time_delta(name)
    self.time_deltas[name] = nil
end
local add_if_exists = function(data, name, time)
    if data and data[name] then
        data[name] = data[name] + time
    end
end
function Td:adapt_track_times(tracks, from_frame, to_frame)
    if (not self.time_deltas[from_frame]) or (not self.time_deltas[to_frame]) then
        msg.warn('Missing time delta. Can not adapt time stamps from "' .. from_frame .. '" to "' .. to_frame .. '.')
        return tracks
    end
    local delta = self.time_deltas[to_frame] - self.time_deltas[from_frame]
    for i, track in pairs(tracks) do
        add_if_exists(track, 'start_time', delta)
        add_if_exists(track, 'end_time', delta)
        if track.data then
            local data = {}
            for time, annotation in pairs(track.data) do
                data[time+delta] = annotation
            end
            track.data = data
        end
    end
    return tracks
end
function Td:serialize()
    local data = {}
    for key, value in pairs(self.time_deltas) do
        table.insert(data,{ frame_id = key, time_delta = value })
    end
    return json.encode(data)
end
function Td:deserialize(string)
    local result = Td:new()
    local data = json.decode(string)
    if data then
        for key, value in pairs(data) do
            assert(value.frame_id)
            assert(value.time_delta)
            result:add_time_delta(value.frame_id, value.time_delta)
        end
    end
    return result
end

return Td