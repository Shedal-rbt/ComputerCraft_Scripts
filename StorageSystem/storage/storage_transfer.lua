local inventory = require("lib.inventory")
local packs = dofile("storage/packs.tbl")
local roles = inventory.resolveRoles(packs.roles)
local expected = { "inbox", "outbox", "messy" }
local missing = {}
for _, role in ipairs(expected) do
  if not roles[role] then
    missing[#missing + 1] = role
  end
end
if #missing > 0 then
  printError("Missing role packs:" .. table.concat(missing, ", "))
  printError("Check Markers in slots 1-" .. packs.markerSlots .. ".")
  printError("Currently Visible Inventories:")
  for _, name in ipairs(inventory.find()) do
    print("  " .. name)
  end
  return
end
