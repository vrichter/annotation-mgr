-- config
local opts = {
    position_size = 50,
    track_pos_color_annotation = '#5b268f66',
    track_pos_color_person = '#ffffff',
    track_pos_color_interpolated = '#26268f66',
    track_pos_color_endpoint = '#8f8f2666',
    track_pos_color_selected = '#8f262666',
    track_pos_color_border = '#000000',
    track_pos_color_border_alt = '#ffffff',
}
(require 'mp.options').read_options(opts,"render-tracks")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'msg'
local Track = require 'track'
local dump = require 'dump'

local RenderTrackAnnotation = {}
function RenderTrackAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function RenderTrackAnnotation:track_to_rotation_deg(rad)
    if rad then
        return -1*rad*180/math.pi 
    else 
        return nil 
    end
end

function RenderTrackAnnotation:render_track_position(ass, px, py, rad, size, color, person_id, gui)
    ass:new_event()
    ass:append('{\\org('..px..','..py..')}')
    if rad then
        ass:append('{\\frz'..self:track_to_rotation_deg(rad)..'}')
        ass:append(gui:asstools_create_color_from_hex(color))
        ass:pos(0,0)
        ass:draw_start()
        --ass:move_to(px-size/2,py)
        --ass:line_to(px,py-2*size) 
        --ass:line_to(px+size/2,py)
        ass:move_to(px,py-size/2)
        ass:line_to(px+2*size,py) 
        ass:line_to(px,py+size/2)
        ass:draw_stop()
    else
        ass:append(gui:asstools_create_color_from_hex(color))
        ass:pos(0,0)
        ass:draw_start()
        ass:move_to(px-size/2,py-size/2)
        ass:line_to(px-size/2,py+size/2) 
        ass:line_to(px+size/2,py+size/2) 
        ass:line_to(px+size/2,py-size/2) 
        ass:draw_stop()
    end
    -- draw name next to position
    if person_id then
        ass:new_event()
        ass:append('{\\pos('..px..','..py..')}')
        ass:append('{\\fs10}')
        ass:append(person_id)
    end
end

function RenderTrackAnnotation:transform_and_draw_track(ass, track, time, tf, tf_target, ref_size, type, gui, marked)
    local track_position = track:position(time)
    if (not track_position) or (not track_position.position) then return end
    local position = track_position.position
    local interpolated = track_position.interpolated
    local track_endpoint = track_position.endpoint
    local size = ref_size
    local color = {}
    color.border = opts.track_pos_color_border
    if marked and (track.id == marked.id) then
        color.primary = opts.track_pos_color_selected
    elseif interpolated then
        color.primary = opts.track_pos_color_interpolated
    elseif track_endpoint then
        color.primary = opts.track_pos_color_endpoint
    else
        color.primary = opts.track_pos_color_annotation
    end
    if type == "transformed_annotation" then
        size = size/2
        color.border = opts.track_pos_color_border_alt
    elseif type == "person" then
        color.primary = opts.track_pos_color_person
    end
    local transformed_position = tf:transform_to(position,tf_target)
    local px, py = gui:video_to_px(transformed_position.x, transformed_position.y)
    self:render_track_position(ass, px, py, transformed_position.rad, size, color, track.person_id, gui)
end

function RenderTrackAnnotation:draw_track_positions(track, time, ass, gui)
    local tracks = track.tracks
    local tf = track.main.data('tf')
    local frame = track.main.data('file')
    local marked = track.marked_track
    local size = gui:video_to_px_scale(opts.position_size)/2
    for k, t in pairs(tracks) do
        self:transform_and_draw_track(ass, t, time, tf, frame, size, "main_annotation", gui, marked)
    end
    for name, render in pairs(track.show_transformable) do
        if render and (track.transformable[name]) then
            for k, t in pairs(track.transformable[name]) do
               self:transform_and_draw_track(ass, t, time, tf, frame, size, "transformed_annotation", gui)
            end
        end
    end
    if track.show_persons then
        for k, person in pairs(track.persons) do
            self:transform_and_draw_track(ass, person, time, tf, frame, size, "person", gui)
        end
    end
    ass:draw_stop()
end

function RenderTrackAnnotation:render(track, ass, gui)
    local time = track.main.data('time')
    if not time then return end
    self:draw_track_positions(track, time, ass, gui)
end

return RenderTrackAnnotation