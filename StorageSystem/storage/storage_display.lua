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
--
-- Setup:
--      Wired Motem on the computer, wired modem on each storage block.
--      Network cable between them, optionally attach a monitor

local inventory = require(lib.inventory)

-- Config:
local CONFIG = {
  refresh = 2,
  countWidth = 7,
  showEmpty = false
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

local state = {
  list = {},
  invCount = 0,
  scroll = 0,
}
--how many rows fit in screen
local function visibleRows()
  local _, h = target.getSize()
  return math.max(1, h-3)
end
-- Prevent over/underscrolling
local function clampScroll()
  local maxScroll = math.max(0,#state.list - visibleRows())
  if state.scroll > maxScroll then state.scroll = maxScroll end
  if state.scroll < 0 then state.scroll = 0 end
end

-- Rescan network, rebuild state
local function refresh()
  local totals, invCount = inventory.scan()
  local list = {}
  for name, entry in pairs(totals) do
    list[#list + 1] = {name = name, count = entry.count}
  end
  table.sort(list, function(a,b) return a.name < b.name end)
  state.list = list
  state.invCount = invCount
end

-----------
--DRAWING--
-----------
local function draw()
  local w, h = target.getSize()
  clampScroll()

  target.setBackgroundColor(colors.black)
  target.clear()

  --Header
  target.setCursorPos(1,1)
  target.setTextColor(colors.yellow)
  target.write(("Storage - %d types / %d inv"):format(#state.list, state.invCount))
  
  --Separator
  target.setCursorPos(1,2)
  target.setTextColor(colors.gray)
  target.write(string.rep("-",w))
  --Body
  local rows = visibleRows()
  local firstRow = 3
  local lastRow = h - 1
  if #state.list == 0 then
    target.setCursorPos(1,firstRow)
    target.setTextColor(colors.gray)
    target.write("(No Items)")
  else
    local row = firstRow
    local last = math.min(#state.list, state.scroll + rows)
    for i = state.scroll + 1, last do
      local item = state.list[i]
      target.setCursorPos(1,row)
      target.setTextColor(colors.white)
      local nameW = w - CONFIG.countWidth - 1
      target.write(
        padRight(shortName(item.name), nameW) .. " " .. padLeft(tostring(item.count), CONFIG.countWidth)
      )
      row = row + 1
    end
  end
    
  --Footer: Scroll indivator
  target.setCursorPos(1,h)
  target.setTextColor(colors.gray)
  if #state.list <= rows then
    target.write(string.rep(" ", w))
  else
    local first = state.scroll + 1
    local last = math.min(#state.list, state.scroll + rows)
    local up = state.scroll > 0 and "^" or " "
    local down = last < #state.list and "v" or " "
    local text = (" %s %d-%d\%d %s "):format(up, first, last, #state.list, down)
    local pad = math.max(0,math.floor((w-#text)/2))
    target.write(padRight(string.rep(" ", pad) .. text, w))
  end
  target.setTextColor(colors.white)
end

---------------
-- Scrolling --
---------------
local function scrollBy(amount)
  state.scroll = state.scroll + amount
  clampScroll()
  draw()
end

local function handleKey(keyCode)
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
    draw()
  elseif keyCode ==keys["end"] then
    state.scroll = #state.list
    clampScroll()
    draw()
  end
end

-- handle taps
local function handleTap(x,y)
  local _, h = target.getSize()
  -- ignore taps on header, footer, or seperator
  if y < 3 or y > h-1 then return end
  local bodyMid = 3 + math.floor((h-1-3)/2)
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
  elseif event == "monitor_touch" then
    if not monitorName or p1 == monitorName or p1 == "monitor" then
      handleTap(p2, p3)
    end
  elseif event == "mouse_click" then 
    if p1==1 then 
      handleTap(p2, p3)
    end
  elseif event == "monitor_resize" or event == "term_resize" then
    draw()
  end
end
