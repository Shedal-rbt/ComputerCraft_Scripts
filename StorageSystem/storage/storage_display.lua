-- storage_display.lua
--
-- Live view of every inventory on the wired network, with scrolling
-- Discovery handled by lib/inventory
--
-- Controls:
--    Arrow Up/Down        |    Scroll one row
--    Page Up/ Page Down   |    Scroll one screen
--    Home/End             |    Jump to Top/Bottom
--    Touch/Click          |    Top/Bottom half of list: Up/Down
--    forward slash        |    Start typing a filter
--    Tab                  |    Toggle filter scope: Name <-> Mod
--    Backspace            |    Delete a character while filtering
--    Enter                |    Keep filter, leave typing mode
--    Esc                  |    Clear filter, leave typing mode
-- Setup:
--      Wired Motem on the computer, wired modem on each storage block.
--      Network cable between them, optionally attach a monitor

local inventory = require("lib.inventory")

-- Config:
local CONFIG = {
  refresh = 2,
  countWidth = 7,
}

-- Output target: Monitor if we find one, else use computer terminal.
local monitor = peripheral.find("monitor")
local target = monitor or term
if monitor then
  monitor.setTextScale(0.5)
end

local monitorName = nil
if monitor then
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.wrap(name) == monitor then
      monitorName = name
      break
    end
  end
end


----------------------
--Formatting helpers--
----------------------

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

--Debounce: When set, a timer is pending that will redraw soon
local redrawPending = false
local redrawTimer = nil

local state = {
  all = {},
  list = {},
  invCount = 0,
  scroll = 0,
  filtering = false,
  filterText = "",
  filterScope = "name",
}
--how many rows fit in screen
local function visibleRows()
  local _, h = target.getSize()
  return math.max(1, h-4)
