local opts = {
    annotation_name = "group-annotation.json",
    track_annotation_suffix = "-tracking-annotation.json",
    next_annotation_max_dist = 25,
    reference_time_frame = "",
    roles = {"member", "speaker", "addressee"}
}
(require 'mp.options').read_options(opts,"group-annotation")


local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local person = require 'person'
local Group = require 'group'
local Track = require 'track'
local render = require 'render-group-annotation'
local ut = require 'utils'

local GroupAnnotation = {}
function GroupAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.groups = {}
    self.groups_changed = false
    self.marked_person = nil
    self.persons = {}
    self.renderer = render:new()
    self.main = {}
    return o
end
--- interface
function GroupAnnotation:name()
    return 'group_annotation'
end
function GroupAnnotation:init(main)
    self.main = main
    self.actions = self.create_actions(self)
    self:after_file_change()
end
function GroupAnnotation:finish()
    self:save_annotations()
end
function GroupAnnotation:before_file_change()
    self:save_annotations()
end
function GroupAnnotation:after_file_change()
    self:load_annotations()
    self:load_persons()
    self.main.notify()
end
function GroupAnnotation:get_actions()
    return self.actions
end
function GroupAnnotation:render(ass, gui)
    self.renderer:render(self, ass, gui)
end
--- helper functions
function GroupAnnotation:save_annotations()
    if not self.groups_changed then
        msg.info("not saving unchanged annotation for")
        return
    end
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    local document = Group:serialize_groups(td:adapt_group_times(self.groups,current_frame,opts.reference_time_frame))
    if document == "[]" then
        msg.info("not saving empty annotation")
    else
        local dirname = self.main.data('dir')
        msg.info('saving annotation for dir:', dirname)
        self.main.save_json_to_file(dirname .. '/' .. opts.annotation_name, document)
    end
    self.groups_changed = false
end
function GroupAnnotation:load_annotations()
    assert(self.groups_changed == false)
    local dirname = self.main.data('dir')
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    msg.info('loading annotation for dir:', dirname)
    local groups = Group:deserialize_groups(self.main.read_string_from_file(dirname .. '/' .. opts.annotation_name))
    self.groups = td:adapt_group_times(groups, opts.reference_time_frame, current_frame)
end
function GroupAnnotation:load_persons()
    local persons = {}
    local tf = self.main.data('tf')
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    local current_dir = self.main.data('dir')
    local suffix = opts.track_annotation_suffix
    if tf:get(current_frame) then -- only when current file transformable
        for key, value in pairs(tf:get_all()) do
            local filename = current_dir .. '/' .. key .. suffix
            if self.main.check_file_exists(filename) then
                persons[key] = td:adapt_track_times(Track:deserialize_tracks(self.main.read_string_from_file(filename)), key, current_frame)
            end
        end
    end
    self.persons = person:create_from_tracks(persons, tf)
end

-- update model
function GroupAnnotation:find_person_next_to(vx,vy,time,max_dist,ignore)
    assert(vx)
    assert(vy)
    local time = time or self.main.data('time')
    local max_dist = max_dist or opts.next_annotation_max_dist
    assert(max_dist)
    local next = nil
    local min_dist = nil
    local time = self.main.data('time')
    local frame_id = self.main.data('file')
    for key, person in pairs(self.persons) do
        if (not ignore) or (ignore.person_id ~= person.person_id) then 
            local person_pos = (person:position(time, frame_id)).position
            if not (person_pos == nil) then
                local dist = ut.calculate_dist(vx, vy, person_pos.x, person_pos.y)
                if min_dist == nil or dist < min_dist then
                    min_dist = dist
                    next = person
                end
            end
        end
    end
    if next and max_dist and (min_dist >= max_dist) then
        return nil
    else
        return next
    end
end
function GroupAnnotation:remove_person_from_group(vx, vy)
    local time = self.main.data('time')
    local person = self.marked_person or self:find_person_next_to(vx, vy, time)
    if person then -- remove from evey group as a person can only be in one
        self:remove_person_from_all_groups(person.person_id)
    end
end
function GroupAnnotation:remove_person_from_all_groups(person_id)
    local time = self.main.data('time')
    local changed = false
    for k,v in pairs(self.groups) do
        if v:remove_person(time, person_id) then
            self:clean_up_group(v)
            changed = true
        end
    end
    if changed then
        self.groups_changed = true
        self.main.notify()
    else
    end
end
function GroupAnnotation:mark_person(person)
    if person ~= self.marked_person then
        self.marked_person = person
        self.main.notify()
    end
end
function GroupAnnotation:find_group_of(time, person)
    for k,v in pairs(self.groups) do
        if v:has_person(time, person.person_id) then
            return self.groups[k]
        end
    end
    return nil
end
function GroupAnnotation:find_or_create_group_of(time, person)
    if not person then return nil end
    local group = self:find_group_of(time, person)
    if not group then
        group = Group:new()
        group:add_person(time, person.person_id, opts.roles[1])
    end
    return group
end
function GroupAnnotation:clean_up_group(group)
    -- completely remove empty groups
    if group:is_empty() then
        msg.error('delete group',group.id, group:is_empty())
        self.groups[group.id] = nil
    end
