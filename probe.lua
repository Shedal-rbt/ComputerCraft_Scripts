-- probe.lua — compact peripheral inspector
local function wrapItems(prefix, items, width)
  local lines = {}
  local cur = prefix
  for _, item in ipairs(items) do
    local sep = (#cur == #prefix) and "" or "  "
    if #cur + #sep + #item > width then
      lines[#lines + 1] = cur
      cur = "  " .. item
    else
      cur = cur .. sep .. item
    end
  end
  if #cur > #prefix then lines[#lines + 1] = cur end
  return lines
end

local function probe(name)
  local t = peripheral.getType(name) or "?"
  local methods = peripheral.getMethods(name) or {}
  table.sort(methods)

  local w = term.getSize()
  local out = {}
  out[#out + 1] = name .. "  [" .. t .. "]  " .. #methods .. " methods"
  for _, l in ipairs(wrapItems("  ", methods, w)) do
    out[#out + 1] = l
  end
  return out
end

local target = ...
local names = target and { target } or peripheral.getNames()

if #names == 0 then
  print("No peripherals attached.")
  return
end

local all = {}
for _, name in ipairs(names) do
  for _, l in ipairs(probe(name)) do all[#all + 1] = l end
  all[#all + 1] = ""
end

textutils.pagedPrint(table.concat(all, "\n"))