end
-- Prevent over/underscrolling
local function clampScroll()
  local maxScroll = math.max(0,#state.list - visibleRows())
  if state.scroll > maxScroll then state.scroll = maxScroll end
  if state.scroll < 0 then state.scroll = 0 end
end

--Rebuild state.list from state.all using the current filter
--also resets scroll to the top since the visible set changes
local function applyFilter()
  local q = state.filterText
  -- No filter = show all
  if q == "" then
    state.list = state.all
  else
    local list = {}
    for _, item in ipairs(state.all) do
      local mod, name = inventory.splitName(item.name)
      -- lowercase the stack
      local haystack
      if state.filterScope == "mod" then
        haystack = mod:lower()
      else
        haystack = name:lower()
      end
      -- plain = true so special characters like "-" or "." in the filter
      -- arent treated as lua patterns
      if haystack:find(q, 1, true) then
        list[#list + 1] = item
      end
    end
    state.list = list
  end
  state.scroll = 0
end

-- Rescan network, rebuild state
local function refresh()
  local totals, invCount = inventory.scan()
  local all = {}
  for name, entry in pairs(totals) do
    all[#all + 1] = { name = name, count = entry.count }
  end
  table.sort(all, function(a, b) return a.name < b.name end)
  state.all = all
  state.invCount = invCount
  applyFilter()
end

-----------
--DRAWING--
-----------
local function draw()
  local w, h = target.getSize()
  clampScroll()

  target.setBackgroundColor(colors.black)

  -- Header.
  target.setCursorPos(1, 1)
  target.setTextColor(colors.yellow)
  local header
  if state.filterText == "" then
    header = ("Storage - %d types / %d inv"):format(#state.list, state.invCount)
  else
    header = ("Storage - %d/%d (filter:%s)"):format(
      #state.list, #state.all, state.filterScope)
  end
  target.write(header)

  -- Separator.
  target.setCursorPos(1, 2)
  target.setTextColor(colors.gray)
  target.write(string.rep("-", w))

  -- Body.
  local rows = visibleRows()
  local firstRow = 3
  local lastBodyRow = h - 2

  if #state.list == 0 then
    target.setCursorPos(1, firstRow)
    target.setTextColor(colors.gray)
    if state.filterText == "" then
      target.write("(no items)")
    else
      target.write("(no matches)")
    end
  else
    local row = firstRow
    local last = math.min(#state.list, state.scroll + rows)

    for i = state.scroll + 1, last do
      local item = state.list[i]
      target.setCursorPos(1, row)
      target.setTextColor(colors.white)

      local nameW = w - CONFIG.countWidth - 1
      target.write(padRight(
          padRight(shortName(item.name), nameW)
          .. " "
          .. padLeft(tostring(item.count),
            CONFIG.countWidth), w)
      )
      row = row + 1
    end
  end
  while row <= lastBodyRow do
    target.setCursorPos(1,row)
    target.write(string.rep(" ", w))
    row = row + 1
  end
  -- Filter / status line (row h-1).
  target.setCursorPos(1, h - 1)
  if state.filtering then
    target.setTextColor(colors.lightBlue)
    local cursor = (state.filterText == "" and "_" or "")
    target.write(padRight(
      ("filter[%s]: %s%s"):format(state.filterScope, state.filterText, cursor), w))
  else
    target.setTextColor(colors.gray)
    target.write(padRight("  / filter   tab scope   arrows scroll   esc clear", w))
  end

  -- Footer: scroll indicator (row h).
  target.setCursorPos(1, h)
  target.setTextColor(colors.gray)

  if #state.list <= rows then
    target.write(string.rep(" ", w))
  else
    local first = state.scroll + 1
    local last  = math.min(#state.list, state.scroll + rows)
    local up    = state.scroll > 0 and "^" or " "
    local down  = last < #state.list and "v" or " "
    local text  = (" %s %d-%d/%d %s "):format(up, first, last, #state.list, down)
    local pad   = math.max(0, math.floor((w - #text) / 2))
    target.write(padRight(string.rep(" ", pad) .. text, w))
  end

  target.setTextColor(colors.white)
end

-- Request a redraw, if one is already scheduled, does nothing, it'll pick up the latest state when it fires.
local function requestRedraw()
  if redrawTimer then return end
  redrawPending = true
  redrawTimer = os.startTimer(0.05) --(Caps at 20 draws per second)
end

---------------
-- Scrolling --
---------------
local function scrollBy(amount)
  state.scroll = state.scroll + amount
  clampScroll()
  draw()
end

--------------------
-- Event Handling --
--------------------

local function handleKey(keyCode)
  -- While filtering, keys go into the filter instead of scrolling.
  if state.filtering then
    if keyCode == keys.backspace then
      state.filterText = state.filterText:sub(1, -2)
      applyFilter()
      requestRedraw()
    elseif keyCode == keys.enter then
      state.filtering = false
      requestRedraw()
    elseif keyCode == keys.escape then
      state.filtering = false
      state.filterText = ""
      applyFilter()
      draw()
    elseif keyCode == keys.tab then
      state.filterScope = (state.filterScope == "name") and "mod" or "name"
      applyFilter()
      requestRedraw()
    end
    return
  end

  -- Not filtering: normal navigation.
  if keyCode == keys.up then
    scrollBy(-1)
  elseif keyCode == keys.down then
    scrollBy(1)
  elseif keyCode == keys.pageUp then
    scrollBy(-visibleRows())
  elseif keyCode == keys.pageDown then
    scrollBy(visibleRows())
  elseif keyCode == keys.home then
    state.scroll = 0
    requestRedraw()
  elseif keyCode == keys["end"] then
    state.scroll = #state.list
    clampScroll()
    requestRedraw()
  elseif keyCode == keys.slash then
    state.filtering = true
    draw()
  elseif keyCode == keys.escape then
    state.filterText = ""
    applyFilter()
    draw()
  end
end

-- Append typed characters to the filter.
local function handleChar(ch)
  if not state.filtering then return end

  -- Only accept printable characters. Ignore control chars.
  if #ch == 1 and ch:byte() >= 32 then
    state.filterText = state.filterText .. ch:lower()
    applyFilter()
    requestRedraw()
  end
end

local function handleTap(x, y)
  local _, h = target.getSize()

  -- Taps on the body scroll. Taps elsewhere do nothing for now.
  if y < 3 or y > h - 2 then return end

  local bodyMid = 3 + math.floor((h - 2 - 3) / 2)

  if y <= bodyMid then
    scrollBy(-1)
  else
    scrollBy(1)
  end
end


---------------
-- Main Loop --
---------------

-- Initial scan/draw
refresh()
draw()

local timer = os.startTimer(CONFIG.refresh)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == timer then
    local ok, err = pcall(function()
      refresh()
      draw()
    end)
    if not ok then printError(tostring(err)) end

    timer = os.startTimer(CONFIG.refresh)

  elseif event == "key" then
    handleKey(p1)

  elseif event == "char" then
    handleChar(p1)

  elseif event == "monitor_touch" then
    if not monitorName or p1 == monitorName or p1 == "monitor" then
      handleTap(p2, p3)
    end

  elseif event == "mouse_click" then
    if p1 == 1 then
      handleTap(p2, p3)
    end

  elseif event == "monitor_resize" or event == "term_resize" then
    draw()
  elseif event == "timer" and p1 = redrawTimer then 
    redrawTimer = nil
    if redrawPending then
      redrawPending = false
      draw()
    end
  end
end
