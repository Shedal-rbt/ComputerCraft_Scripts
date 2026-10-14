-- chat_display.lua
local monitor = peripheral.find("monitor")
if not monitor then error("No monitor attached", 0) end
monitor.setTextScale(0.5)

local modem = peripheral.find("modem")
if not modem then error("No modem attached", 0) end
rednet.open(peripheral.getName(modem))

local PROTOCOL = "chat"
local lines = {}   -- { text = "...", color = colors.x }

-- Wrap a string to a given width, splitting on newlines first.
local function wrap(text, width)
  local out = {}
  for paragraph in (text .. "\n"):gmatch("([^\n]*)\n") do
    if #paragraph == 0 then
      out[#out + 1] = ""
    else
      while #paragraph > width do
        out[#out + 1] = paragraph:sub(1, width)
        paragraph = paragraph:sub(width + 1)
      end
      out[#out + 1] = paragraph
    end
  end
  return out
end

local function redraw()
  local w, h = monitor.getSize()
  monitor.clear()

  monitor.setCursorPos(1, 1)
  monitor.setTextColor(colors.yellow)
  monitor.write("Chat")

  local visible = h - 1
  local start = math.max(1, #lines - visible + 1)
  for i = start, #lines do
    local line = lines[i]
    monitor.setCursorPos(1, 2 + (i - start))
    monitor.setTextColor(line.color or colors.white)
    monitor.write(line.text)
  end

  monitor.setTextColor(colors.white)
end

local function addMessage(name, text)
  local w = select(1, monitor.getSize())
  local stamp = textutils.formatTime(os.time(), true)
  local header = string.format("[%s] %s: ", stamp, name)
  local wrapped = wrap(header .. text, w)

  for i, l in ipairs(wrapped) do
    lines[#lines + 1] = {
      text = l,
      color = (i == 1) and colors.lightBlue or colors.white,
    }
  end
  redraw()
end

redraw()

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "rednet_message" then
    local sender, message, protocol = p1, p2, p3
    if protocol == PROTOCOL then
      if type(message) == "table" and message.text then
        addMessage(message.name or ("#" .. sender), message.text)
      elseif type(message) == "string" then
        addMessage("#" .. sender, message)
      end
    end
  elseif event == "monitor_resize" then
    redraw()
  end
end
