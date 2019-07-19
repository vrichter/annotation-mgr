-- config
local opts = {
    position_size = 25,
    group_line_factor = 0.25,
    color_group           = '#ffffffaa',
    color_person_selected = '#ffffff33',
    color_single_person   = '#ffffff33',
    color_group_member    = '#377eb833',
    color_group_speaker   = '#e41a1c33',
    color_group_addressee = '#4daf4a33',
    color_border_selected = '#e41a133',
    color_border_default  = '#00000033',
}
(require 'mp.options').read_options(opts,"render-export-annotation")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'msg'
local dump = require 'dump'
local tr = require 'render-track-annotation'
local gr = require 'render-group-annotation'
local tf = require 'tf'

local RenderExportAnnotation = {}
function RenderExportAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.tr = tr:new()
    self.gr = gr:new()
    self.render_matches = true
    return o
end
function RenderExportAnnotation:render_person(ass,gui,person,name)
    local px, py = gui:video_to_px(person.x, person.y)
    self.tr:render_track_position(ass, px, py, person.rad, opts.position_size, {border=opts.color_border_default, primary=opts.color_single_person}, name, gui)
end
function RenderExportAnnotation:render_line(ass,gui,person_1,person_2)
    local px1, py1 = gui:video_to_px(person_1.x, person_1.y)
    local px2, py2 = gui:video_to_px(person_2.x, person_2.y)
    local color = {border=opts.color_border_default, primary=opts.color_group_addressee}
    ass:new_event()
    ass:append(gui:asstools_create_color_from_hex(color))
    ass:pos(0,0)
    ass:draw_start()
    ass:move_to(px1,py1)
    ass:line_to(px2,py2) 
    ass:draw_stop()
end
local function create_back_line(px,py,rad)
    if not rad then
        return {{ x = px, y = py }}
    else
        local result = {}
        table.insert(result,{x = px - opts.position_size * math.cos(rad-math.pi/2) * opts.group_line_factor, y = py - opts.position_size * math.sin(rad-math.pi/2) * opts.group_line_factor})
        table.insert(result,{x = px + opts.position_size * math.cos(rad-math.pi/2) * opts.group_line_factor, y = py + opts.position_size * math.sin(rad-math.pi/2) * opts.group_line_factor})
        return result
    end
end
function RenderExportAnnotation:render_group(ass,gui,person_ids,persons,matches)
    local color = {border=opts.color_border_default, primary=opts.color_group_member, al}
    local points = {}
    for k,v in pairs(person_ids) do
        local p = persons[k].person
        if matches then
            p = persons[k].match
        end
        local px, py = gui:video_to_px(p.x, p.y)
        local rad = p.rad
        for i,pos in pairs(create_back_line(px,py,rad)) do
            table.insert(points, pos)
        end
    end
    self.gr:render_group_polygon(ass,points,color,gui)
end
local function transform_position(person,tf,from_frame, to_frame)
    local track = {frame_id = from_frame, x = person[2], y = person[3], rad = person[4]}
    return tf:transform_to(track,to_frame)
end
function RenderExportAnnotation:draw_state_and_ssignment(model, time, ass, gui)
    local work_with_matches = self.render_matches
    local state = model.state
    local tf = model.tf
    local persons = model:find_persons(time)
    local matched_persons = model:match_tracks_to_persons(time, persons)
    local matched_groups = {}
    if work_with_matches then
        matched_groups = model:match_groups(time, matched_persons)
    else
        matched_groups = model:match_groups(time, persons)
    end
    local named_persons = {}
    local frame_ref = model:frame_id()
    local frame_id = model.main.data('file')
    for k,person in pairs(persons) do
        named_persons[person[1]] = { person=transform_position(person,tf,frame_ref,frame_id) }
    end
    for k,person in pairs(matched_persons) do
        named_persons[person[1]].match = transform_position(person,tf,frame_ref,frame_id)
    end
    for k,match in pairs(named_persons) do
        if not work_with_matches then
           self:render_person(ass,gui,match.person,k)
        elseif match.match then
            self:render_person(ass,gui,match.match,k)
        end
    --self:render_person(ass,gui,match.person,k)
        --if match.match then
        --    self:render_person(ass,gui,match.match,k)
        --    self:render_line(ass,gui,match.person,match.match)
        --end
    end
    for k, group in pairs(matched_groups) do
        self:render_group(ass,gui,group,named_persons,work_with_matches)
    end
    ass:draw_stop()
end
function RenderExportAnnotation:render(model, ass, gui)
    local time = model.main.data('time')
    local frame_id = model.main.data('file')
    local td = model.main.data('time_deltas'):get_time_delta("",frame_id) or 0
    if not time then return end
    self:draw_state_and_ssignment(model, time+td , ass, gui)
end
function RenderExportAnnotation:create_menu_actions(vx, vy)
    local actions = {context_menu = {}}
    if self.render_matches then
        table.insert(actions.context_menu,{"command", "Group from Annotations", "", function () self.render_matches = false end, "", false, false})
    else
        table.insert(actions.context_menu,{"command", "Group from Matches", "", function () self.render_matches = true end, "", false, false})
    end
    return actions
end
return RenderExportAnnotation