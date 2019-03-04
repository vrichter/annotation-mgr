function dump(o, level, max_depth, pretty)
   local l = level or 1
   local m = max_depth or 10
   local pretty_n = function(param)
      if pretty and (string.len(param) > 10) then
         return '\n' .. param
      else
         return param
      end
   end
   local pretty_i = function(depth, param)
      local result = param
      if pretty then
         local indent = 1
         while indent < depth do
            result = '    ' .. result
            indent = indent + 1
         end
      end
      return result
   end
   -- thanks to https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
   if not o then
      return 'NIL'
   end
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if (k == '__index') then
            v = tostring(v)
         elseif (l>=m) then 
            v = '__(' .. tostring(v) .. ')' 
         else 
            v = dump(v,l+1,m,pretty) 
         end
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. pretty_n(pretty_i(l,'['..k..'] = ' .. v .. ','))
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
function dump_pp(o)
   return dump(o,1,10,true)
end

return dump