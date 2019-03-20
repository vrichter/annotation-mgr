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
    return o
end
local function generate_playlist_entries()
    local result = {}
    local playlist = mp.get_property_native('playlist')
    for key, playlist_entry in pairs(playlist) do
        table.insert(result, { 
            "command", playlist_entry.filename, "", 
            function() mp.set_property_number("playlist-pos",key-1) end, "", not (playlist_entry.current == nil)})
    end
    return result
end
local function pairsByKeys (t, f)
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
function Menu:menu_action(handler, vx, vy)
    menu_list = {
        context_menu = {
            {"cascade", "Play", "play_menu", "", "", false},
        },

        play_menu = {
            {"command", "Play/Pause", "Space", "cycle pause", "", false},
            {"command", "Stop", "Ctrl+Space", "stop", "", false},
            {"separator"},
            {"command", "Previous", "<", "playlist-prev", "", false},
            {"command", "Next", ">", "playlist-next", "", false},
            {"cascade", "Playlist", "playlist", "", "", false},
        },
        playlist = generate_playlist_entries()
    }

    -- track interaction
    local next_track = handler.find_annotation_next_to(vx,vy)
    if next_track then
        table.insert(menu_list.context_menu, {"command", "Mark track", "MBTN_RIGHT", function () handler.mark_track(next_track) end, "", false, false})
        table.insert(menu_list.context_menu, {"command", "Toggle endpoint", "ESC", function () handler.toggle_endpoint(next_track) end, "", false, false})
        table.insert(menu_list.context_menu, {"cascade", "Set Person Id", "person_id_menu", "", "", false})
        menu_list.person_id_menu = {}
        for name, ignored in pairs(handler.get_person_ids()) do
            table.insert(menu_list.person_id_menu, {
                "command", name, "", 
                function() handler.set_person_id(next_track.id, name) end, 
                "", (name == next_track.person_id)})
        end
        table.insert(menu_list.person_id_menu, {
            "command", "-- enter new name", "", 
            function() handler.set_person_id(next_track.id, self.name_dialog()) end, 
            "", false})
    end

    -- visualizations
    local transformable = handler.get_transformable()
    local first = true
    for name, active in pairsByKeys(transformable) do
        if first then
            table.insert(menu_list.context_menu, {"cascade", "Show other annotations", "show_transformable_menu", "", "", false})
            menu_list.show_transformable_menu = {}
            first = false
        end
        local set_transformable_and_update = function(handler, name, menu, position) 
            local activate = (menu[position][3] == "")
            handler.set_transformable(name, activate)
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
    if handler.show_persons() then
        table.insert(menu_list.context_menu, {"command", "Hide persons", "", function () handler.set_show_persons(false) end, "", false, false})
    else
        table.insert(menu_list.context_menu, {"command", "Show persons", "", function () handler.set_show_persons(true) end, "", false, false})
    end


    -- setting fix points in map
    table.insert(menu_list.context_menu, {"cascade", "Fix point", "fixpoint_menu", "", "", false})
    menu_list.fixpoint_menu = {
        {"command", "Add fix point", "",
        function () handler.add_fixpoint(vx, vy, self.name_dialog()) end,
        "", false},
        {"command", "Remove fix point", "",
        function () handler.remove_fixpoint(vx, vy) end,
        "", false}
    }
    

    -- create menu
    engine.createMenu(menu_list, 'context_menu', -1, -1, 'tk')
end
function Menu:name_dialog()
    local result = utils.subprocess({args={"zenity","--entry"}})
    return string.gsub(result.stdout, "\n", "")
end

return Menu