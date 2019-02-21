local Annotations = require "annotations"
local dump = require "dump"

local Track = {}
for k, v in pairs(Annotations) do
    Track[k] = v
end
Track._max_id = 1
function Track:new(o)
    o = o or Annotations:new(o)
    setmetatable(o, self)
    self.__index = self
    o['id'] = Track._max_id
    Track._max_id  = Track._max_id+1
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
    local va = (na-pa)/(dt_before+dt_after)
    return { x=(px+vx*dt_before), y=(py+vy*dt_before), rad=(pa+va*dt_before) }
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
            interpolated = false,
            endpoint = false
        }
    elseif (not next) and not (Track.is_end_time(self,neighbours.previous.time)) then
        result = {
            position = previous,
            interpolated = false,
            endpoint = false
        }
    end
    return result
end

return Track