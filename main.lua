-- config
local opts = {
    person_tracking_file = "person-tracking-results.json",
    tf_filename = "transformations.json",
    td_filename = "time-deltas.json",
    starting = 'track_annotation'
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
local handler_track_annotation = require 'track-annotation'
local handler_group_annotation = require 'group-annotation'
local handler_export_annotation = require 'export-annotation'

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
    --- meta information
    tf = transform:new(),
    time_deltas = time_deltas:new(),
    --- state
    print_timestamps = false,
    handlers = { },
    handler_current = nil
}
_gui = Gui:new()

-- watch which file is opened. load corresponding data if necessary
function observe_path(name, data)
    local path = mp.get_property_native(name)
    if path == _data.path then return end
    assert(path)
    _data.ready = false
    if _data.handler_current then
        _data.handler_current:before_file_change()
    end
    _data.path = path
    local dir, file = utils.split_path(path)
    if not (_data.dir == dir) then
        msg.info('directory changed to:',dir)
        _data.dir = dir
        load_config_from_dir(dir)
    end
    msg.info('file changed from '.. dump(_data.file) .. ' to ' .. dump(file))
    _data.file = file
    if not (_data.file == nil) and (_data.handler_current) then
        _data.handler_current:after_file_change()
    end
    wait_for_video_to_start()
    goto_last_track_position()
    msg.info('memory usage:',collectgarbage('count')..'kbyte')
    collectgarbage()
    msg.info('memory usage:',collectgarbage('count')..'kbyte')
    _data.ready = true
end

--- main handler
main_handler = {}
main_handler.check_file_exists = function (filename)
    local f=io.open(filename,"r")
    if f~=nil then io.close(f) return true else return false end
end
main_handler.read_string_from_file = function(filename)
    if not (main_handler.check_file_exists(filename)) then return nil end
    local file = assert(io.open(filename,'r'))
    local string = file:read('*all')
    file:close()
    --msg.info('read data:',string)
    return string
end
main_handler.save_json_to_file = function(filename, json)
    --msg.info('saving ' .. json .. ' to file .. ' .. filename)
    assert(filename)
    assert(json)
    local file = assert(io.open(filename, 'w'))
    local string = file:write(json)
    file:close()
end
main_handler.notify = function()
    _gui:update_data(main_handler)
end
main_handler.is_ready = function()
    return _data.ready
end
main_handler.render = function(ass, gui)
    assert(_data.handler_current ~= main_handler)
    if _data.handler_current then
        _data.handler_current:render(ass, gui)
    end
    -- own rendering could be additionally done here
end
main_handler.goto_track_position_ms = function(time_ms)
    mp.set_property('time-pos',time_ms/1000)
end
main_handler.open_menu = function(vx, vy, append)
    local function generate_playlist_entries(handler)
        local result = {}
        local playlist = mp.get_property_native('playlist')
        for key, playlist_entry in pairs(playlist) do
            table.insert(result, { 
                "command", playlist_entry.filename, "", 
                function() 
                    set_current_track_time()
                    mp.set_property_number("playlist-pos",key-1) 
                end, "", not (playlist_entry.current == nil)})
        end
        return result
    end
    local menu_inst = menu:new()
    local menu_list = {
        context_menu = {
            {"cascade", "Play", "play_menu", "", "", false},
        },
        play_menu = {
            {"command", "Play/Pause", "Space", "cycle pause", "", false},
            {"command", "Stop", "Ctrl+Space", "stop", "", false},
            {"separator"},
            {"command", "Previous", "<", main_handler.playlist_previous, "", false},
            {"command", "Next", ">", main_handler.playlist_next, "", false},
            {"cascade", "Playlist", "playlist", "", "", false},
        },
        playlist = generate_playlist_entries(main_handler)
    }
    -- print timestamps
    if _data.print_timestamps then
        table.insert(menu_list.context_menu, {"command", "Hide timestamps", "", function () _data.print_timestamps = false end, "", false, false})
    else
        table.insert(menu_list.context_menu, {"command", "Print timestamps", "", function () _data.print_timestamps = true end, "", false, false})
    end
    -- change state
    table.insert(menu_list.context_menu, {"cascade", "Change State", "statelist", "", "", false})
    menu_list.statelist = {}
    for k,v in pairs(_data.handlers) do
        table.insert(menu_list.statelist,
        {"command", v:name(), "", function () main_handler.set_state(k)  end, "", false, false})
    end
    menu_inst:append(menu_list)
    menu_inst:append(append)
    menu_inst:menu_action(vx, vy)
