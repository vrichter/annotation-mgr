-- config
local opts = {
    person_tracking_file = "persontracking.json-",
}
(require 'mp.options').read_options(opts,"annotation")

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local Person = require 'person'
local Gui = require 'gui'
local dump = require 'dump'

-- local data
_data = {
    path = "",
    dir = "",
    ready = false,
    time = 0,
    persons = {}
}
_gui = Gui:new()

-- watch which file is opened. load corresponding data if necessary
function observe_path(name, data)
    local path = mp.get_property_native(name)
    if path == nil then
      msg.warn('path is nil')
      return
    end
    if path == _data.path then
        return
    else
        _data.path = path
    end
    _data.ready = false
    local dir, file = utils.split_path(path)
    if not (_data.dir == dir) then
        msg.info('directory changed to:',dir)
        _data.dir = dir
        load_config_from_dir(dir)
    end
    if not (_data.file == file) then
        _data.file = file
        update_config_for_file(dir,file)
    end
    _data.ready = true
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
    _gui:update_data('paused for loading annotations. please wait a moment.')
    mp.set_property_native('pause',true)
    msg.info('loading configuration from:',dir)
    local pt = load_person_tracking(dir)
    if not pt == nil then
        _data.person_tracking = pt
    end
    _gui:update_data(_data.person)
    mp.set_property_native('pause',pause_state)
end
function update_config_for_file(path,file)
    msg.info('update config for file not implemented. path:',path,' file:',file)
end
mp.observe_property("path", native, observe_path)

-- update model
function data_insert_person(person)
    table.insert(_data.persons,person)
    _gui:update_data(_data.persons)
end
function data_remove_person(person)
    table.remove(_data.persons)
    _gui:update_data(_data.persons)
end
function data_add_annotation(id,time,x,y,r)
    print('add annotation:',id,time,x,y,r)
    local current = _data.persons[id]:position(time)
    if current then
        x = x or current.x
        y = y or current.y
        r = r or current.rad
    end
    print('current:',dump(current),'r',r)
    _data.persons[id]:add_annotation(time,x,y,r)
    _gui:update_data(_data.persons)
end
function data_remove_annotation(id,time)
    print('p',_data.persons,'id',id,'pid',_data.persons[id],'t',time)
    _data.persons[id]:remove_annotation(time)
    _gui:update_data(_data.persons)
end


-- add, move, remove annotations from gui callbacks
function add_person_annotation(vx,vy)
    assert(vx)
    assert(vy)
    local person = Person:new()
    person:add_annotation(_data.time,vx,vy)
    msg.info('created a new person with position',dump(person))
    data_insert_person(person)
end
function find_annotation_next_to(vx,vy,max_dist)
    assert(vx)
    assert(vy)
    assert(max_dist)
    local next = nil
    local min_dist = nil
    local time = _data.time
    for key, person in pairs(_data.persons) do
        local person_pos = person:position(time)
        if not (person_pos == nil) then
            local pvx, pvy = _gui:tr_person_to_video(person_pos)
            local dist = _gui:calculate_dist(vx, vy, pvx, pvy)
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
function remove_person_annotation(vx,vy)
    assert(vx)
    assert(vy)
    local next = find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
    if next then
        data_remove_annotation(next.id,_data.time)
    end
end
function move_person(vx, vy)
    assert(vx)
    assert(vy)
    data_add_annotation(_gui.marked_person.id,_data.time,vx,vy)
end
function rotate_person(vx, vy)
    assert(vx)
    assert(vy)
    local position = _gui.marked_person:position(_data.time)
    local rad = _gui:tr_rotation_from_points_rad(position.x,position.y,vx,vy)
    -- rotate marked person
    data_add_annotation(_gui.marked_person.id,_data.time,position.x,position.y,rad)
end

function select_or(f,vx,vy,...)
    if _gui.marked_person then
        -- call function and unmark person
        f(vx,vy,...)
        _gui.marked_person = nil
        _gui.modified = true
    else
        -- mark person
        _gui.marked_person = find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
        _gui.modified = true
    end
end

function ctrl_left_click_handler(vx,vy,event)
    add_person_annotation(vx,vy)
end
function ctrl_right_click_handler(vx,vy,event)
    remove_person_annotation(vx,vy)
end
function left_click_handler(vx,vy,event)
    select_or(move_person,vx,vy)
end
function right_click_handler(vx,vy,event)
    select_or(rotate_person,vx,vy)
end

function if_ready(f)
    return function(...)
        if _data.ready then
            f(...)
        else
            return
        end
    end
end

--function on_tick()
    --msg.info("tick was triggered")
    --msg.info('time in tick:',mp.get_property_native('time-pos'))
--end

--mp.add_key_binding("MBTN_LEFT", "", left_click_handler, { complex = true })
_gui:add_mouse_binding("Ctrl+MBTN_LEFT", "ctrl_left_click_handler", if_ready(ctrl_left_click_handler))
_gui:add_mouse_binding("Ctrl+MBTN_RIGHT", "ctrl_right_click_handler", if_ready(ctrl_right_click_handler))
_gui:add_mouse_binding("MBTN_LEFT", "left_click_handler", if_ready(left_click_handler))
_gui:add_mouse_binding("MBTN_RIGHT", "right_click_handler", if_ready(right_click_handler))
_gui:add_time_binding(function(time) _data.time = time end)
--mp.register_event("tick", on_tick)
