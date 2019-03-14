-- config
local opts = {
    position_size = 50,
    track_pos_color_annotation = '#5b268f66',
    track_pos_color_interpolated = '#26268f66',
    track_pos_color_endpoint = '#8f8f2666',
    track_pos_color_selected = '#8f262666',
    track_pos_color_border = '#000000',
    track_pos_color_border_alt = '#ffffff',
}
(require 'mp.options').read_options(opts,"annotation-gui")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'msg'
local Track = require 'track'
local dump = require 'dump'

local function bind(t, k)
    msg.info('bind:',t,k)
    return function(...) return t[k](t, ...) end
end

local Gui = {}
function Gui:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.opts = opts
    -- ui properties
    self.properties = {}
    -- data to be rendered
    self.data = nil
    -- gui state
    self.ready = false
    self.marked_track = nil
    self.modified = true
    -- callbacks provided
    self.observers = {}
    -- register callbacks
    mp.observe_property("dwidth", native, bind(o,'observe_video_w'))
    mp.observe_property("dheight", native, bind(o,'observe_video_h'))
    mp.observe_property("osd-width", native, bind(o,'observe_osd_w'))
    mp.observe_property("osd-height", native, bind(o,'observe_osd_h'))
    mp.observe_property("time-pos", string, bind(o,'observe_time'))
    mp.register_event("tick", bind(o,'on_tick'))
    return o
end

-- property watchers
function Gui:observe_property(name, data)
    if data == nil then
        data = mp.get_property_native(name)
    end
    return data
end
function Gui:property(name, value)
    if value then
        -- setter
        local modified = not (self.properties[name] == value)
        self.properties[name] = value
        if modified then
            self.modified = true
            self:call_observers(name,value)
        end
    else
        -- getter
        local data = self.properties[name]
        if not data then
            data = self:observe_property(name,nil)
            self.properties[name] = data
        end
        return data
    end
end

function Gui:observe_video_w(name, data)
    self:property('dwidth', self:observe_property(name,data))
    self:update_video_position()
end
function Gui:observe_video_h(name, data)
    self:property('dheight', self:observe_property(name,data))
    self:update_video_position()
end
function Gui:observe_osd_w(name, data)
    self:property('osd-width', self:observe_property(name,data))
    self:update_video_position()
end
function Gui:observe_osd_h(name, data)
    self:property('osd-height', self:observe_property(name,data))
    self:update_video_position()
end
function Gui:observe_time(name,data)
    self:property('time-pos', self:observe_property(name,data))
end

function Gui:update_video_position()
    local ww = self:property('osd-width')
    local wh = self:property('osd-height')
    local vw = self:property('dwidth')
    local vh = self:property('dheight')
    if ww == nil  or wh == nil or  vw == nil or vh == nil then
        return
    end
    local scale=ww/vw
    if wh/vh < scale then
        scale = wh/vh
    end
    self:property('video-x', (ww-(vw*scale))/2)
    self:property('video-y', (wh-(vh*scale))/2)
    self:property('video-scale', scale)
end

function Gui:update_data(data)
    self.data = data
    --msg.info('self',self,'set data:',dump(self.data))
    self.modified = true
end

-- transformations
function Gui:tr_px_to_video(x,y)
    -- first remove padding, then scale with video scale
    return (x-self:property('video-x'))/self:property('video-scale'), (y-self:property('video-y'))/self:property('video-scale')
end
function Gui:tr_video_to_px(x,y)
    -- scale with video scale, then add padding
    return x*self:property('video-scale')+self:property('video-x'), y*self:property('video-scale')+self:property('video-y')
end
function Gui:tr_video_to_px_scale(x)
    return x*self:property('video-scale')
end
function Gui:tr_track_to_px(track)
    return self:tr_video_to_px(track.x, track.y)
end
function Gui:tr_rotation_from_points_rad(x_center, y_center, x_dir, y_dir)
    local xd = x_center-x_dir
    local yd = y_center-y_dir
    local norm = math.sqrt((xd^2)+(yd^2))
    xd = xd/norm
    yd = yd/norm
    xz = 0
    yz = 1
    local angle = - (math.atan2(yd,xd) - math.atan2(yz,xz))
    return angle
end
function Gui:tr_track_to_rotation_rad(rad)
    return track.rad
end
function Gui:tr_track_to_rotation_deg(rad)
    if rad then
        return rad*180/math.pi 
    else 
        return nil 
    end
end
function Gui:calculate_dist(ax,ay,bx,by)
    return math.sqrt(math.abs((bx-ax)^2-(by-ay)^2))
end

-- render functions
function Gui:asstools_hex_rgb2bgr(hex)
    if not hex then return nil, nil end
    hex = hex:match("^#?([1-9a-fA-F]+)$")
    if not hex then return nil, nil end
    assert((string.len(hex) == 6) or (string.len(hex) == 8))
    local color = string.sub(hex,5,6) .. string.sub(hex,3,4) .. string.sub(hex,1,2)
    local alpha = nil
    if string.len(hex) == 8 then
        alpha = string.sub(hex,7,8)
    end
    return color, alpha
