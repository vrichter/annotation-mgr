-- config
local opts = {
    person_tracking_file = "person-tracking-results.json",
    annotation_suffix = "-tracking-annotation.json",
    tf_filename = "transformations.json",
    td_filename = "time-deltas.json",
    jump_next_min_delta_ms = 10,
}
(require 'mp.options').read_options(opts,"annotation")

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'msg'
local Track = require 'track'
local Gui = require 'gui'
local dump = require 'dump'
local os = require 'os'
local menu = require 'menu'
local transform = require 'tf'
local time_deltas = require 'td'
local json = require 'dependencies/json'
local person = require 'person'

local debug = require 'debug'

-- local data
_data = {
    --- file and loading
    path = "",
    dir = "",
    file = "",
    ready = false,
    time = 0,
    last_track_time_pos = nil,
    last_track_time_delta = nil,
    selected_audio = {},
    --- annotations
    tracks = {},
    fixpoints = {},
    tracks_changed = false,
    --- static annotations
    transformable = {},
    persons = person:new(),
    --- meta information
    tf = transform:new(),
    time_deltas = time_deltas:new(),
    --- gui config
    show_transformable = {},
    show_persons = false,
    print_timestamps = false,
    --- state
    annotate_tracks = true
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
        msg.info('file changed from '.. dump(_data.file) .. ' to ' .. dump(file))
        if not (_data.file == nil) then
            save_annotation_for_file(dir .. '/' .. _data.file)
        end
        _data.file = file
        update_config_for_file(dir,file)
        _gui.marked_track = nil
    end
    wait_for_video_to_start()
    goto_last_track_position()
    msg.error('memory usage:',collectgarbage('count')..'kbyte')
    collectgarbage()
    msg.error('memory usage:',collectgarbage('count')..'kbyte')
    _data.ready = true
end
function check_file_exists(filename)
    local info = utils.file_info(filename)
    if (not info) or (not info['is_file']) then
        msg.info('file "' .. filename .. '" not found or is not regular file.')
        return false
    end
    return true
end
function read_string_from_file(filename)
    if not (check_file_exists(filename)) then return nil end
    local file = assert(io.open(filename,'r'))
    local string = file:read('*all')
    file:close()
    --msg.info('read data:',string)
    return string
end
function save_json_to_file(filename, json)
    --msg.info('saving ' .. json .. ' to file .. ' .. filename)
    assert(filename)
    assert(json)
    local file = assert(io.open(filename, 'w'))
    local string = file:write(json)
    file:close()
end
function load_person_tracking(dir)
    local person_path = dir .. opts.person_tracking_file
    msg.info('person tracking file: ' .. person_path)
    msg.error('not implemented')
end
function load_transformable_annotations()
    local tf_new = {}
    local show_new = {}
    if _data.tf.transformations[_data.file] then -- only when current file transformable
        for key, value in pairs(_data.tf.transformations) do
            local filename = _data.dir .. '/' .. key .. opts.annotation_suffix
            if (key ~= _data.file) and check_file_exists(filename) then
                if _data.transformable[key] then
                    show_new[key] = _data.show_transformable[key]
                end
                tf_new[key] = _data.time_deltas:adapt_track_times(
                    Track:deserialize_tracks(read_string_from_file(filename)),
                    key,
                    _data.file
                )
            else
                show_new[key] = nil
            end
        end
    end
    _data.transformable = tf_new
    _data.show_transformable = show_new
    local person_tracks = {_data.tracks}
    for k,v in pairs(tf_new) do table.insert(person_tracks,v) end
    _data.persons = person:create_from_tracks(person_tracks, _data.tf)
end
function load_transformations(dir)
    local tf_path = dir .. opts.tf_filename
    _data.tf = transform:deserialize(read_string_from_file(tf_path))
    return tf
end
function load_time_deltas(dir)
    local td_path = dir .. opts.td_filename
    local data = read_string_from_file(td_path)
    if not data then return end
    _data.time_deltas = time_deltas:deserialize(data)
    return tf
end
function load_config_from_dir(dir)
    local pause_state = mp.get_property_native('pause')
    msg.info('pausing for config load')
    mp.set_property_native('pause',true)
    _gui:update_data(_data)
    msg.info('loading configuration from:',dir)
    load_transformations(dir)
    load_time_deltas(dir)
    local pt = load_person_tracking(dir)
    if not (pt == nil) then
        _data.person_tracking = pt
    end
    mp.set_property_native('pause',pause_state)
end
function save_annotation_for_file(path)
    local filename = path
    if not _data.tracks_changed then
        msg.info("not saving unchanged annotation for:", filename)
        return 
    end
    local document = Track:serialize_tracks(_data.tracks)
    if document == "[]" then
        msg.info("not saving empty annotation for:", filename)
    else
        msg.info('saving annotation for file:', filename)
        save_json_to_file(filename .. opts.annotation_suffix, document)
    end
end
function ensure_frames_set()
    for name,track in pairs(_data.tracks) do
        for time, position in pairs(track.data) do
            if not position['frame_id'] then
                position['frame_id'] = _data.file
                _data.tracks_changed = true
            end
        end
    end
end
function load_annotation_for_file(path, file)
    local filename = path .. "/" .. file
    msg.info('loading annotation for file:', filename)
    local annotation = Track:deserialize_tracks(read_string_from_file(filename .. opts.annotation_suffix))
    if annotation then
        _data.tracks = annotation
    else
        _data.tracks = {}
    end
    _data.tracks_changed = false
    ensure_frames_set()
    load_transformable_annotations()
    _gui:update_data(_data)
    mp.set_property_native('pause',pause_state)
end
function update_config_for_file(path,file)
    load_annotation_for_file(path,file)
end
function wait_for_video_to_start()
    local last = os.date('%s')
    local count = 0
    while not mp.get_property_native('time-pos') do
        local now = os.date('%s')
        if now ~= last then
            msg.warn('waiting for video to start')
            last = now
            count = count + 1
        end
        if count > 3 then
            msg.warn('waiting for more than '..count..' seconds for video to start. give up.')
            return            
        end
    end
end
function goto_last_track_position()
    if true then
        local goto_time = _data.last_track_time_pos
        if not goto_time then return end
        local old_delta = _data.last_track_time_delta or 0
        local new_delta = _data.time_deltas:get_time_delta(_data.file)
        local goto_time = goto_time - old_delta + new_delta
        if goto_time > 0. then
            mp.set_property('time-pos',goto_time/1000)
        end
    end
    unset_current_track_time()
end
function on_shutdown()
    save_annotation_for_file(_data.path)
end
function find_selected_stream(tracklist, type)
    for k,v in pairs(tracklist) do
        if (v.type == type) and (v.selected == true) then
            return v
        end
    end
end
function adapt_external_audio_stream(title)
    local delta = _data.time_deltas:get_time_delta(title, _data.file)/1000.
    msg.info('adapt audio time:',delta)
    dump_pp(mp.set_property_native('audio-delay',delta))
end
function update_tracklist()
    local tracklist = mp.get_property_native('track-list')
    local new_selected_audio = find_selected_stream(tracklist, 'audio')
    if new_selected_audio then
        if new_selected_audio.external == true then
            adapt_external_audio_stream(new_selected_audio.title)
        end
    end
    _data.selected_audio = new_selected_audio
end
mp.observe_property("path", native, observe_path)
mp.register_event('shutdown',on_shutdown)
mp.register_event('audio-reconfig',update_tracklist)

-- update model
function data_insert_track(track)
    _data.tracks[track.id] = track
    _gui:update_data(_data)
    _data.tracks_changed = true
end
function data_remove_track(track)
    table.remove(_data.tracks)
    _gui:update_data(_data)
    _data.tracks_changed = true
end
function data_add_annotation(id,time,x,y,r,frame)
    msg.info('add annotation:',id,time,x,y,r,frame)
    if not _data.tracks[id] then
        msg.warn("id:" .. id .. " not found in tracks: " .. dump_pp(_data.tracks))
        return 
    end
    local position = _data.tracks[id]:position(time)
    if not position then return end
    local current = position.position
    if current then
        x = x or current.x
        y = y or current.y
        r = r or current.rad
        frame = frame or _data.file
    end
    msg.info('current:',dump(current),'r',r)
    _data.tracks[id]:add_annotation(time,x,y,r,frame)
    _gui:update_data(_data)
    _data.tracks_changed = true
end
function data_remove_annotation(id,time)
    msg.info('p',_data.tracks,'id',id,'pid',_data.tracks[id],'t',time)
    _data.tracks[id]:remove_annotation(time)
    _gui:update_data(_data)
    _data.tracks_changed = true
end


-- add, move, remove annotations from gui callbacks
function add_track_annotation(vx,vy)
    assert(vx)
    assert(vy)
    local track = Track:new()
    local time = _data.time
    track:add_annotation(time,vx,vy)
    track:set_start_time(time)
    msg.info('created a new track with position',dump(track))
    data_insert_track(track)
end
function find_annotation_next_to(vx,vy,max_dist)
    assert(vx)
    assert(vy)
    assert(max_dist)
    local next = nil
    local min_dist = nil
    local time = _data.time
for key, track in pairs(_data.tracks) do
        local track_pos = (track:position(time)).position
        if not (track_pos == nil) then
            local transformed = _data.tf:transform_to(track_pos, _data.file)
            local dist = _gui:calculate_dist(vx, vy, transformed.x, transformed.y)
            if min_dist == nil or dist < min_dist then
                min_dist = dist
                next = track
            end
        end
    end
    if next and max_dist and (min_dist >= max_dist) then
        return nil
    else
        return next
    end
end
function remove_track_annotation(vx,vy)
    assert(vx)
    assert(vy)
    local next = find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
    if next then
        data_remove_annotation(next.id,_data.time)
    end
end
function move_track(track, vx, vy)
    assert(vx)
    assert(vy)
    data_add_annotation(track.id,_data.time,vx,vy)
end
function rotate_track(track, vx, vy)
    assert(vx)
    assert(vy)
    local position = (track:position(_data.time)).position
    local rad = _gui:tr_rotation_from_points_rad(position.x,position.y,vx,vy)
    -- rotate marked track
    data_add_annotation(track.id,_data.time,position.x,position.y,rad)
end
function reset_end(annotation, time)
    local changed = false
    if (annotation:is_start_time(time)) then
        annotation:reset_start_time()
        changed = true
    end
    if (annotation:is_end_time(time)) then
        annotation:reset_end_time()
        changed = true
    end
    return changed
end
function set_end(annotation, time, vx, vy)
    local changed = false
    local entry = annotation:position(time)
    local first, last = annotation:get_time_endpoints()
    if (entry.position) then
        if (entry.interpolated) then
            data_add_annotation(annotation.id, time, vx, vy)
            changed = true
        end
        if (time >= last) then
            annotation:set_end_time(time)
            msg.info('setting endpoint:',time)
            changed = true
        elseif (time <= first) then
            annotation:set_start_time(time)
            msg.info('setting startpoint:',time)
            changed = true
        else
            msg.warn('cannot set endpoint in the middle:',first/1000 .. ' < ' .. time/1000 .. ' < ' .. last/1000)
        end
    end
    return changed
end
function toggle_end(track)
    --local annotation = find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
    if (track) then
        local time = _data.time
        if(reset_end(track, time)) then return true end
        if(set_end(track, time, vx, vy)) then return true end
      end
    return false
end
function find_next_neighbour_annotation(time, track)
    local time = time+1 -- after now
    -- next in track
    if track then
        local n = track:find_neighbours(time)
        if n then
            return n.next
        else
            return nil
        end
    end
    -- overall next
    local min_next = nil
    for key, value in pairs(_data.tracks) do
        local n = value:find_neighbours(time)
        if n and n.next and n.next.time then
            if not min_next then
                min_next = n.next
            elseif min_next.time > n.next.time then
                min_next = n.next
            end
        end
    end
    return min_next
end
function find_previous_neighbour_annotation(time, track)
    -- next in track
    if track then
        local n = track:find_neighbours(time)
        if n then
            return n.previous
        else
            return nil
        end
    end
    -- overall next
    local max_previous = nil
    for key, value in pairs(_data.tracks) do
        local n = value:find_neighbours(time)
        if n and n.previous and n.previous.time then
            if not max_previous then
                max_previous = n.previous
            elseif max_previous.time < n.previous.time then
                max_previous = n.previous
            end
        end
    end
    return max_previous
end
menu_handler = {}
menu_handler.set_person_id = function(track_id, person_id)
    msg.info("setting track id" .. track_id .. " to person '" .. person_id .. "'")
    _data.tracks[track_id].person_id = person_id
    _data.tracks_changed = true
    _gui.modified = true
end
menu_handler.get_person_ids = function()
    local result = {}
    for id, track in pairs(_data.tracks) do
        if track.person_id then
            result[track.person_id] = true
        end
    end
    return result
end
menu_handler.marked_track = function()
    return _gui.marked_track
end
menu_handler.add_fixpoint = function(name, vx, vy)
    _data.fixpoints[name] = {}
end
menu_handler.find_annotation_next_to = function(vx, vy)
    return find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
end
menu_handler.mark_track = function(track)
    _gui.marked_track = track
    _gui.modified = true
end
menu_handler.get_transformable = function()
    local result = {}
    for key, value in pairs(_data.transformable) do
        result[key] = not (_data.show_transformable[key] == nil)
    end
    return result
end
menu_handler.set_transformable = function(name, boolean)
    if (boolean == true) then
        _data.show_transformable[name] = true
    else
        _data.show_transformable[name] = nil
    end
    _gui.modified = true
end
menu_handler.toggle_endpoint = function(track)
    local changed = toggle_end(track)
    if changed then
        _data.tracks_changed = true
    end
    _gui.modified = true
end
menu_handler.show_persons = function()
    return _data.show_persons
end
menu_handler.set_show_persons = function(bool)
    _data.show_persons = bool
    _gui.modified = true
end
menu_handler.playlist_next = function()
    set_current_track_time()
    mp.command('playlist-next')
end
menu_handler.playlist_previous = function()
    set_current_track_time()
    mp.command('playlist-prev')
end
menu_handler.save_track_position = function()
    set_current_track_time()
end
menu_handler.print_timestamps = function()
    return _data.print_timestamps
end
menu_handler.set_print_timestamps = function(bool)
    _data.print_timestamps = bool
end
function ctrl_left_click_handler(vx,vy,event)
    add_track_annotation(vx,vy)
end
function ctrl_right_click_handler(vx,vy,event)
    remove_track_annotation(vx,vy)
end
function left_click_handler(vx,vy,event)
    if not _gui.marked_track then
        _gui.marked_track = find_annotation_next_to(vx,vy,_gui.opts.position_size/2)
    else 
        move_track(_gui.marked_track, vx, vy)
        _gui.marked_track = nil
        _gui.modified = true
    end
    _gui.modified = true
end

function right_click_handler(vx,vy,event)
    if not _gui.marked_track then
        local menu_inst = menu:new({})
        menu:menu_action(menu_handler, vx, vy)
    else 
        rotate_track(_gui.marked_track,vx,vy)
        _gui.marked_track = nil
        _gui.modified = true
    end
end
function escape_handler()
    _gui.marked_track = nil
    _gui.modified = true
end
function end_handler()
    local next = find_next_neighbour_annotation(_data.time+opts.jump_next_min_delta_ms, _gui.marked_track)
    if next and next.time then
        msg.info('now: '.. _data.time .. ' goto next annotation: ' .. next.time)
        mp.set_property('time-pos',next.time/1000)
    end
end
function home_handler()
    local previous = find_previous_neighbour_annotation(_data.time-opts.jump_next_min_delta_ms, _gui.marked_track)
    if previous and previous.time then
        msg.info('now: ' .. _data.time .. ' goto previous annotation: ' .. previous.time)
        mp.set_property('time-pos',previous.time/1000)
    end
end
function ctrl_s_handler(vx,vy,event)
    if (_data.dir ~= nil) and (_data.file ~= nil) then
        _data.tracks_changed = true
        save_annotation_for_file(_data.dir .. '/' .. _data.file)
        _data.tracks_changed = false
    end
end
function unset_current_track_time()
    _data.last_track_time_pos = nil
    _data.last_track_time_delta = nil
end
function set_current_track_time()
    _data.last_track_time_pos = _data.time
    _data.last_track_time_delta = _data.time_deltas.time_deltas[_data.file]
end
function move_handler(addx, addy, addr)
    if _gui.marked_track then
        local time = _data.time
        local p = _gui.marked_track:position(time)
        if p.position then
            local new_rad = nil
            if p.position.rad then
                new_rad = p.position.rad + addr
            elseif addr ~= 0 then
                new_rad = addr
            end
            _gui.marked_track:add_annotation(time, p.position.x+addx, p.position.y+addy, new_rad, p.position.frame_id)
            _data.tracks_changed = true
            _gui.modified = true
        end
    end
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

function on_tick()
    if _data.print_timestamps then
        msg.info('time in tick:',mp.get_property_native('time-pos'))
    end
end

function on_frame(name,data)
    msg.info(dump_pp(data))
end

--mp.add_key_binding("MBTN_LEFT", "", left_click_handler, { complex = true })
_gui:add_mouse_binding("Ctrl+MBTN_LEFT", "ctrl_left_click_handler", if_ready(ctrl_left_click_handler))
_gui:add_mouse_binding("Ctrl+MBTN_RIGHT", "ctrl_right_click_handler", if_ready(ctrl_right_click_handler))
_gui:add_mouse_binding("MBTN_LEFT", "left_click_handler", if_ready(left_click_handler))
_gui:add_mouse_binding("MBTN_RIGHT", "right_click_handler", if_ready(right_click_handler))
_gui:add_mouse_binding("Shift+MBTN_LEFT", "shift_left_click_handler", if_ready(shift_left_click_handler))
--_gui:add_mouse_binding("Shift+MBTN_RIGHT", "shift_right_click_handler", if_ready(shift_right_click_handler))
_gui:add_key_binding("Ctrl+s", "ctrl_s_handler", if_ready(ctrl_s_handler))
_gui:add_key_binding("ESC", "escape_handler", if_ready(escape_handler))
_gui:add_key_binding("END", "end_handler", if_ready(end_handler), {repeatable=true})
_gui:add_key_binding("HOME", "home_handler", if_ready(home_handler), {repeatable=true})
_gui:add_key_binding("Alt+UP", "move_handler_up", if_ready(function() move_handler(0,-1,0) end), {repeatable=true})
_gui:add_key_binding("Alt+DOWN", "move_handler_down", if_ready(function() move_handler(0,1,0) end), {repeatable=true})
_gui:add_key_binding("Alt+LEFT", "move_handler_left", if_ready(function() move_handler(-1,0,0) end), {repeatable=true})
_gui:add_key_binding("Alt+RIGHT", "move_handler_right", if_ready(function() move_handler(1,0,0) end), {repeatable=true})
_gui:add_key_binding("Alt+q", "move_handler_rotate_left", if_ready(function() move_handler(0,0,-math.pi/64) end), {repeatable=true})
_gui:add_key_binding("Alt+e", "move_handler_rotate_right", if_ready(function() move_handler(0,0,math.pi/64) end), {repeatable=true})
_gui:add_key_binding("n", "name_handler", if_ready(name_handler))
_gui:add_key_binding(">", "playlist_next", if_ready(menu_handler.playlist_next))
_gui:add_key_binding("<", "playlist_previous", if_ready(menu_handler.playlist_previous))
_gui:add_key_binding("g", "testing", if_ready(menu_handler.testing))
_gui:add_time_binding(function(time) _data.time = math.floor(time*1000) end)
mp.register_event("tick", on_tick)