end
function GroupAnnotation:move_person_to_group(time, group, person_id)
    if not group then return end 
    local removed = false
    for k,v in pairs(self.groups) do
        if (group.id ~= v.id) and v:has_person(time, person_id) then
            v:remove_person(time, person_id)
            self:clean_up_group(v)
            removed = true
        end
    end
    group:add_person(time,person_id,opts.roles[1])
    self.groups[group.id] = group
    self.groups_changed = true
    self.main.notify()
    if removed then
        mp.command('frame-step')
    end
    return removed
end
function GroupAnnotation:select_or_move_to_group(vx, vy)
    local time = self.main.data('time')
    if self.marked_person then
        local next_person = self:find_person_next_to(vx, vy, time, nil, self.marked_person)
        if next_person then
            local new_group = self:find_or_create_group_of(time, next_person)
            self:move_person_to_group(time, new_group, self.marked_person.person_id)
            self.marked_person = nil
        else
            self:remove_person_from_all_groups(self.marked_person.person_id)
            self.marked_person = nil
        end
    else 
        self.marked_person = self:find_person_next_to(vx, vy)
    end
    self.main.notify()
end
function GroupAnnotation:find_annotation(time, direction, group_id)
    if group_id then
        return self.groups[group_id]:find_neighbours(time+add)[direction]
    else
        local min_neighbour = nil
        for k,v in pairs(self.groups) do
            local neighbour = v:find_neighbours(time)[direction]
            if neighbour and neighbour.time_delta then
                if (not min_neighbour) or min_neighbour.time_delta > neighbour.time_delta then
                    min_neighbour = neighbour
                end
            end
        end
        return min_neighbour
    end
end
function GroupAnnotation:find_annotation_fuzzy(time, direction, group_id)
    local result = self:find_annotation(time, direction, group_id)
    if (not result) or (not result.time) or (result.time == time) then
        -- try again with a small time delta
        local add = 1
        if direction == 'previous' then add = add * -1 end
        result = self:find_annotation(time+add, direction, group_id)
    end
    return result
end
function GroupAnnotation:goto_annotation(direction)
    local time = self.main.data('time')
    local group_id = nil
    if self.marked_person then
        group_id = GroupAnnotation:find_group_of(time, self.marked_person)
    end
    local annotation = self:find_annotation_fuzzy(time, direction, group_id)
    if annotation and annotation.time then
        self.main.goto_track_position_ms(annotation.time)
    end
end
function GroupAnnotation:open_menu(vx, vy)
    self.main.open_menu(vx,vy,self.create_menu_actions(self,vx,vy))
end
function GroupAnnotation.create_actions(handler)
    return {
        {type='mouse', event="Ctrl+MBTN_RIGHT", name="remove_person_from_group", callback=function(...) handler:remove_person_from_group(...); mp.command('frame-step') end},
        {type='mouse', event="MBTN_LEFT",       name="select_or_move_to_group",  callback=function(...) handler:select_or_move_to_group(...) end},
        {type='mouse', event="MBTN_RIGHT",      name="menu",                     callback=function(...) handler:open_menu(...) end},
        {type='key',   event="Ctrl+s",          name="save",                     callback=function(...) handler:save_annotations(...) end },
        {type='key',   event="ESC",             name="deselect",                 callback=function(...) handler:mark_person(nil) end},
        {type='key',   event="END",             name="goto_next_annotation",     callback=function(...) handler:goto_annotation('next',...) end,  options={repeatable=true}},
        {type='key',   event="HOME",            name="goto_previous_annotation", callback=function(...) handler:goto_annotation('previous',...) end, options={repeatable=true}},
        --{type='key',   event="Alt+UP",          name="add_to_first_group",       callback=function(...) handler:add_to_group('first') end, options={repeatable=true}},
        --{type='key',   event="Alt+DOWN",        name="remove_from_group",        callback=function(...) handler:add_to_group() end,  options={repeatable=true}},
        --{type='key',   event="Alt+LEFT",        name="move_to_next_group",       callback=function(...) handler:add_to_group('next') end, options={repeatable=true}},
        --{type='key',   event="Alt+RIGHT",       name="move_to_previous_group",   callback=function(...) handler:add_to_group('previous') end,  options={repeatable=true}},
    }
end
function GroupAnnotation.create_menu_actions(handler, vx, vy)
    local menu_list = { context_menu = {}}
    -- handler interaction
    local next_person = handler:find_person_next_to(vx,vy)
    if next_person then
        table.insert(menu_list.context_menu, {"command", "Mark person", "MBTN_RIGHT", function () handler:mark_person(next_person) end, "", false, false})
    end
    if next_person then
        local time = handler.main.data('time')
        local group = handler:find_group_of(time, next_person)
        if group then
            local role = group:get_role(time, next_person.person_id)
            msg.error('role:',role)
            assert(role)
            table.insert(menu_list.context_menu, {"cascade", "Person Role", "role_menu", "", "", false})
            local role_menu = {}
            for k,v in pairs(opts.roles) do
                table.insert(role_menu, {"command", v, "", 
                    function () 
                        group:add_person(time, next_person.person_id, v)
                        handler.groups_changed = true
                        handler.main.notify() 
                    end, "", (role==v), false})
            end
            menu_list.role_menu = role_menu
        end
    end
    return menu_list
end
return GroupAnnotation