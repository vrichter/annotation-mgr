-- config
local opts = {
    position_size = 50,
    person_pos_color = "{\\3c&H00ff00&}{\\1c&H0000ff&}{\\1a&Hbb&}"
}
(require 'mp.options').read_options(opts,"annotation")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

-- data
local _properties = {}
local _persons = {}

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

print(dump(mp))

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
mp.observe_property("dwidth", native, observe_video_w)
mp.observe_property("dheight", native, observe_video_h)
mp.observe_property("osd-width", native, observe_osd_w)
mp.observe_property("osd-height", native, observe_osd_h)

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
    render_annotations()
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
function draw_person_positions(persons, ass)
    local size = tr_video_to_px_scale(opts.position_size)
    ass:new_event()
    ass:pos(0,0)
    ass:append(opts.person_pos_color)
    ass:draw_start()
    for id, person in pairs(persons) do
        local px, py = tr_person_to_px(person)
        ass:rect_cw(px-size/2, py-size/2, px+size/2, py+size/2)
    end
    ass:draw_stop()
    mp.set_osd_ass(_properties['osd-w'], _properties['osd-h'], ass.text)
end

function render_annotations()
    local ass = assdraw.ass_new()
    draw_person_positions(_persons,ass)
    mp.set_osd_ass(_properties['osd-w'], _properties['osd-h'], ass.text)
end

-- annotations 
function add_person_annotation(mx,my)
    local vx, vy = tr_px_to_video(mx,my)
    table.insert(_persons,{x=vx, y=vy})
    render_annotations()
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
    render_annotations()
end

function left_click_handler(event)
    local mx, my = mp.get_mouse_pos()
    add_person_annotation(mx,my)
end

function right_click_handler(event)
    local mx, my = mp.get_mouse_pos()
    remove_person_annotation(mx,my)
end

function on_tick()
    --print("tick was triggered")
end

--mp.add_key_binding("MBTN_LEFT", "", left_click_handler, { complex = true })
mp.add_key_binding("MBTN_LEFT", "left_click_handler", left_click_handler)
mp.add_key_binding("MBTN_RIGHT", "right_click_handler", right_click_handler)
mp.register_event("tick", on_tick)