local dump = require "dump"
local msg = require 'msg'

local Tf = {}
function Tf:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
    -- { x, y, rad, frame_id }
function Tf:transform_to(track, frame_id)
    if (not (track.frame_id)) or (not (frame_id)) or (track.frame_id == frame_id)  then return track end
    if not (track.frame_id == 'Home') then
        track = self:transform_to_home(track)
    end
    if frame_id == 'map.mp4' then
        return {x = track.y*100+114, y = track.x*100+44, rad=track.rad, frame_id='map.mpv'}
    end
    assert(false)
end

return Tf