local dump = require "dump"
local msg = require 'msg'

local Utils = {}

function Utils.pairs_by_keys (t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end
function Utils.calculate_dist(ax,ay,bx,by)
    return math.sqrt(math.abs((bx-ax)^2-(by-ay)^2))
end
function Utils.len(data)
    if not data then return -1 end
    local len = 0
    for k,v in pairs(data) do
        len = len + 1
    end
    return len
end
-- thanks to https://gist.github.com/tylerneylon/81333721109155b2d244
function Utils.clone(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    
    -- New table; mark it as seen an copy recursively.
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[Utils.clone(k, s)] = Utils.clone(v, s) end
    return res
end

return Utils