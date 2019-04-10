-- This module provides the annotations class
local dump = require 'dump'
local msg = require 'msg'

local Annotations = {}
function Annotations:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.data = {}
    o.start_time = nil
    o.end_time = nil
    o.fuzzy_max = 10 -- ms
    return o
end
function Annotations:add(time,value)
    assert(time)
    assert(value)
    self.data[time] = value
end
function Annotations:get_start_time()
    return self.start_time
end
function Annotations:get_end_time()
    return self.end_time
end
function Annotations:set_start_time(time)
    assert(self.data[time])
    for key, value in pairs(self.data) do
        assert(time <= key)
    end
    self.start_time = time
end
function Annotations:set_end_time(time)
    assert(self.data[time])
    for key, value in pairs(self.data) do
        assert(time >= key)
    end
    self.end_time = time
end
function Annotations:reset_start_time()
    self.start_time = nil
end
function Annotations:reset_end_time()
    self.end_time = nil
end
function Annotations:is_start_time(time)
    return (not (self.start_time == nil)) and (self.start_time == time)
end
function Annotations:is_end_time(time)
    return (not (self.end_time == nil)) and (self.end_time == time)
end
function Annotations:fuzzy_time(time)
    if self.data[time] then
        return time
    else -- return neighbours time if not too far
        local n = self:find_neighbours(time)
        result = nil
        if n then
            if n.next and n.next.time_delta then
                result = n.next
            end
            if n.previous and n.previous.time_delta then
                if (not result) or (result.time_delta > n.previous.time_delta) then
                    result = n.previous
                end
            end
        end
        if result then
            if result.time_delta < self.fuzzy_max then
                return result.time
            end
        end
    end
end
function Annotations:remove(time)
    assert(time)
    local time = self:fuzzy_time(time)
    if not time then return end
    self.data[time]=nil
end
function Annotations:get_entry(time)
    return self.data[time]
end
function Annotations:is_empty()
    for k,v in pairs(self.data) do
        return false
    end
    return true
end
function Annotations:get_time_endpoints()
    local first = nil
    local last = nil
    for key, value in pairs(self.data) do
        if (not first) or (key < first) then
            first = key
        end
        if (not last) or (key > last) then
            last = key
        end
    end
    return first, last
end
function Annotations:find_neighbours(time)
    assert(time)
    local less_dist = nil
    local less_time = nil
    local lessval = nil
    local more_dist = nil
    local more_time = nil
    local moreval = nil
    for key, value in pairs(self.data) do
        if key < time then
            if (not less_dist) or (time-key < less_dist) then
                less_dist = time-key
                less_time = key
                lessval = value
            end
        else
            if (not more_dist) or (key-time < more_dist) then
                more_dist = key-time
                more_time = key
                moreval = value
            end
        end
    end
    return { previous =  { annotation = lessval, time_delta = less_dist, time = less_time},
             next =      { annotation = moreval, time_delta = more_dist, time = more_time}
    }
end
return Annotations