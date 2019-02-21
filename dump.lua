function dump(o, level, max_depth)
   local l = level or 1
   local m = max_depth or 10
   -- thanks to https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if (k == '__index') then
            v = tostring(v)
         elseif (l>=m) then 
            v = '__(' .. tostring(v) .. ')' 
         else 
            v = dump(v,l+1,m) 
         end
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. v .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

return dump