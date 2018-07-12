-- config
local opts = {
    position_size = 50,
    person_pos_color_annotation = '#268f2666',
    person_pos_color_interpolated = '#26268f66',
    person_pos_color_selected = '#8f262666',
    person_pos_color_border = '#000000',
    person_tracking_file = "persontracking.json-",
}
(require 'mp.options').read_options(opts,"annotation")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- data
local _properties = {}
local _property_time = nil
local _annotations = {}
local _person_tracking = {}
local _persons = {}

-- gui state
local _ready = false
local _gui_marked_person = nil

-- helper functions
function dump(o)
    -- thanks to https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

-- classes
local Annotations = {}
function Annotations:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.data = {}
    return o
end
function Annotations:add(time,value)
    if not self.data[time] then
        self.data[time] = value
    else
        for k,v in pairs(value) do
            self.data[time][k] = v
        end
    end
end
function Annotations:get_entry(time)
    return self.data[time]
end
function Annotations:find_neighbours(time)
    local less_dist = nil
    local lessval = nil
    local more_dist = nil
    local moreval = nil
    for key, value in pairs(self.data) do
        if key < time then
            if (not less_dist) or (time-key < less_dist) then
                less_dist = time-key
                lessval = value
            end
        else
            if (not more_dist) or (key-time < more_dist) then
                more_dist = key-time
                moreval = value
            end
        end
    end
    return lessval, moreval, less_dist, more_dist
end

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
function Person:add_annotation(time,x_postition,y_position)
    self.annotations:add(time,{x=x_postition,y=y_position})
end
function Person:interpolate(p,n,dt_before,dt_after)
    local px = p.x
    local py = p.y
    local nx = n.x
    local ny = n.y
    local vx = (nx-px)/(dt_before+dt_after)
    local vy = (ny-py)/(dt_before+dt_after)
    return { x=(px+vx*dt_before), y=(py+vy*dt_before) }
end
function Person:current_position(time)
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

-- property watchers
function observe_property(name, data)
    if data == nil then
        data = mp.get_property_native(name)
    end
    return data
end
function observe_video_w(name, data)
    _properties['video-w'] = observe_property(name,data)
end
function observe_video_h(name, data)
    _properties['video-h'] = observe_property(name,data)
end
function observe_osd_w(name, data)
    _properties['osd-w'] = observe_property(name,data)
    update_video_position()
end
function observe_osd_h(name, data)
    _properties['osd-h'] = observe_property(name,data)
    update_video_position()
end
function observe_path(name, data)
    local path = observe_property(name,data)
    if path == _properties['path'] then
        return
    else
        _properties['path'] = path
    end
    _ready = false
    local dir, file = utils.split_path(path)
    if not (_properties['dir'] == dir) then
        msg.info('directory changed to:',dir)
        _properties['dir'] = dir
        load_config_from_dir(dir)
    end
    if not (_properties['file'] == file) then
        _properties['file'] = file
        update_config_for_file(dir,file)
    end
    _ready = true
end
function observe_time(name,data)
    local time = observe_property(name,data)
    if not (_property_time == time) then
        msg.trace("time changed:",time)
        _property_time = time
        render_gui()
    end
end
mp.observe_property("dwidth", native, observe_video_w)
mp.observe_property("dheight", native, observe_video_h)
mp.observe_property("osd-width", native, observe_osd_w)
mp.observe_property("osd-height", native, observe_osd_h)
mp.observe_property("path", native, observe_path)
mp.observe_property("time-pos", native, observe_time)

function update_video_position()
    local ww = _properties['osd-w']
    local wh = _properties['osd-h']
    local vw = _properties['video-w']
    local vh = _properties['video-h']
    if ww == nil  or wh == nil or  vw == nil or vh == nil then
        return
    end
    local scale=ww/vw
    if wh/vh < scale then
        scale = wh/vh
    end
    _properties['video-x'] = (ww-(vw*scale))/2
    _properties['video-y'] = (wh-(vh*scale))/2
    _properties['video-scale'] = scale
    render_gui()
end

function load_person_tracking(dir)
    local person_path = dir .. opts.person_tracking_file
    local info = utils.file_info(person_path)
    if (not info) or (not info['is_file']) then
        msg.info('person tracking file not found or is not regular file.')
        return nil
    end
    local file = assert(io.open(person_path))
    local string = file:read('*all')
    file:close()
    msg.info('parsing to json')
    local parsed = utils.parse_json(string)
    msg.info('parsing to json done.')
    return parsed
end

function load_config_from_dir(dir)
    local pause_state = mp.get_property_native('pause')
    msg.info('pausing for config load')
    render_text_only('paused for loading annotations. please wait a moment.')
    mp.set_property_native('pause',true)
    msg.info('loading configuration from:',dir)
    local pt = load_person_tracking(dir)
    if not pt == nil then
        _person_tracking = pt
    end
    mp.set_property_native('pause',pause_state)
end

function update_config_for_file(path,file)
    msg.info('update config for file not implemented. path:',path,' file:',file)
end

-- transformations
function tr_px_to_video(x,y)
    -- first remove padding, then scale with video scale
    return (x-_properties['video-x'])/_properties['video-scale'], (y-_properties['video-y'])/_properties['video-scale']
end
function tr_video_to_px(x,y)
    -- scale with video scale, then add padding
    return x*_properties['video-scale']+_properties['video-x'], y*_properties['video-scale']+_properties['video-y']
end
function tr_video_to_px_scale(x)
    return x*_properties['video-scale']
