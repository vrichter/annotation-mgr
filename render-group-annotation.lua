-- config
local opts = {
    position_size = 50,
    group_line_factor = 0.25,
    color_group = '#ffff33',
    color_person_selected = '#8f262666',
    color_single_person = '#ffffff',
    color_group_member = '#5b268f66',
    color_border_default = '#000000',
    alpha_group = '{\\alpha&H80&}',
}
(require 'mp.options').read_options(opts,"render-groups")

local mp = require 'mp'
local assdraw = require 'mp.assdraw'
local utils = require 'mp.utils'
local msg = require 'msg'
local dump = require 'dump'
local tr = require 'render-track-annotation'
local tf = require 'tf'

local RenderGroupAnnotation = {}
function RenderGroupAnnotation:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.tr = tr:new()
    return o
end
local function mean_point(points)
    local x = 0
    local y = 0
    local c = 0
    for k,v in pairs(points) do
        x = x + v.x
        y = y + v.y
        c = c + 1
    end
    return {x = x/c, y = y/c}
end
local function sort_points(points)
    local center = mean_point(points)
    local tf = tf:new()
    table.sort(points, 
        function(a,b)
            return tf:rotation_from_points(center.x,center.y,a.x,a.y) < tf:rotation_from_points(center.x,center.y,b.x,b.y)
        end
    )
    return points
end
function RenderGroupAnnotation:render_group_polygon(ass, points, color, gui)
    if not points[2] then return end -- need at least two points for a polygon
    ass:new_event()
    ass:append(gui:asstools_create_color_from_hex(color))
    ass:append(opts.alpha_group)
    ass:pos(0,0)
    ass:draw_start()
    local first = true
    for i,point in pairs(sort_points(points)) do
        if first then
            ass:move_to(point.x,point.y)
            first = false
        else
            ass:line_to(point.x,point.y) 
        end
    end
    ass:draw_stop()
end
function RenderGroupAnnotation:get_group_member_positions(time, group, persons, frame_id)
    local positions = {}
    local members = group:get_persons(time)
    if members and members.annotation then
        for k,v in pairs(members.annotation) do
            table.insert(positions, {person = persons[k], position = persons[k]:position(time, frame_id).position, type=v})
        end
    end
    return positions
end
local function get_color_from_type(type, marked)
    if marked then
        return { primary = opts.color_person_selected, border = opts.color_border_default }
    elseif type == 'nongroup' then
        return { primary = opts.color_single_person, border = opts.color_border_default }
    elseif type == 'member' then
        return { primary = opts.color_group_member, border = opts.color_border_default }
    else
        assert(false)
    end
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
function RenderGroupAnnotation:render_track_position(ass, position, color, id, gui)
    local size = gui:video_to_px_scale(opts.position_size)/2
    if position.position then
        local px, py = gui:video_to_px(position.position.x, position.position.y)
        self.tr:render_track_position(ass, px, py, position.position.rad, size, color, id, gui)
        return create_back_line(px, py, position.position.rad)
    else
        return {{ x = 0, y = 0 }}
    end
end
function RenderGroupAnnotation:draw_group(ass, group, time, persons, frame_id, marked, gui)
    local positions = self:get_group_member_positions(time, group, persons, frame_id)
    local color = opts.color_group
    local members = {}
    local points = {}
    local track_renderer = tr:new()
    for k, position in pairs(positions) do
        local person_color = get_color_from_type(position.type, (marked and (marked.person_id == position.person.person_id)))
        local person_points = self:render_track_position(ass, position, person_color,position.person.person_id, gui)
        for i,p in pairs(person_points) do
            table.insert(points,p)
        end
        table.insert(members,position.person.person_id)
    end
    self:render_group_polygon(ass, points, color, gui)    
    return members
end
function RenderGroupAnnotation:draw_groups(group, time, ass, gui)
    local persons = group.persons
    local marked = group.marked_person
    local frame_id = group.main.data('file')
    local rendered_persons = {}
    for k, group in pairs(group.groups) do
        local members = self:draw_group(ass, group, time, persons, frame_id, marked, gui)
        for l, id in pairs(members) do
            rendered_persons[id] = true
        end
    end
    local track_renderer = tr:new()
    for k, person in pairs(persons) do
        if not rendered_persons[person.person_id] then -- render remaining persons
            local position = person:position(time, frame_id)
            if position and position.position then
                self:render_track_position(ass, position, get_color_from_type('nongroup', (marked and (person.person_id == marked.person_id))), person.person_id, gui)
            end
        end
    end
    ass:draw_stop()
end
function RenderGroupAnnotation:render(group, ass, gui)
    local time = group.main.data('time')
    if not time then return end
    self:draw_groups(group, time, ass, gui)
end

return RenderGroupAnnotation