end
main_handler.opt = function(name)
    return opts[name]
end
main_handler.data = function(name)
    return _data[name]
end
-- local helper funcitons
function load_transformations(dir)
    local tf_path = dir .. opts.tf_filename
    _data.tf = transform:deserialize(main_handler.read_string_from_file(tf_path))
    return tf
end
function load_time_deltas(dir)
    local td_path = dir .. opts.td_filename
    local data = main_handler.read_string_from_file(td_path)
    if not data then return end
    _data.time_deltas = time_deltas:deserialize(data)
    return tf
end
function load_config_from_dir(dir)
    local pause_state = mp.get_property_native('pause')
    msg.info('pausing for config load')
    mp.set_property_native('pause',true)
    main_handler.notify()
    msg.info('loading configuration from:',dir)
    load_transformations(dir)
    load_time_deltas(dir)
    mp.set_property_native('pause',pause_state)
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
function unset_current_track_time()
    _data.last_track_time_pos = nil
    _data.last_track_time_delta = nil
end
function set_current_track_time()
    _data.last_track_time_pos = _data.time
    _data.last_track_time_delta = _data.time_deltas.time_deltas[_data.file]
end
function on_shutdown()
    _data.handler_current:finish()
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

-- interaction
main_handler.playlist_next = function()
    set_current_track_time()
    mp.command('playlist-next')
end
main_handler.playlist_previous = function()
    set_current_track_time()
    mp.command('playlist-prev')
end
main_handler.exit = function()
    mp.command("quit")
end
main_handler.on_tick = function()
    if _data.print_timestamps then
        msg.info('time in tick:',mp.get_property_native('time-pos'))
    end
end
main_handler.on_time_change = function(time)
    _data.time = math.floor(time*1000)
end
main_handler.set_state = function(name)
    if not _data.handlers[name] then 
        msg.error('unknown target state: "'..name..'"') 
    elseif  _data.handler_current == _data.handlers[name] then
        msg.warn('cannot change to same state')
    else
        local old = _data.handler_current
        if old then
            remove_bindings(old:name(), old:get_actions())
            old:finish()
        end
        local next = _data.handlers[name]
        if next then
            next:init(main_handler)
            add_bindings(next:name(), next:get_actions())
            _data.handler_current = next
        end
        main_handler.notify()
    end
end

function add_bindings(prefix, actions)
    for k,v in pairs(actions) do
        if (v.type == 'mouse') then
            _gui:add_mouse_binding(v.event, prefix..'-'..v.name, v.callback, v.options)
        elseif (v.type == 'key') then
            _gui:add_key_binding(v.event, prefix..'-'..v.name, v.callback, v.options)
        else
            msg.warn('unknown action type:',dump(v))
        end
    end
end

function remove_bindings(prefix, actions)
    for k,v in pairs(actions) do
        if (v.type == 'mouse') or (v.type == 'key') then
            _gui:remove_key_binding( prefix..'-'..v.name)
        else
            msg.warn('unknown action type:',dump(v))
        end
    end
end

_gui:add_key_binding(">", "playlist_next", main_handler.playlist_next)
_gui:add_key_binding("<", "playlist_previous", main_handler.playlist_previous)
_gui:add_key_binding("g", "testing", main_handler.testing)
_gui:add_time_binding(main_handler.on_time_change)
mp.register_event("tick", main_handler.on_tick)

_data.handlers = { 
    track_annotation = handler_track_annotation:new(),
    group_annotation = handler_group_annotation:new(),
    export_annotation = handler_export_annotation:new()
}
main_handler.set_state(opts.starting)
