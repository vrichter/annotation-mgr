-- config
local opts = {
    position_size = 50,
    person_pos_color_annotation = '#268f2666',
    person_pos_color_interpolated = '#26268f66',
    person_pos_color_selected = '#8f262666',
    person_pos_color_border = '#000000',
}
(require 'mp.options').read_options(opts,"annotation-gui")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local Person = require 'person'
local dump = require 'dump'

local function bind(t, k)
    print('bind:',t,k)
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
    self.marked_person = nil
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
    print('self',self,'set data:',dump(self.data))
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
function Gui:tr_person_to_video(person)
    return person.x, person.y
end
function Gui:tr_person_to_px(person)
    return self:tr_video_to_px(self:tr_person_to_video(person))
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

function Gui:draw_person_positions(ass,persons)
    local size = self:tr_video_to_px_scale(opts.position_size)/2
    local time = self:property('time-pos')
    for key, person in pairs(persons) do
        local position, interpolated = person:position(time)
        if position then
            local color = {border = opts.person_pos_color_border}
            if self.marked_person and (person.id == self.marked_person.id) then
                color.primary = opts.person_pos_color_selected
            elseif interpolated then
                color.primary = opts.person_pos_color_interpolated
            else
                color.primary = opts.person_pos_color_annotation
            end
            local px, py = self:tr_person_to_px(position)
            ass:new_event()
            ass:append(self:asstools_create_color_from_hex(color))
            ass:pos(0,0)
            ass:draw_start()
            ass:rect_cw(px-size, py-size, px+size, py+size)
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

function Gui:render_persons(persons)
    local ass = assdraw.ass_new()
    self:draw_person_positions(ass,persons)
    --self:draw_tracking_positions(ass,tracking)
    mp.set_osd_ass(self:property('osd-width'), self:property('osd-height'), ass.text)
end

function Gui:render_gui()
    print('self',self,'set data:',dump(self.data))
    if not self.data then
        msg.info("render: clean")
        self:render_clean()
    elseif type(self.data) == 'string' then
        msg.info("render: text")
        self:render_text_only(self.data)
    else 
        msg.info("render: persons")
        self:render_persons(self.data)
    end
end

function Gui:on_tick()
    --msg.info("tick was triggered")
    if self.modified then
        msg.info("modified: true",self)
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