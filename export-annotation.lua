local opts = {
    start_time = 0,
    time_step = 1000/15,
    reference_time_frame = "",
    target_time_frame = "",
    reference_coordinate_frame = "Home",
    track_annotation_suffix = "-tracking-annotation.json",
    group_annotation_name = "group-annotation.json",
}
(require 'mp.options').read_options(opts,"export-annotation")

local Track = require "track"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local person = require 'person'
local Group = require 'group'
local ut = require 'utils'
local json = require 'dependencies/json'

local ExportAnnotation = {}
function ExportAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.tracks = {}
    self.transformable = {}
    self.show_transformable = {}
    self.persons = {}
    self.groups = {}
    self.main = {}
    return o
end
--- interface
function ExportAnnotation:name()
    return 'export_annotation'
end
function ExportAnnotation:init(main)
    self.main = main
    self.actions = {}
    self.persons = nil
    self.groups = nil
    self.timestamps = {}
    self.features = {}
    self.GTgroups = {}
    self.current_dir = ""
    self:after_file_change()
end
function ExportAnnotation:finish()
end
function ExportAnnotation:before_file_change()
end
function ExportAnnotation:after_file_change()
    if self.main.data('dir') ~= self.current_dir then
        self.current_dir = self.main.data('dir')
        self:load_annotations()
        self:create_annotations()
        self:dump_annotations()
    end
end
function ExportAnnotation:get_actions()
    return self.actions
end
function ExportAnnotation:render(ass, gui)
    gui.render_text_only("Probably writing data.")
end
--- helper functions
function ExportAnnotation:load_annotations()
    --- groups
    local current_dir = self.main.data('dir')
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    msg.info('loading annotation for dir:', current_dir)
    local groups = Group:deserialize_groups(self.main.read_string_from_file(current_dir .. '/' .. opts.group_annotation_name))
    self.groups = td:adapt_group_times(groups, opts.reference_time_frame, opts.target_time_frame)
    --- persons
    local persons = {}
    local tf = self.main.data('tf')
    local suffix = opts.track_annotation_suffix
    for key, value in pairs(tf:get_all()) do
        local filename = current_dir .. '/' .. key .. suffix
        if self.main.check_file_exists(filename) then
            persons[key] = td:adapt_track_times(Track:deserialize_tracks(self.main.read_string_from_file(filename)), key, opts.target_time_frame)
        end
    end
    self.persons = person:create_from_tracks(persons, tf)
end
local function calculate_end_time(persons)
    local time_end = nil
    for pid, person in pairs(persons) do
        for tid, track in pairs(person.tracks) do
            if not time_end then
                time_end = track.end_time
            elseif track.end_time and (track.end_time > time_end) then
                time_end = track.end_time
            end
        end
    end
    return time_end
end
function ExportAnnotation:create_annotations()
    local time_start = opts.start_time
    local time_end = calculate_end_time(self.persons)
    local time_step = opts.time_step
    local time = time_start
    while time < time_end do
        local persons = {}
        for id, person in pairs(self.persons) do
            local position = person:position(time, opts.reference_coordinate_frame).position
            if position then
                table.insert(persons, {[1]=person.person_id, [2]=position.x, [3]=position.y, [4]=position.rad} )
            end
        end
        local groups = {}
        for id, group in pairs(self.groups) do 
            local persons = group:get_persons(time)
            if persons and (persons.annotation) then
                local list = {}
                for name, role in pairs(persons.annotation) do
                    table.insert(list,name)
                end
                table.insert(groups,list)
            end
        end
        table.insert(self.timestamps, time)
        table.insert(self.features, persons)
        table.insert(self.GTgroups, groups)
        time = time + time_step
    end
end
function ExportAnnotation:dump_annotations()
    local write_out = {}
    write_out.features = json.encode({features = self.features, timestamp = self.timestamps})
    write_out.groundtruth = json.encode({GTgroups = self.GTgroups, GTtimestamp = self.timestamps})
    for k,v in pairs(write_out) do
        local file = assert(io.open(self.main.data('dir').."/"..k..".json", 'w'))
        file:write(v)
        file:close()
    end
end
return ExportAnnotation