end
function Gui:asstools_create_color_from_hex(color)
    local gc = function(num,hex)
        local c,a = self:asstools_hex_rgb2bgr(hex)
        local result = ''
        if c then
            result = result .. '{\\' .. num .. 'c&H' .. c .. '&}'
        end
        if a then
            result = result .. '{\\' .. num .. 'a&H' .. a .. '&}'
        end
        return result
    end
    local result = ''
    result = result .. gc(1,color.primary)
    result = result .. gc(2,color.secondary)
    result = result .. gc(3,color.border)
    result = result .. gc(4,color.shadow)
    return result
end

function Gui:render_track_position(ass, px, py, rad, size, color, person_id)
    ass:new_event()
    ass:append('{\\org('..px..','..py..')}')
    if rad then
        ass:append('{\\frz'..self:tr_track_to_rotation_deg(rad)..'}')
        ass:append(self:asstools_create_color_from_hex(color))
        ass:pos(0,0)
        ass:draw_start()
        ass:move_to(px-size/2,py)
        ass:line_to(px,py-2*size) 
        ass:line_to(px+size/2,py)
        ass:draw_stop()
    else
        ass:append(self:asstools_create_color_from_hex(color))
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

function Gui:transform_and_draw_track(ass, track, time, tf, tf_target, size, main)
    local color_border = main and opts.track_pos_color_border or opts.track_pos_color_border_alt
    size = main and size or size*0.5
    local track_position = track:position(time)
    if (track_position) then 
        local position = track_position.position
        local interpolated = track_position.interpolated
        local track_endpoint = track_position.endpoint
        if position then
            local color = {border = color_border}
            if self.marked_track and (track.id == self.marked_track.id) then
                color.primary = opts.track_pos_color_selected
            elseif interpolated then
                color.primary = opts.track_pos_color_interpolated
            elseif track_endpoint then
                color.primary = opts.track_pos_color_endpoint
            else
                color.primary = opts.track_pos_color_annotation
            end
            local transformed_position = tf:transform_to(position,tf_target)
            msg.info('track',dump(position),'transformed to',tf_target,dump(transformed_position))
            local px, py = self:tr_track_to_px(transformed_position)
            self:render_track_position(ass, px, py, transformed_position.rad, size, color, track.person_id)
        end
    end
end

function Gui:draw_track_positions(ass,data)
    local tracks = data.tracks
    local tf = data.tf
    local tf_target = data.file
    local size = self:tr_video_to_px_scale(opts.position_size)/2
    local time = self:property('time-pos')
    if not time then return end
    time = math.floor(time*1000)
    for key, track in pairs(tracks) do
        self:transform_and_draw_track(ass, track, time, tf, tf_target, size, true)
    end
    for name, render in pairs(data.show_transformable) do
        if render and (data.transformable[name]) then
            for key, track in pairs(data.transformable[name]) do
               self:transform_and_draw_track(ass, track, time, tf, tf_target, size, false)
            end
        end
    end
    ass:draw_stop()
end

function Gui:draw_tracking_positions(ass)

end

function Gui:render_text_only(text)
    local ass = assdraw.ass_new()
    ass:pos(0,0)
    ass:append(text)
    mp.set_osd_ass(self:property('osd-width'), self:property('osd-height'), ass.text)
end

function Gui:render_clean()
    local ass = assdraw.ass_new()
    mp.set_osd_ass(self:property('osd-width'), self:property('osd-height'), ass.text)
end

function Gui:render_tracks(data)
    local ass = assdraw.ass_new()
    self:draw_track_positions(ass,data)
    --self:draw_tracking_positions(ass,tracking)
    mp.set_osd_ass(self:property('osd-width'), self:property('osd-height'), ass.text)
end

function Gui:render_gui()
    if self.data then
        if not self.data.ready then
           self:render_text_only("not ready yet. please wait a moment.")
        else
            self:render_tracks(self.data)
        end
    else
        self:render_clean()
    end
end

function Gui:on_tick()
    --msg.info("tick was triggered")
    if self.modified and self:property('video-scale') then
        self:render_gui()
        self.modified = false
    end        
end

function Gui:mouse_binding_wrapper(f)
    return function(...)
        local vx, vy = _gui:tr_px_to_video(mp.get_mouse_pos())
        f(vx, vy, ...)
    end
end


function Gui:add_mouse_binding(key, name, functor)
    mp.add_key_binding(key,name,self:mouse_binding_wrapper(functor))
end

function Gui:add_key_binding(key, name, functor)
    mp.add_key_binding(key,name,functor)
end

function Gui:add_observer(name, callback)
    if self.observers[name] then
        table.insert(self.observers[name],callback)
    else
        self.observers[name] = { callback }
    end
end

function Gui:call_observers(name, value)
    if self.observers[name] then
        for key, callback in pairs(self.observers[name]) do
            callback(value)
        end
    end
end

function Gui:add_time_binding(f)
    self:add_observer('time-pos',f)
end

return Gui