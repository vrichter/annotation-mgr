local Annotations = require "annotations"
local dump = require "dump"

local Person = {_max_id=1}
function Person:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o['id'] = Person._max_id
    o.annotations = Annotations:new()
    Person._max_id  = Person._max_id+1
    return o
end
function Person:add_annotation(time,x_postition,y_position,rotation_radian)
    assert(time)
    assert(x_postition)
    assert(y_position)
    rotation_radian = rotation_radian or 0
    self.annotations:add(time,{x=x_postition,y=y_position,rad=rotation_radian})
end
function Person:remove_annotation(time)
    assert(time)
    self.annotations:remove(time)
end
function Person:interpolate(p,n,dt_before,dt_after)
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
    local va = (na-pa)/(dt_before+dt_after)
    return { x=(px+vx*dt_before), y=(py+vy*dt_before), rad=(pa+va*dt_before) }
end
function Person:position(time)
    assert(time)
    local time = time or _property_time
    local entry = self.annotations:get_entry(time)
    if not (entry == nil) then
        return entry, false
    end
    -- need to interpolate
    local previous, next, dt_before, dt_after = self.annotations:find_neighbours(time)
    if (not previous) or (previous.lost == true) then
        return next, true
    end
    if (not next) or (next.lost == true) then
        return previous, true
    end
    return self:interpolate(previous,next,dt_before,dt_after), true
end

return Person