end
function tr_person_to_video(person)
    return person['x'], person['y']
end
function tr_person_to_px(person)
    return tr_video_to_px(tr_person_to_video(person))
end
function calculate_dist(ax,ay,bx,by)
    return math.sqrt(math.abs((bx-ax)^2-(by-ay)^2))
end

-- render functions
Asstools = {}
function Asstools.hex_rgb2bgr(hex)
    if not hex then return nil, nil end
    print('before: ',hex)
    hex = hex:match("^#?([1-9a-fA-F]+)$")
    print('after: ',hex)
    if not hex then return nil, nil end
    assert((string.len(hex) == 6) or (string.len(hex) == 8))
    color = string.sub(hex,5,6) .. string.sub(hex,3,4) .. string.sub(hex,1,2)
    alpha = nil
    if string.len(hex) == 8 then
        alpha = string.sub(hex,7,8)
    end
    print('result:',color,alpha)
    return color, alpha
end
function Asstools.create_color_from_hex(color)
    local gc = function(num,hex)
        local c,a = Asstools.hex_rgb2bgr(hex)
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

function draw_person_positions(ass)
    local size = tr_video_to_px_scale(opts.position_size)/2
    for key, person in pairs(_persons) do
        local position, interpolated = person:current_position()
        print('po',position,interpolated)
        if position then
            local color = {border = opts.person_pos_color_border}
            if _gui_marked_person and (person.id == _gui_marked_person.id) then
                print('color selected')
                color.primary = opts.person_pos_color_selected
            elseif interpolated then
                print('color interpolated')
                color.primary = opts.person_pos_color_interpolated
            else
                color.primary = opts.person_pos_color_annotation
            end
            local px, py = tr_person_to_px(position)
            ass:new_event()
            ass:append(Asstools.create_color_from_hex(color))
            ass:pos(0,0)
            ass:draw_start()
            ass:rect_cw(px-size, py-size, px+size, py+size)
        end
    end
    ass:draw_stop()
end

function draw_tracking_positions(ass)

end

function render_text_only(text)
    local ass = assdraw.ass_new()
    ass:pos(0,0)
    ass:append(text)
    mp.set_osd_ass(_properties['osd-w'], _properties['osd-h'], ass.text)
end

function render_clean()
    local ass = assdraw.ass_new()
    mp.set_osd_ass(_properties['osd-w'], _properties['osd-h'], ass.text)
end

function render_gui()
    local ass = assdraw.ass_new()
    draw_person_positions(ass)
    draw_tracking_positions(ass)
    mp.set_osd_ass(_properties['osd-w'], _properties['osd-h'], ass.text)
end

-- gui functions
function add_person_annotation(mx,my)
    local vx, vy = tr_px_to_video(mx,my)
    local person = Person:new()
    person:add_annotation(_property_time,vx,vy)
    msg.info('created a new person with position position',dump(person))
    table.insert(_persons,person)
    render_gui()
end
function find_annotation_next_to_mouse(mx,my,max_dist)
    local mvx,mvy = tr_px_to_video(mx,my)
    local next = nil
    local min_dist = nil
    for key,person in pairs(_persons) do
        local person_pos = person:current_position()
        if not (person_pos == nil) then
            local vx, vy = tr_person_to_video(person:current_position())
            local dist = calculate_dist(mvx, mvy, vx, vy)
            if min_dist == nil or dist < min_dist then
                min_dist = dist
                next = person
            end
        end
    end
    if next and max_dist and (min_dist >= max_dist) then
        return nil
    else
        return next
    end
end
function remove_person_annotation(mx,my)
    local mvx,mvy = tr_px_to_video(mx,my)
    local next = nil
    local min_dist = nil
    for key,person in pairs(_persons) do
        local vx, vy = tr_person_to_video(person)
        local dist = calculate_dist(mvx, mvy, vx, vy)
        if min_dist == nil or dist < min_dist then
            min_dist = dist
            next  = key
        end
    end
    table.remove(_persons,next)
    render_gui()
end
function ctrl_left_click_handler(event)
    if not _ready then return end
    local mx, my = mp.get_mouse_pos()
    print('mouse:',dump(event))
    add_person_annotation(mx,my)
end

function left_click_handler(event)
    if not _ready then return end
    local mx, my = mp.get_mouse_pos()
    print('mouse:',dump(event))
    if _gui_marked_person then
        -- move marked person
        print('persons: ',dump(_persons))
        _persons[_gui_marked_person.id]:add_annotation(_property_time, tr_px_to_video(mx,my))
        _gui_marked_person = nil
    else
        -- mark person
        _gui_marked_person = find_annotation_next_to_mouse(mx,my,opts.position_size/2)
    end
    render_gui()
end

function right_click_handler(event)
    if not _ready then return end
    local mx, my = mp.get_mouse_pos()
    remove_person_annotation(mx,my)
end

function on_tick()
    --msg.info("tick was triggered")
    --msg.info('time in tick:',mp.get_property_native('time-pos'))
end

--mp.add_key_binding("MBTN_LEFT", "", left_click_handler, { complex = true })
mp.add_key_binding("Ctrl+MBTN_LEFT", "ctrl_left_click_handler", ctrl_left_click_handler)
mp.add_key_binding("MBTN_LEFT", "left_click_handler", left_click_handler)
mp.add_key_binding("MBTN_RIGHT", "right_click_handler", right_click_handler)
mp.register_event("tick", on_tick)
