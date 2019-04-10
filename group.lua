local Annotations = require "annotations"
local dump = require "dump"
local msg = require 'msg'
local utils = require 'mp.utils'
local uuid = require 'dependencies/uuid'
local json = require 'dependencies/json'
local ut = require 'utils'

local Group = {}
for k, v in pairs(Annotations) do
    Group[k] = v
end
uuid.randomseed(os.time()+os.clock()*1000000)
function Group:new(o)
    o = o or Annotations:new(o)
    setmetatable(o, self)
    self.__index = self
    o.id = uuid.new()
    return o
end
function Group:add_person(time,person_id)
    assert(time)
    assert(person_id)
    local group = self:get_persons(time)
    local new_group = {}
    if group and group.annotation then
        for k,v in pairs(group.annotation) do
            new_group[k]=v
        end
    end
    new_group[person_id] = "member"
    self:set_group(time, new_group)
end
function Group:set_group(time, group)
    if not group or not next(group) then -- remove
        Group.remove(self,time)
    else -- new point
        Group.add(self,time,group)
    end
    self:clean_entries()
    self:update_endpoints()
end
function Group:remove_person(time, person_id)
    assert(time)
    assert(person_id)
    local group = self:get_persons(time)
    if not group then
        msg.error('cannot remove person',person_id,'at time',time,': out of bounds [',self.start_time,', ',self.end_time,']')
        return false
    end
    local group = group.annotation
    if group[person_id] ~= nil then
        local new_group = {} -- need a copy
        local members = 0
        for k,v in pairs(group) do
            if k ~= person_id then
                new_group[k] = v
                members = members + 1
            end
        end
        self:set_group(time,new_group)
        return true
    else
        return false
    end
end
function Group:has_person(time, person_id)
    assert(time)
    assert(person_id)
    local group = self:get_persons(time)
    if group and group.annotation then
        return group.annotation[person_id]
    else
        return nil
    end
end
function Group:get_persons(time)
    assert(time)
    if (self.start_time and time < self.start_time) or (self.end_time and time > self.end_time) then return nil end
    local result = self:find_neighbours(time)
    local annotation = nil
    if result.previous and result.previous.annotation then
        annotation = result.previous
    end
    if result.next and result.next.annotation then
        if (not annotation) or (result.next == time) then
            annotation = result.next
        end
    end
    if annotation then 
        return annotation
    else
        return {}
    end
end
function Group:is_empty()
    for k,v in pairs(self.data) do
        if ut.len(v) > 1 then
            return false
        end
    end
    return true
end
function Group:update_endpoints()
    local min = nil
    local max = nil
    for k,v in pairs(self.data) do
        if (not min) or (k <= min) then 
            min = k
        end
        if (not max) or (k >= max) then
            max = k
        end
    end
    if min then
        self.start_time = min
    else
        self.start_time = nil
    end
    if max and ut.len(self.data[max]) < 2 then
        self.end_time = max
    else
        self.end_time = nil
    end
end
function Group:serialize(do_not_encode)
    local annotations = {}
    for key, value in pairs(self.data) do
        table.insert(annotations, {time = key, persons = value})
    end
    local data = {}
    if annotations[1] then -- only create annotation when it contains data
        data = {
            id = self.id, 
            start_time = self.start_time,
            end_time = self.end_time,
            annotations = annotations
        }
    end
    if do_not_encode then return data else return Group.pretty_encode_group(data) end
end
function Group:serialize_groups(groups, do_not_encode)
    local data = {}
    for key, value in pairs(groups) do
        table.insert(data,value:serialize(true))
    end
    if do_not_encode then return data else return Group.pretty_encode_groups(data) end
end
local function json_element(name, value)
    local result = '"'..name..'": '
    if type(value) == 'string' then
        result = result .. '"' .. value .. '"'
    else
        result = result .. value
    end
    return result
end
local function if_exists(name, data, prefix, suffix)
    if data[name] then
        return prefix .. json_element(name, data[name]) .. suffix
    else
        return ""
    end
end
function Group.pretty_encode_persons(persons)
    local result = '"persons": [ '
    for name,role in pairs(persons) do
        result = result .. '{ ' .. json_element('person_id', name) .. ', ' .. json_element('role',role) .. '}, '
    end
    return string.gsub(result, ', $', ' ]')
end
function Group.pretty_encode_annotation(annotation)
    return '{ ' .. json_element('time', annotation.time) .. ', ' .. Group.pretty_encode_persons(annotation.persons) .. ' }'
end
function Group.pretty_encode_annotations(annotations, indent)
    local result = '['
    for k,v in pairs(annotations) do
        result = result .. '\n' .. indent .. Group.pretty_encode_annotation(v) .. ','
    end
    result = string.gsub(result, ',$', '\n') .. indent .. ']'
    return result
end
function Group.pretty_encode_group(group, indent)
    local indent = indent or '    '
    local result = '{\n' .. 
        if_exists('id', group, indent, ',\n') ..
        if_exists('start_time', group, indent, ',\n') ..
        if_exists('end_time', group, indent, ',\n') ..
        indent .. '"annotations": ' .. Group.pretty_encode_annotations(group.annotations, indent..'    ') .. 
        '\n'..indent..'}'
    return result
end
function Group.pretty_encode_groups(groups, indent)
    local indent = indent or '    '
    local result = '['
    for k,v in pairs(groups) do
        result = result .. '\n' .. indent .. Group.pretty_encode_group(v,indent..'    ') .. ','
    end
    result = string.gsub(result, ',$', '\n') .. indent .. ']'
    return result
   
end
function Group:deserialize_groups(data)
    result = {}
    if not data then return result end
    parsed = utils.parse_json(data)
    if not parsed then msg.error("could not parse as json: ", data); return result; end
    for key, parsed_group in pairs(parsed) do
        if not parsed_group.annotations then 
            msg.warn("skipping parsed group. does not contatin anntation: ", dump_pp(parsed_group))
        elseif not parsed_group.id then
            msg.warn("skipping parsed group. does not contatin id: ", dump_pp(parsed_group))
        else
            local group = Group:new()
            group.id = parsed_group.id
            group.start_time = parsed_group.start_time
            group.end_time = parsed_group.end_time
            msg.error(dump_pp(parsed_group))
            for key, parsed_annotation in pairs(parsed_group.annotations) do
                local annotation = {}
                for k,member in pairs(parsed_annotation.persons) do 
                    annotation[member.person_id] = member.role
                end
                group:set_group(parsed_annotation.time, annotation)
            end
            result[group.id] = group
        end
    end
    return result
end

return Group