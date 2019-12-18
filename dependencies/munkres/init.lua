local cp = package.cpath
package.cpath = ("./".. ...):gsub("init","?.so")
local munkres = require("munkres")
package.cpath = cp

local example1 = {
    {100, 100, 1},
    {100, 2, 21512},
    {1, 4, 9852},
    {6, 30252, 400},
}

local solution1 = {
    {0, 0, 1, 0},
    {0, 1, 0, 0},
    {1, 0, 0, 0},
    {0, 0, 0, 1},
};

local example2 = {
  {100, 1},
  {100, 12},
  {1, 4},
  {6, 30252}
};

--- TODO: this isn't right
local solution2 = {
  {0,1,0,0},
  {0,0,1,0},
  {1,0,0,0},
  {0,0,0,1},
};

local function compare_rows_equal(a, b)
  if b == nil then 
    return false
  end
  for k,i in pairs(a) do
    if (b[k] == nil) or (b[k] ~= i) then
      return false
    end
  end
  return true
end

local function compare_tables(a, b)
  for k,i in pairs(a) do
      if not compare_rows_equal(a[k], b[k]) then
        return false
      end
  end
  return true
end

-- check if the library is working properly
assert(compare_tables(minimize_weights(example1)['assignment'],solution1))
assert(compare_tables(minimize_weights(example2)['assignment'],solution2))

return { minimize_weights = minimize_weights, maximize_utility = maximize_utility }