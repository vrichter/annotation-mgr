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
    return o
end
function Annotations:add(time,value,nextvalue)
    msg.info('time',time,'value',dump(value))
    assert(time)
    assert(value)
    if not self.data[time] then
        self.data[time] = value
    else
        for k,v in pairs(value) do
            self.data[time][k] = v
        end
    end
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
function Annotations:remove(time)
    assert(time)
    msg.info('before',dump(self.data))
    --table.remove(self.data,time)
    self.data[time]=nil
    msg.info('after',dump(self.data))
    -- update min/max
    if (time == self.min) or (time == self.max) then
        self.update_min_max()
    end
end
function Annotations:get_entry(time)
    return self.data[time]
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