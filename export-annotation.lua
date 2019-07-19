local opts = {
    start_time = 0,
    end_time = 0,
    time_step = 1000/15,
    reference_time_frame = "",
    target_time_frame = "",
    reference_coordinate_frame = "Home",
    track_annotation_suffix = "-tracking-annotation.json",
    group_annotation_name = "group-annotation.json",
    assignment_cost_factor = 100, -- use distance in cm instead of m for costs because munkres works with intergers
    assignment_cutoff_cost = 50*50, -- distance in cm squared
    assignment_cost_max = 50000, -- set to max when over cutoff
    auto_export="false",
    num_threads = 8,
    ffm_config_alg = "grow",
    ffm_config_mdl = 5000,
    ffm_config_stride = 40,
    xfactor = 100,
    yfactor = 100,
    role_export_agents = {
        flobi_entrance = true, 
        flobi_assistance = true,
    },
    match_person_ignore = {
        flobi_assistance = {
            0.44039871145942,
            2.808521980116,
            -0.78241969261972
        },
        flobi_entrance = {
            2.4838969458636,
            0.44503089333403,
            0.014353081273802
        }
    }
}
(require 'mp.options').read_options(opts,"export")

local Track = require "track"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local person = require 'person'
local Group = require 'group'
local ut = require 'utils'
local json = require 'dependencies/json'
local munkres = require 'dependencies/munkres/init'
local render = require 'render-export-annotation'
local ffm = require 'ffm'

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
    self.state = ""
    self.renderer = render:new()
    self.threads = {}
    msg.info("ffm_config is: ",opts.ffm_config)
    self.ffm = ffm:new(opts.ffm_config_alg,opts.ffm_config_mdl,opts.ffm_config_stride)
    return o
end
--- interface
function ExportAnnotation:name()
    return 'export_annotation'
end
function ExportAnnotation:init(main)
    self.main = main
    self.actions = self.create_actions(self)
    self.persons = nil
    self.groups = nil
    self.annotations_created = false
    self.timestamps = {}
    self.features = {}
    self.GTgroups = {}
    self.matched_features = {}
    self.role_annotations = {}
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
        if opts.auto_export ~= "false" then
            self:create_annotations()
            self:dump_annotations()
            self:dump_role_annotations()
            self.main.exit()
        end
    end
end
function ExportAnnotation:get_actions()
    return self.actions
end
function ExportAnnotation:render(ass, gui)
    self.renderer:render(self, ass, gui)
end
--- helper functions
function ExportAnnotation:frame_id()
    return opts.reference_coordinate_frame
end
local function collect_non_named_tracks(frames, persons, tf)
    local non_person_tracks = {}
    for frame_id,tracks in pairs(frames) do
        for i,track in pairs(tracks) do
            if not track.person_id then
                table.insert(non_person_tracks,track)
            end
        end
    end
    return non_person_tracks
end
function ExportAnnotation:load_annotations()
    --- groups
    local current_dir = self.main.data('dir')
    local td = self.main.data('time_deltas')
    local current_frame = self.main.data('file')
    msg.info('loading annotation for dir:', current_dir)
    local groups = Group:deserialize_groups(self.main.read_string_from_file(current_dir .. '/' .. opts.group_annotation_name))
    self.groups = td:adapt_group_times(groups, opts.reference_time_frame, opts.target_time_frame)
    --- tracks
    local tracks = {}
    local tf = self.main.data('tf')
    local suffix = opts.track_annotation_suffix
    for key, value in pairs(tf:get_all()) do
        local filename = current_dir .. '/' .. key .. suffix
        if self.main.check_file_exists(filename) then
            tracks[key] = td:adapt_track_times(Track:deserialize_tracks(self.main.read_string_from_file(filename)), key, opts.target_time_frame)
        end
    end
    self.persons = person:create_from_tracks(tracks, tf)
    self.tracks = collect_non_named_tracks(tracks, persons, tf)
    self.tf = tf
end
-- squared error
local function calculate_assignment_cost(position, person, cutoff, max_cost)
    local x1 = person[2] * opts.assignment_cost_factor
    local y1 = person[3] * opts.assignment_cost_factor
    local x2 = position["x"] * opts.assignment_cost_factor
    local y2 = position["y"] * opts.assignment_cost_factor
    local cost = (x2-x1)*(x2-x1)+(y2-y1)*(y2-y1)
    if cost < cutoff then
        return cost
    else
        return max_cost
    end
end
local function find_best_matches(positions, persons)
    --msg.error("positions",dump_pp(positions))
    --msg.error("persons",dump_pp(persons))
    local cost_matrix = {}
    for k,i in pairs(positions) do
        local row = {}
        for l,j in pairs(persons) do
            table.insert(row,calculate_assignment_cost(i,j,opts.assignment_cutoff_cost,opts.assignment_cost_max))
        end
        table.insert(cost_matrix,row)
    end
    --msg.error("cost_matrix",dump_pp(cost_matrix))
    local match = munkres.minimize_weights(cost_matrix)
    --msg.error("assignment",dump_pp(match))
    matches = {}
    for k,v in pairs(match.assignment_map) do
        if cost_matrix[k] ~= nil then
            local cost = cost_matrix[k][v] 
            if (cost ~= nil) and (cost < opts.assignment_cost_max) then
                matches[persons[v][1]] = positions[k]
            end
        end
    end
    --msg.error("matches",dump_pp(matches),match["total_cost"])
    return matches
