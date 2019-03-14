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
local function homogenize(vector)
    local factor = vector[3][1]
    if factor == 0. or factor == 1. then
        return vector
    else 
        return vector / factor
    end
end
local function transform_2d_pose(pose, tf)
    assert(tf)
    assert(pose.x)
    assert(pose.y)
    if not pose.rad then 
        local point = homogenize(tf * matrix {{pose.x}, {pose.y}, {1}})
        return {x = point[1][1], y = point[2][1]}
    else
        local point = homogenize(tf * matrix {{pose.x}, {pose.y}, {1}}) -- this is a point
        local direction = homogenize(tf * matrix {{ math.cos(pose.rad) }, { math.sin(pose.rad) }, { 0 }}) -- this is a vector
        local norm = matrix.normf(direction)
        local rotation = math.atan2(direction[2][1]/norm, direction[1][1]/norm);
        return {x = point[1][1], y = point[2][1], rad = rotation}
    end
end
function Tf:transform_to_home(track)
    assert(self.transformations[track.frame_id])
    local home_tf = matrix.invert(self.transformations[track.frame_id])
    assert(home_tf)
    return transform_2d_pose(track, home_tf)
end
function Tf:transform_to(track, frame_id)
    if (not (track.frame_id)) or (not (frame_id)) or (track.frame_id == frame_id)  then return track end
    if not (track.frame_id == 'Home') then
        msg.info('transforming track',dump(track),'from"'..frame_id..'" to "Home"')
        track = self:transform_to_home(track)
        msg.info('result:',dump(track))
    end
    if self.transformations[frame_id] then
        msg.info('transforming track',dump(track),'from "Home" to "'..frame_id..'"')
        local result = transform_2d_pose(track,self.transformations[frame_id])
        msg.info('result:',dump(result))
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
function Tf:calculate4PointTFforBigMap(x1, y1, x2, y2, x3, y3, x4, y4)
    local T_vga_bm = matrix {
          { 1.826, 0, x1},
          { 0, 1.826, y1},
          { 0,     0,   1}
        }
    local T_sm_bm = matrix {
          { 3.4687, 0, 0},
          { 0, 3.4687, 0},
          { 0,      0, 1}
        }
    local T_h_sm = matrix {
          {0, 100, 114},
          {100, 0, 44}, 
          {0, 0, 1}     
        }
    return matrix.invert(matrix.invert(T_h_sm) * matrix.invert(T_sm_bm) * T_vga_bm)
end

return Tf