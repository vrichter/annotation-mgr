local dump = require 'dump'
local msg = require 'msg'
local matrix = require 'dependencies/matrix'

local Tf = {}
function Tf:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
local transformations = { Home = {} }
transformations['Home']['Home'] = matrix
    {
        {1, 0, 0},
        {0, 1, 0},
        {0, 0, 1}
    }
transformations['Home']['map.mp4'] = matrix
    { -- then translate by the image margin 114x44
        {1,0,114},
        {0,1,44},
        {0,0,1}
    } * matrix
    { -- scale: the map shows 1cm per pixel the coords are in meter
        {100,   0,   0},
        {  0, 100,   0},
        {  0,   0,   1}
    } * matrix
    { -- first switch x and y
        {0, 1, 0},
        {1, 0, 0},
        {0, 0, 1}
    }
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
    if transformations['Home'][frame_id] then
        local result = transform_2d_pose(track,transformations['Home'][frame_id])
        result.frame_id = frame_id
        return result
    end
    assert(false)
end

return Tf