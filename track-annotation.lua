local opts = {
    annotation_suffix = "-tracking-annotation.json",
    next_annotation_max_dist = 25,
    jump_next_min_delta_ms = 10,
}
(require 'mp.options').read_options(opts,"track-annotation")



local Track = require "track"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local person = require 'person'
local render = require 'render-track-annotation'
local ut = require 'utils'

local TrackAnnotation = {}
function TrackAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.tracks = {}
    self.tracks_changed = false
    self.marked_track = nil
    self.transformable = {}
    self.show_transformable = {}
    self.persons = {}
    self.show_persons = false
    self.renderer = render:new()
    self.main = {}
    return o
end
--- interface
function TrackAnnotation:name()
    return 'track_annotation'
end
function TrackAnnotation:init(main)
    self.main = main
    self.actions = self.create_actions(self)
    self:after_file_change()
end
function TrackAnnotation:finish()
    self:save_annotations()
end
function TrackAnnotation:before_file_change()
    self:save_annotations()
end
function TrackAnnotation:after_file_change()
    self:load_annotations()
    self:load_transformable_annotations()
end
function TrackAnnotation:get_actions()
    return self.actions
end
function TrackAnnotation:render(ass, gui)
    self.renderer:render(self, ass, gui)
end
--- helper functions
function TrackAnnotation:add_track(track)
    table:insert(self.tracks,track)
end
function TrackAnnotation:save_annotations()
    if not self.tracks_changed then
        msg.info("not saving unchanged annotation for")
        return
    end
    local document = Track:serialize_tracks(self.tracks)
    if document == "[    ]" then
        msg.info("not saving empty annotation")
    else
        local filename = self.main.data('path')
        msg.info('saving annotation for file:', filename)
        self.main.save_json_to_file(filename .. opts.annotation_suffix, document)
    end
    self.tracks_changed = false
end
local function ensure_frames_set(tracks,frame)
    local tracks = tracks or {}
    local changed = false
    for name, track in pairs(tracks) do
        for time, position in pairs(track.data) do
            if not position.frame_id then
                position.frame_id = frame
                changed = true
            end
        end
    end
    return changed, tracks
end

function TrackAnnotation:load_annotations()
    assert(self.tracks_changed == false)
    local filename = self.main.data('path')
    msg.info('loading annotation for file:', filename)
    self.tracks_changed, self.tracks = ensure_frames_set(Track:deserialize_tracks(self.main.read_string_from_file(filename .. opts.annotation_suffix)))
end
function TrackAnnotation:load_transformable_annotations()
    local tf_new = {}
    local tf = self.main.data('tf')
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    local current_dir = self.main.data('dir')
    local suffix = opts.annotation_suffix
    if tf:get(current_frame) then -- only when current file transformable
        for key, value in pairs(tf:get_all()) do
            local filename = current_dir .. '/' .. key .. suffix
            if (key ~= current_frame) and self.main.check_file_exists(filename) then
                tf_new[key] = td:adapt_track_times(Track:deserialize_tracks(self.main.read_string_from_file(filename)), key, current_frame)
            end
        end
    end
    self.transformable = tf_new
    local person_tracks = {self.tracks}
    for k,v in pairs(tf_new) do table.insert(person_tracks,v) end
    self.persons = person:create_from_tracks(person_tracks, tf)
end

-- update model
function TrackAnnotation:add_annotation(id,time,x,y,r,frame)
    msg.info('add annotation:',id,time,x,y,r,frame)
    if not self.tracks[id] then
        msg.warn("id:" .. id .. " not found in tracks: " .. dump_pp(self.tracks))
        return 
    end
    local position = self.tracks[id]:position(time)
    if not position then return end
    local current = position.position
    if current then
        x = x or current.x
        y = y or current.y
        r = r or current.rad
        frame = frame or self.main.data('file')
    end
    msg.info('current:',dump(current),'r',r)
    self.tracks[id]:add_annotation(time,x,y,r,frame)
    self.tracks_changed = true
    self.main.notify()
end
function TrackAnnotation:remove_annotation(id,time)
    msg.info('p',self.tracks,'id',id,'pid',self.tracks[id],'t',time)
    self.tracks[id]:remove_annotation(time)
    if self.tracks[id]:is_empty() then
        self.tracks[id] = nil
    end
    self.tracks_changed = true
    self.main.notify()
end
function TrackAnnotation:add_track(vx,vy)
    assert(vx)
    assert(vy)
    local track = Track:new()
    local time = _data.time
    track:add_annotation(time,vx,vy)
    track:set_start_time(time)
    msg.info('created a new track with position',dump(track))
    self.tracks[track.id] = track
    self.tracks_changed = true
    self.main.notify()
