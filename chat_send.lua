-- chat_send.lua
local modem = peripheral.find("modem")
if not modem then error("No modem attached", 0) end
rednet.open(peripheral.getName(modem))

local PROTOCOL = "chat"

write("Your name: ")
local name = read() or "anon"

print("Type a message and press enter. Ctrl+T to exit.")

while true do
  write("> ")
  local msg = read()
  if msg and #msg > 0 then
    rednet.broadcast({ name = name, text = msg }, PROTOCOL)
  end
end
