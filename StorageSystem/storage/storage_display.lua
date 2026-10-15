-- storage_display.lua
--
-- Live view of every inventory on the wired network, with scrolling.
-- Discovery handled by lib/inventory.
--
-- Controls:
--    Arrow Up/Down        | Scroll one row
--    Page Up/Page Down    | Scroll one screen
--    Home/End             | Jump to Top/Bottom
--    Touch/Click          | Top/Bottom half of list: Up/Down
--    forward slash        | Start typing a filter
--    Tab                  | Toggle filter scope: Name <-> Mod
--    Backspace            | Delete a character while filtering
--    Enter                | Keep filter, leave typing mode
--    Esc                  | Clear filter, leave typing mode
 
local inventory = require("storage.lib.inventory")
 
local CONFIG = {
  refresh = 2,
  countWidth = 7,
  redrawDelay = 0.05,
}
 
-- Output target: monitor if available, otherwise terminal.
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
-- Formatting helpers
----------------------
 
local function shortName(full)
  return full:match(":(.+)$") or full
end
 
local function padRight(s, w)
  if #s >= w then
    return s:sub(1, w)
  end
  return s .. string.rep(" ", w - #s)
end
 
local function padLeft(s, w)
  if #s >= w then
    return s:sub(1, w)
  end
  return string.rep(" ", w - #s) .. s
end
 
----------------
-- Application state
----------------
 
local state = {
  all = {},
  list = {},
  invCount = 0,
  scroll = 0,
  filtering = false,
  filterText = "",
  filterScope = "name",
}
 
local redrawTimer = nil
 
local function visibleRows()
  local _, h = target.getSize()
  return math.max(1, h - 4)
end
 
local function clampScroll()
  local maxScroll = math.max(0, #state.list - visibleRows())
 
  if state.scroll > maxScroll then
    state.scroll = maxScroll
  end
 
  if state.scroll < 0 then
    state.scroll = 0
  end
end
 
----------------
-- Filtering
----------------
 
-- Each item caches its lowercase name and mod ID.
-- resetScroll is true when the user changes the filter.
local function applyFilter(resetScroll)
  local q = state.filterText
 
  if q == "" then
    state.list = state.all
  else
    local list = {}
    local field = state.filterScope == "mod"
      and "modLower"
      or "nameLower"
 
    for _, item in ipairs(state.all) do
      if item[field]:find(q, 1, true) then
        list[#list + 1] = item
      end
    end
 
    state.list = list
  end
 
  if resetScroll then
    state.scroll = 0
  end
 
  clampScroll()
end
 
----------------
-- Inventory refresh
----------------
 
local function refresh()
  local totals, invCount = inventory.scan()
  local all = {}
 
  for name, entry in pairs(totals) do
    local mod, itemName = inventory.splitName(name)
 
    all[#all + 1] = {
      name = name,
      count = entry.count,
 
      -- Cache values used by filtering.
      modLower = mod:lower(),
      nameLower = itemName:lower(),
    }
  end
 
  table.sort(all, function(a, b)
    return a.name < b.name
  end)
 
  state.all = all
  state.invCount = invCount
 
  -- Rebuild the filtered list without resetting the user's scroll.
  applyFilter(false)
end
 
-----------
-- Drawing
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
    header = ("Storage - %d types / %d inv"):format(
      #state.list, state.invCount)
  else
    header = ("Storage - %d/%d (filter:%s)"):format(
      #state.list, #state.all, state.filterScope)
  end
 
  target.write(padRight(header, w))
 
  -- Separator.
  target.setCursorPos(1, 2)
  target.setTextColor(colors.gray)
  target.write(string.rep("-", w))
 
  -- Body.
  local rows = visibleRows()
  local firstRow = 3
  local lastBodyRow = h - 2
  local row = firstRow
 
  if #state.list == 0 then
    target.setCursorPos(1, firstRow)
    target.setTextColor(colors.gray)
 
    target.write(
      state.filterText == "" and "(no items)" or "(no matches)"
    )
  else
    local last = math.min(#state.list, state.scroll + rows)
    local nameW = math.max(0, w - CONFIG.countWidth - 1)
 
    for i = state.scroll + 1, last do
      local item = state.list[i]
 
      target.setCursorPos(1, row)
      target.setTextColor(colors.white)
 
      local line = padRight(shortName(item.name), nameW)
        .. " "
        .. padLeft(tostring(item.count), CONFIG.countWidth)
 
      target.write(padRight(line, w))
      row = row + 1
    end
  end
 
  -- Clear unused body rows.
  while row <= lastBodyRow do
    target.setCursorPos(1, row)
    target.setTextColor(colors.white)
    target.write(string.rep(" ", w))
    row = row + 1
  end
 
  -- Filter / status line.
  target.setCursorPos(1, h - 1)
 
  if state.filtering then
    target.setTextColor(colors.lightBlue)
 
    local cursor = state.filterText == "" and "_" or ""
    local line = ("filter[%s]: %s%s"):format(
      state.filterScope, state.filterText, cursor)
 
    target.write(padRight(line, w))
  else
    target.setTextColor(colors.gray)
    target.write(padRight(
      "  / filter   tab scope   arrows scroll   esc clear", w))
  end
 
  -- Scroll indicator.
  target.setCursorPos(1, h)
  target.setTextColor(colors.gray)
 
  if #state.list <= rows then
    target.write(string.rep(" ", w))
  else
    local first = state.scroll + 1
    local last = math.min(#state.list, state.scroll + rows)
    local up = state.scroll > 0 and "^" or " "
    local down = last < #state.list and "v" or " "
 
    local line = (" %s %d-%d/%d %s "):format(
      up, first, last, #state.list, down)
 
    local pad = math.max(0, math.floor((w - #line) / 2))
 
    target.write(padRight(string.rep(" ", pad) .. line, w))
  end
 
  target.setTextColor(colors.white)
end
 
----------------
-- Redraw scheduling
----------------
 
local function requestRedraw()
  if redrawTimer then
    return
  end
 
  redrawTimer = os.startTimer(CONFIG.redrawDelay)
end
 
local function scrollBy(amount)
  state.scroll = state.scroll + amount
  clampScroll()
  requestRedraw()
end
 
----------------
-- Keyboard input
----------------
 
local function handleKey(keyCode)
  if state.filtering then
    if keyCode == keys.backspace then
      state.filterText = state.filterText:sub(1, -2)
      applyFilter(true)
      requestRedraw()
 
    elseif keyCode == keys.enter then
      state.filtering = false
      requestRedraw()
 
    elseif keyCode == keys.escape then
      state.filtering = false
      state.filterText = ""
      applyFilter(true)
      requestRedraw()
 
    elseif keyCode == keys.tab then
      state.filterScope =
        state.filterScope == "name" and "mod" or "name"
 
      applyFilter(true)
      requestRedraw()
    end
 
    return
  end
 
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
    requestRedraw()
 
  elseif keyCode == keys.escape then
    state.filterText = ""
    applyFilter(true)
    requestRedraw()
  end
end
 
local function handleChar(ch)
  if not state.filtering then
    return
  end
 
  if #ch == 1 and ch:byte() >= 32 then
    state.filterText = state.filterText .. ch:lower()
    applyFilter(true)
    requestRedraw()
  end
end
 
----------------
-- Mouse / monitor input
----------------
 
local function handleTap(x, y)
  local _, h = target.getSize()
 
  if y < 3 or y > h - 2 then
    return
  end
 
  local bodyMid = 3 + math.floor((h - 2 - 3) / 2)
 
  if y <= bodyMid then
    scrollBy(-1)
  else
    scrollBy(1)
  end
end
 
----------------
-- Input event loop
----------------
 
local function inputLoop()
  while true do
    local event, p1, p2, p3 = os.pullEvent()
 
    if event == "key" then
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
      requestRedraw()
 
    elseif event == "timer" and p1 == redrawTimer then
      redrawTimer = nil
      draw()
    end
  end
end
 
----------------
-- Refresh loop
----------------
 
local function refreshLoop()
  while true do
    os.sleep(CONFIG.refresh)
 
    local ok, err = pcall(refresh)
 
    if ok then
      requestRedraw()
    else
      printError("Storage refresh failed: " .. tostring(err))
    end
  end
end
 
----------------
-- Startup
----------------
 
local ok, err = pcall(refresh)
 
if not ok then
  error("Initial storage scan failed: " .. tostring(err), 0)
end
 
draw()
 
-- Run input handling and periodic refresh as separate coroutines.
parallel.waitForAny(inputLoop, refreshLoop)