end
function TrackAnnotation:find_annotation_next_to(vx,vy,max_dist)
    assert(vx)
    assert(vy)
    local max_dist = max_dist or opts.next_annotation_max_dist
    assert(max_dist)
    local next = nil
    local min_dist = nil
    local time = self.main.data('time')
    local tf = self.main.data('tf')
    for key, track in pairs(self.tracks) do
        local track_pos = (track:position(time)).position
        if not (track_pos == nil) then
            local transformed = tf:transform_to(track_pos, _data.file)
            local dist = ut.calculate_dist(vx, vy, transformed.x, transformed.y)
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
function TrackAnnotation:remove_next_annotation(vx,vy)
    assert(vx)
    assert(vy)
    local next = self:find_annotation_next_to(vx,vy)
    if next then
        self:remove_annotation(next.id,_data.time)
    end
end
function TrackAnnotation:move_track(track, vx, vy)
    assert(vx)
    assert(vy)
    self:add_annotation(track.id,_data.time,vx,vy)
end
function TrackAnnotation:rotate_track(track, vx, vy)
    assert(vx)
    assert(vy)
    local position = (track:position(self.main.data('time'))).position
    local rad = self.main.data('tf'):rotation_from_points(position.x,position.y,vx,vy)
    -- rotate marked track
    self:add_annotation(track.id,_data.time,position.x,position.y,rad)
end
function TrackAnnotation:reset_end(annotation, time)
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
function TrackAnnotation:set_end(annotation, time, vx, vy)
    local changed = false
    local entry = annotation:position(time)
    local first, last = annotation:get_time_endpoints()
    if (entry.position) then
        if (entry.interpolated) then
            self:add_annotation(annotation.id, time, vx, vy)
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
function TrackAnnotation:toggle_end(track)
    if (track) then
        local time = self.main.data('time')
        if(self:reset_end(track, time)) then return true end
        if(self:set_end(track, time, vx, vy)) then return true end
    end
    return false
end
function TrackAnnotation:find_next_neighbour_annotation(time, track)
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
    for key, value in pairs(self.tracks) do
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
function TrackAnnotation:find_previous_neighbour_annotation(time, track)
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
    for key, value in pairs(self.tracks) do
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
function TrackAnnotation:mark_track(track)
    if (not self.marked_track) or (self.marked_track.id ~= track.id) then
        self.marked_track = track
        self.main.notify()
    end
end
function TrackAnnotation:select_or_move(vx,vy,event)
    if not self.marked_track then
        self.marked_track = self:find_annotation_next_to(vx,vy)
    else 
        self:move_track(self.marked_track, vx, vy)
        self.marked_track = nil
    end
    self.main.notify()
end
function TrackAnnotation:open_menu(vx, vy)
    self.main.open_menu(vx,vy,self.create_menu_actions(self,vx,vy))
end
function TrackAnnotation:menu_or_rotate(vx,vy,event)
    if not self.marked_track then
        self:open_menu(vx,vy)
    else 
        self:rotate_track(self.marked_track,vx,vy)
        self.marked_track = nil
        self.main.notify()
    end
end
function TrackAnnotation:deselect()
    self.marked_track = nil
    self.main.notify()
end
function TrackAnnotation:goto_next_annotation()
    local time = self.main.data('time')
    local min_delta = opts.jump_next_min_delta_ms
    local next = self:find_next_neighbour_annotation(time+min_delta, self.marked_track)
    if next and next.time then
        msg.info('now: '.. time .. ' goto next annotation: ' .. next.time)
        self.main.goto_track_position_ms(next.time)
    end
end
function TrackAnnotation:goto_previous_annotation()
    local time = self.main.data('time')
    local min_delta = opts.jump_next_min_delta_ms
    local previous = self:find_previous_neighbour_annotation(time-min_delta, self.marked_track)
    if previous and previous.time then
        msg.info('now: ' .. time .. ' goto previous annotation: ' .. previous.time)
        self.main.goto_track_position_ms(previous.time)
    end
end
function TrackAnnotation:move_track_delta(addx, addy, addr)
    if self.marked_track then
        local time = self.main.data('time')
        local p = self.marked_track:position(time)
        if p.position then
            local new_rad = nil
            if p.position.rad then
                new_rad = p.position.rad + addr
            elseif addr ~= 0 then
                new_rad = addr
            end
            self.marked_track:add_annotation(time, p.position.x+addx, p.position.y+addy, new_rad, p.position.frame_id)
            self.tracks_changed = true
            self.main.notify()
        end
    end
end
function TrackAnnotation:toggle_endpoint(track)
    self:toggle_end(track)
    self.main.notify()    
end
function TrackAnnotation:set_person_id(track_id, person_id)
    msg.info("setting track id '" .. track_id .. "' to person '" .. person_id .. "'")
    self.tracks[track_id].person_id = person_id
    self.tracks_changed = true
    self.main.notify()    
end
function TrackAnnotation:get_person_ids()
    local result = {}
    for id, track in pairs(self.tracks) do
        if track.person_id then
            result[track.person_id] = true
        end
    end
    return result
