-- This module provides the annotations class
local Annotations = {}
function Annotations:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.data = {}
    return o
end
function Annotations:add(time,value)
    if not self.data[time] then
        self.data[time] = value
    else
        for k,v in pairs(value) do
            self.data[time][k] = v
        end
    end
end
function Annotations:get_entry(time)
    return self.data[time]
end
function Annotations:find_neighbours(time)
    assert(time)
    local less_dist = nil
    local lessval = nil
    local more_dist = nil
    local moreval = nil
    for key, value in pairs(self.data) do
        if key < time then
            if (not less_dist) or (time-key < less_dist) then
                less_dist = time-key
                lessval = value
            end
        else
            if (not more_dist) or (key-time < more_dist) then
                more_dist = key-time
                moreval = value
            end
        end
    end
    return lessval, moreval, less_dist, more_dist
end
return Annotations