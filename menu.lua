local dump = require "dump"
local msg = require "msg"
local engine = require "dependencies/mpvcontextmenu/menu-engine"
local mp = require 'mp'
local utils = require 'mp.utils'

local Menu = {}
function Menu:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.menu_list = { context_menu = {} }
    return o
end
local function add_menu(menu, add)
    local first_elem = true
    for k,v in pairs(add) do
        if type(k) == 'number' then
            if first_elem and menu[1] then 
                table.insert(menu,{'separator'})
            end
            first_elem = false
            table.insert(menu,v)
        elseif menu[k] then
            add_menu(menu[k],v)
        else
            menu[k] = v
        end
    end
end
function Menu:append(menu)
    add_menu(self.menu_list, menu)
end
function Menu:menu_action(vx, vy)
    engine.createMenu(self.menu_list, 'context_menu', -1, -1, 'tk')
end

return Menu