end
function ExportAnnotation:match_tracks_to_persons(timestamp, persons)
    local tf = self.tf
    local tracks = self.tracks
    local frame_position_map = {}
    -- create a set of persons without ignored
    local persons_filtered = {}
    for k,v in pairs(persons) do
        if opts.match_person_ignore[v[1]] == nil then
            table.insert(persons_filtered,v)
        end
    end
    -- first get all positions at timestamp and sort them according to frame
    for id,track in pairs(tracks) do
        local position = track:position(timestamp).position
        if position and position.frame_id then
            if not frame_position_map[position.frame_id] then
                frame_position_map[position.frame_id] = {position}
            else
                table.insert(frame_position_map[position.frame_id],position)
            end
        end
    end
    -- find best matching person for each position in each frame
    local person_matches = {}
    for frame, positions_f in pairs(frame_position_map) do
        local positions = {}
        for id, position_f in pairs(positions_f) do
            table.insert(positions,tf:transform_to(position_f, opts.reference_coordinate_frame))
        end
        for id, position in pairs(find_best_matches(positions, persons_filtered)) do
            if person_matches[id] then
                table.insert(person_matches[id],position)
            else
                person_matches[id] = {position}
            end
        end
    end
    for k,v in pairs(opts.match_person_ignore) do
        person_matches[k] = {{x=v[1], y=v[2], rad=v[3],frame_id=opts.reference_coordinate_frame}}
    end
    -- calculate mean postition for each person over all frames
    result = {}
    -- {{[1]=person_id, [2]=position.x, [3]=position.y, [4]=position.rad}}
    for id, positions in pairs(person_matches) do
        local pos = person.calculate_mean_position(positions)
        table.insert(result,
        {
            [1]=id,
            [2]=pos.x,
            [3]=pos.y,
            [4]=pos.rad
        })
    end
    return result
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
function ExportAnnotation:find_persons(time)
    local persons = {}
    for id, person in pairs(self.persons) do
        local position = person:position(time, opts.reference_coordinate_frame).position
        if position then
            table.insert(persons, {[1]=person.person_id, [2]=position.x, [3]=position.y, [4]=position.rad} )
        end
    end
    return persons
end
function ExportAnnotation:find_groups(time)
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
    return groups
end
function ExportAnnotation:match_groups(time, persons)
    local observation = { time = time, persons = {} }
    for k,v in pairs(persons) do
        table.insert(observation.persons,{id=v[1],x=v[2]*opts.xfactor,y=v[3]*opts.yfactor,rad=v[4]})
    end
    return self.ffm:detect(observation)
end
local function scale_positions(persons, xfac, yfac)
    local xf = xfac or 1
    local yf = yfac or 1
    if xf == 1 and yf == 1 then
        return persons
    else
        local scaled = {}
        for i,p in pairs(persons) do
            scaled[i] = {[1]=p[1], [2]=p[2]*xf, [3]=p[3]*yf, [4]=p[4]}
        end
        return scaled
    end
end
local function find_group(time, agent, groups)
    for k,v in pairs(groups) do
        if v:has_person(time,agent) then
            return v
        end
    end
    return nil
end
local function create_role_data(time, agent, data, groups, persons)
    local result = {}
    local group = find_group(time, agent, groups) or Group:new()
    result[agent..'.role.agent'] = group:get_role(time,agent) or 'NA'
    for k,v in pairs(persons) do
        if k ~= agent then
            result[agent..'.role.'..k] = group:get_role(time,k) or 'NA'
        end
    end
    return result
end
local function create_person_data(person_ids,scaled_persons,scaled_matched_persons)
    local find = function(id,persons) 
        for k,v in pairs(persons) do
            if id==v[1] then
                return v
            end
        end
        return nil
    end
    result = {}
    for k,v in pairs(person_ids) do
        local p = find(k,scaled_persons)
        if p then
            result["position."..k..".x"] = p[2]
            result["position."..k..".y"] = p[3]
            result["position."..k..".r"] = p[4] or 'NA'
        else
            result["position."..k..".x"] = 'NA'
            result["position."..k..".y"] = 'NA'
            result["position."..k..".r"] = 'NA'
        end
        p = find(k,scaled_matched_persons)
        if p then
            result["mposition."..k..".x"] = p[2]
            result["mposition."..k..".y"] = p[3]
            result["mposition."..k..".r"] = p[4] or 'NA'
        else
            result["mposition."..k..".x"] = 'NA'
            result["mposition."..k..".y"] = 'NA'
            result["mposition."..k..".r"] = 'NA'
        end

    end
    return result
