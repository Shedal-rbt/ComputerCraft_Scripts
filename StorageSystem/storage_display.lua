-- storage_display.lua

-- Config:
local CONFIG = {
  refresh = 2,
  countWidth = 7,
  showEmpty = false
}

-- Target is either the first monitor found or the terminal of the computer
local monitor = peripheral.find(monitor)
local target = monitor or term

-- isInventory: Returns true if the peripheral has the methods 'list' and 'size'
local function isInventory(name)
  local methods = peripheral.getMethods(name) or {}
  local hasList = false
  local hasSize = false
  for _, m in ipairs(methods) do
    if m == "list" then hasList = true end
    if m == "size" then hasSize = true end
  end
  return hasList and hasSize
end

-- findInventories: returns a table of every peripheral name that looks like an inventory
--  Basically filters through all peripherals given by peripheral.getNames() for inventories
local function findInventories()
  local invs = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then
      invs[#invs + 1] = name
    end
  end
  return invs
end

-- scan: Walks through all the inventories and totals up item counts by item name.
--  Returns 2 things:
--    totals: table: item names -> {count = N}
--    invCount: how many inventories had something in them
local function scan()
  local totals = {}
  local invCount = 0
  for _, name in ipairs(findInventories()) do
    local ok, contents = pcall(peripheral.call, name, "list")     -- Call list for an inventory using a pcall, store inventory in contents, and if it worked in ok
    if ok and contents then
      local used = false                                          -- Assume the inventory is empty.
      for _, item in pairs(contents) do
        used = true
        local existing = totals[item.name]                        -- This lets you check if another inventory had already added this to the totals
        if existing then
          existing.count = existing.count + item.count
        else
          totals[item.name] = {count = item.count}
        end
      end
      if used or CONFIG.showEmpty then
        invCount = invCount + 1
      end
    end
  end
  return totals, invCount
end

-- Shortens full item names
-- (EG: minecraft:iron_ingot -> iron_ingot)
local function shortName(full)
  return full:match(":(.+)$") or full
end

-- pads a string 's' on the right with spaces til its 'w' characters wide, if larger than w than truncate it
local function padRight(s,w)
  if #s >= w then
    return s:sub(1,w)
  end
  return s .. string.rep(" ", w - #s)
end

-- Same as padright, but for the left.
local function padLeft(s,w)
  if #s >= w then
    return s:sub(1,w)
  end
  return string.rep(" ", w - #s) .. s
end

local function draw()
  local totals, invCount = scan()
  local list = {}
  for name, entry in pairs(totals) do
    list[#list + 1] = { name = name, count = entry.count }
  end

  table.sort(list, function(a, b)
    return a.name < b.name
  end)

  -- getSize() returns width, height (two values).
  local w, h = target.getSize()

  target.setBackgroundColor(colors.black)
  target.clear()

  -- Header line.
  target.setCursorPos(1, 1)
  target.setTextColor(colors.yellow)
  target.write(("Storage - %d types / %d inv"):format(#list, invCount))

  -- Separator line.
  target.setCursorPos(1, 2)
  target.setTextColor(colors.gray)
  target.write(string.rep(" ", w))

  -- Body: one row per item type, starting at row 3.
  local row = 3
  for _, item in ipairs(list) do
    if row > h then
      -- Out of vertical room. Print a "... N more" note and stop.
      target.setCursorPos(1, h)
      target.setTextColor(colors.gray)
      target.write("... " .. (#list - (row - 3)) .. " more")
      break
    end

    target.setCursorPos(1, row)
    target.setTextColor(colors.white)

    local nameW = w - CONFIG.countWidth - 1

    target.write(
      padRight(shortName(item.name), nameW)
      .. " "
      .. padLeft(tostring(item.count), CONFIG.countWidth)
    )

    row = row + 1
  end

  -- Reset colors so anything drawn later isn't stuck on gray/black.
  target.setTextColor(colors.white)
  target.setBackgroundColor(colors.black)
end

-- Main loop. Runs forever, redrawing every CONFIG.refresh seconds.
-- pcall wraps draw() so a single bad scan can't kill the script.
while true do
  local ok, err = pcall(draw)

  if not ok then
    printError(tostring(err))
    sleep(2)
  end

  sleep(CONFIG.refresh)
end
