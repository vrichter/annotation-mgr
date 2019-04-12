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
    mp.observe_property("time-pos", native, bind(o,'observe_time'))
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
function Gui:px_to_video(x,y)
    local vx = self:property('video-x')
    local vy = self:property('video-y')
    local vs = self:property('video-scale')
    if vx and vy and vs then
        -- first remove padding, then scale with video scale
        return (x-vx)/vs, (y-vy)/vs
    else
        msg.warn('could not get required screen info: video-x = ',vx,'video-y = ',y,'video-scale = ',vs)
        return nil, nil
    end
end
function Gui:video_to_px(x,y)
    -- scale with video scale, then add padding
    return x*self:property('video-scale')+self:property('video-x'), y*self:property('video-scale')+self:property('video-y')
end
function Gui:video_to_px_scale(x)
    return x*self:property('video-scale')
end

-- render functions
function Gui:asstools_hex_rgb2bgr(hex_in)
    if not hex_in then return nil, nil end
    local pattern = "^#?([0-9a-fA-F]+)$"
    hex = hex_in:match(pattern)
    if not hex or string.len(hex) < 6 then 
        msg.error('could not match',hex_in,'to',pattern)
        return nil, nil 
    end
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

function Gui:render_state(handler)
    local ass = assdraw.ass_new()
    handler.render(ass, self)
    mp.set_osd_ass(self:property('osd-width'), self:property('osd-height'), ass.text)
end

function Gui:render_gui()
    if self.data then
        if not self.data.is_ready() then
           self:render_text_only("not ready yet. please wait a moment.")
        else
            self:render_state(self.data)
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
        local vx, vy = _gui:px_to_video(mp.get_mouse_pos())
        if vx and vy then
            f(vx, vy, ...)
        else
            msg.warn('could not get mouse position in video coordinates')
        end
    end
end

function Gui:if_ready_wrapper(f)
    return function(...)
        if self.data.is_ready() then
            f(vx, vy, ...)
        else
            msg.ward('ignoring callback while not ready')
        end
    end
end

function Gui:add_mouse_binding(key, name, functor, flags)
    mp.add_key_binding(key,name,self:if_ready_wrapper(self:mouse_binding_wrapper(functor), flags))
end

function Gui:add_key_binding(key, name, functor, flags)
    mp.add_key_binding(key,name,self:if_ready_wrapper(functor),flags)
end

function Gui:remove_key_binding(name)
    mp.remove_key_binding(name)
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