end
function TrackAnnotation:get_transformable()
    local result = {}
    for key, value in pairs(self.transformable) do
        result[key] = not (self.show_transformable[key] == nil)
    end
    return result
end
function TrackAnnotation:set_transformable(name, boolean)
    if (boolean == true) then
        self.show_transformable[name] = true
    else
        self.show_transformable[name] = nil
    end
    self.main.notify()    
end

function TrackAnnotation.create_actions(track)
    return {
        {type='mouse', event='Ctrl+MBTN_LEFT',  name='add_track',                callback=function(...) track:add_track(...) end},
        {type='mouse', event="Ctrl+MBTN_RIGHT", name="remove_next_annotation",   callback=function(...) track:remove_next_annotation(...) end},
        {type='mouse', event="MBTN_LEFT",       name="select_or_move",           callback=function(...) track:select_or_move(...) end},
        {type='mouse', event="MBTN_RIGHT",      name="menu_or_rotate",           callback=function(...) track:menu_or_rotate(...) end},
        {type='key',   event="Ctrl+s",          name="save",                     callback=function(...) track:save_annotations(...) end },
        {type='key',   event="ESC",             name="deselect",                 callback=function(...) track:deselect(...) end},
        {type='key',   event="END",             name="goto_next_annotation",     callback=function(...) track:goto_next_annotation(...) end,  options={repeatable=true}},
        {type='key',   event="HOME",            name="goto_previous_annotation", callback=function(...) track:goto_previous_annotation(...) end, options={repeatable=true}},
        {type='key',   event="Alt+UP",          name="move_up",                  callback=function(...) track:move_track_delta(0,-1,0) end, options={repeatable=true}},
        {type='key',   event="Alt+DOWN",        name="move_down",                callback=function(...) track:move_track_delta(0,1,0) end,  options={repeatable=true}},
        {type='key',   event="Alt+LEFT",        name="move_left",                callback=function(...) track:move_track_delta(-1,0,0) end, options={repeatable=true}},
        {type='key',   event="Alt+RIGHT",       name="move_right",               callback=function(...) track:move_track_delta(1,0,0) end,  options={repeatable=true}},
        {type='key',   event="Alt+q",           name="move_rotate_left",         callback=function(...) track:move_track_delta(0,0,-math.pi/64) end, options={repeatable=true}},
        {type='key',   event="Alt+e",           name="move_rotate_right",        callback=function(...) track:move_track_delta(0,0,math.pi/64) end,  options={repeatable=true}},
    }
end
local function name_dialog()
    local result = utils.subprocess({args={"zenity","--entry"}})
    return string.gsub(result.stdout, "\n", "")
end
function TrackAnnotation.create_menu_actions(track, vx, vy)
    local menu_list = { context_menu = {}}
    -- track interaction
    local next_track = track:find_annotation_next_to(vx,vy)
    if next_track then
        table.insert(menu_list.context_menu, {"command", "Mark track", "MBTN_RIGHT", function () track:mark_track(next_track) end, "", false, false})
        table.insert(menu_list.context_menu, {"command", "Toggle endpoint", "-", function () track:toggle_endpoint(next_track) end, "", false, false})
        table.insert(menu_list.context_menu, {"cascade", "Set Person Id", "person_id_menu", "", "", false})
        menu_list.person_id_menu = {}
        for name, ignored in pairs(track:get_person_ids()) do
            table.insert(menu_list.person_id_menu, {
                "command", name, "", 
                function() track:set_person_id(next_track.id, name) end, 
                "", (name == next_track.person_id)})
        end
        table.insert(menu_list.person_id_menu, {
            "command", "-- enter new name", "", 
            function() track:set_person_id(next_track.id, name_dialog()) end, 
            "", false})
    end

    -- visualizations
    local transformable = track:get_transformable()
    local first = true
    for name, active in ut.pairs_by_keys(transformable) do
        if first then
            table.insert(menu_list.context_menu, {"cascade", "Show other annotations", "show_transformable_menu", "", "", false})
            menu_list.show_transformable_menu = {}
            first = false
        end
        local set_transformable_and_update = function(handler, name, menu, position) 
            local activate = (menu[position][3] == "")
            track:set_transformable(name, activate)
            menu[position][2] = name
            if activate then
                menu[position][3] = "+"
            else
                menu[position][3] = ""
            end
        end
        local pos = #(menu_list.show_transformable_menu)
        table.insert(menu_list.show_transformable_menu, {
            "command", name, (active and "+" or ""), 
            function() set_transformable_and_update(handler, name, menu_list.show_transformable_menu, pos+1) end, 
            "", false, true})
    end

    -- show person tracks
    if track.show_persons then
        table.insert(menu_list.context_menu, {"command", "Hide persons", "", function () track.show_persons=false; track.main.notify() end, "", false, false})
    else
        table.insert(menu_list.context_menu, {"command", "Show persons", "", function () track.show_persons=true; track.main.notify() end, "", false, false})
    end
    return menu_list
end
return TrackAnnotation