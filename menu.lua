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
    local marked_track = handler.marked_track()
    if marked_track then
        table.insert(menu_list.context_menu, {"command", "Unmark track", "", function () handler.mark_track(nil) end, "", false, false})
        table.insert(menu_list.context_menu, {"cascade", "Set Person Id", "person_id_menu", "", "", false})
        menu_list.person_id_menu = {}
        for name, ignored in pairs(handler.get_person_ids()) do
            table.insert(menu_list.person_id_menu, {
                "command", name, "", 
                function() handler.set_person_id(marked_track.id, name) end, 
                "", (name == marked_track.person_id)})
        end
        table.insert(menu_list.person_id_menu, {
            "command", "-- enter new name", "", 
            function() handler.set_person_id(marked_track.id, self.name_dialog()) end, 
            "", false})
    else
        local next = handler.find_annotation_next_to(vx, vy)
        if (next) then
            table.insert(menu_list.context_menu, {"command", "Mark track", "", function () handler.mark_track(next) end, "", false, false})
        end
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
    engine.createMenu(menu_list, 'context_menu', -1, -1, 'tk')
end
function Menu:name_dialog()
    local result = utils.subprocess({args={"zenity","--entry"}})
    return string.gsub(result.stdout, "\n", "")
end

return Menu