end
local function append_all(t, data)
    for k,v in pairs(data) do
        if not t[k] then
            t[k] = {}
        end
        table.insert(t[k],v)
    end
end
function ExportAnnotation:create_annotations()
    local time_start = opts.start_time or 0
    local time_end = opts.end_time
    if time_end <= time_start then
        msg.info("Overriding end-time as it is smaller than start-time")
        time_end = calculate_end_time(self.persons)
    end
    if not time_end then return end
    local time_step = opts.time_step
    local time = time_start
    msg.info("Generating observations: between",time_start,"and",time_end,"every",time_step)
    local person_ids = {}
    for k,v in pairs(self.persons) do
        if v.person_id then
            person_ids[v.person_id] = true
        end
    end
    local counter = 0 
    while time < time_end do
        counter = counter+1
        if (counter % 100) == 0 then
            msg.info("processed",counter,"timestamps. time =",time,"of",time_end,"(",(time-time_start)/(time_end-time_start)*100,"%)")
        end
        table.insert(self.timestamps, time)
        local persons = self:find_persons(time)
        local scaled_persons = scale_positions(persons,opts.xfactor,opts.yfactor)
        table.insert(self.features, scaled_persons)
        local groups = self:find_groups(time)
        table.insert(self.GTgroups, groups)
        local matched_persons = self:match_tracks_to_persons(time, persons)
        local scaled_matched_persons = scale_positions(matched_persons,opts.xfactor,opts.yfactor)
        table.insert(self.matched_features, scaled_matched_persons)
        time = time + time_step
        --- roles
        append_all(self.role_annotations, { ["time"] = time } )
        append_all(self.role_annotations, create_person_data(person_ids,scaled_persons,scaled_matched_persons))
        for k,v in pairs(opts.role_export_agents) do
            append_all(self.role_annotations, create_role_data(time,k,role_data,self.groups,person_ids))
        end
    end
    self.annotations_created = true
end
function ExportAnnotation:dump_annotations()
    local write_out = {}
    write_out.features = json.encode({features = self.features, timestamp = self.timestamps})
    write_out.features2 = json.encode({features = self.matched_features, timestamp = self.timestamps})
    write_out.groundtruth = json.encode({GTgroups = self.GTgroups, GTtimestamp = self.timestamps})
    for k,v in pairs(write_out) do
        local file = assert(io.open(self.main.data('dir').."/"..k..".json", 'w'))
        file:write(v)
        file:close()
    end
end
function ExportAnnotation:dump_role_annotations()
    msg.info("Dumping role annotations into file role_data.tsv")
    file = assert(io.open(self.main.data('dir').."/role_data.tsv", 'w'))
    local print_header = function(data)
        for k, v in pairs(data) do
            file:write(tostring(k)..'\t')
        end
        file:write('\n')
    end
    local print_line = function(data,i)
        for k, v in pairs(data) do
            file:write(tostring(v[i])..'\t')
        end
        file:write('\n')
    end
    if self.annotations_created == false then
        self:create_annotations()
    end
    print_header(self.role_annotations)
    local i = 1
    while self.role_annotations.time[i] do
        print_line(self.role_annotations,i)
        i=i+1
    end
    file:close()
    msg.info("Data completely written.")
end
function ExportAnnotation:open_menu(vx, vy)
    self.main.open_menu(vx,vy,self:create_menu_actions(vx,vy))
end
function ExportAnnotation.create_actions(handler)
    return {
        {
            type='mouse',
            event="MBTN_RIGHT",
            name="menu",
            callback=function(...) handler:open_menu(...) end
        },
        {
            type='key',
            event="Alt+UP",
            name="mdl_up",
            callback=function(...) handler.ffm:inc_mdl(); handler.main:notify() end, 
            options={repeatable=true}
        },
        {
            type='key',
            event="Alt+DOWN",
            name="mdl_down",
            callback=function(...) handler.ffm:dec_mdl(); handler.main:notify() end, 
            options={repeatable=true}
        },
        {
            type='key',
            event="Alt+RIGHT",
            name="stride_up",
            callback=function(...) handler.ffm:inc_stride(); handler.main:notify() end, 
            options={repeatable=true}
        },
        {
            type='key',
            event="Alt+LEFT",
            name="stride_down",
            callback=function(...) handler.ffm:dec_stride(); handler.main:notify() end, 
            options={repeatable=true}
        },
        {
            type='key',
            event="Alt+a",
            name="next_alg",
            callback=function(...) handler.ffm:inc_alg(); handler.main:notify() end, 
            options={repeatable=true}
        },
    }
end
function ExportAnnotation:create_menu_actions(vx, vy)
    local actions = {}
    if self.renderer.create_menu_actions then
        actions = self.renderer:create_menu_actions(vx,vy)
    end
    table.insert(actions.context_menu,{"command", "Export Role Annotations", "", function () self:dump_role_annotations() end, "", false, false})
    return actions
end

return ExportAnnotation