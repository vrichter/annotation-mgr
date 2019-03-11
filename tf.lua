local dump = require 'dump'
local msg = require 'msg'
local matrix = require 'dependencies/matrix'
local json = require 'dependencies/json'

local Tf = {}
function Tf:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.transformations = {}
    return o
end
local function transform_2d_rotation(rad, tf)
    local point = tf * matrix {{ math.cos(rad), math.sin(rad), 1}}
    local norm = math.sqrt((point[1]^2)+(point[2]^2))
    local angle = - (math.atan2(yd,xd) - math.atan2(yz,xz))
    return Math.atan2(point[2]/norm, point[1]/norm);
end
local function transform_2d_pose(pose, tf)
    local point = tf * matrix {{pose.x}, {pose.y}, {1}}
    local result = {x = point[1][1], y = point[2][1]}
    if pose.rad then 
        result.rad = transform_2d_rotation(pose.rad, tf)
    end
    return result
end
    -- { x, y, rad, frame_id }
function Tf:transform_to(track, frame_id)
    if (not (track.frame_id)) or (not (frame_id)) or (track.frame_id == frame_id)  then return track end
    if not (track.frame_id == 'Home') then
        track = self:transform_to_home(track)
    end
    if self.transformations[frame_id] then
        local result = transform_2d_pose(track,self.transformations[frame_id])
        result.frame_id = frame_id
        return result
    end
    assert(false)
end
function Tf:add_transformation(name, tf)
    self.transformations[name] = tf
end
function Tf:remove_transformation(name)
    self.transformations[name] = nil
end
function Tf:serialize()
    local data = {}
    for key, value in pairs(self.transformations) do
        table.insert(data,{ frame_id = key, transformation = value })
    end
    return json.encode(data)
end
function Tf:deserialize(string)
    local result = Tf:new()
    local data = json.decode(string)
    if data then
        for key, value in pairs(data) do
            assert(value.frame_id)
            assert(value.transformation)
            local tf = value.transformation
            assert(#tf == 3)
            assert(#tf[1] == 3)
            assert(#tf[2] == 3)
            assert(#tf[3] == 3)
            result:add_transformation(value.frame_id, 
                                  matrix {
                                      {tf[1][1], tf[1][2], tf[1][3]},
                                      {tf[2][1], tf[2][2], tf[2][3]},
                                      {tf[3][1], tf[3][2], tf[3][3]}
                                    })
        end
    end
    return result
end

return Tf