local inventory = require("lib.inventory")
local packs = dofile("storage/packs.tbl")
local roles = inventory.resolveRoles(packs.roles)
local expected = { "inbox", "outbox", "messy" }
local missing = {}
local function checkRoles()
  for _, role in ipairs(expected) do
    if not roles[role] then
      missing[#missing + 1] = role
    end
  end
  if #missing == 0 then return true end
  if #missing > 0 then
    printError("Missing role packs:" .. table.concat(missing, ", "))
    printError("Check Markers in slots 1-" .. packs.markerSlots .. ".")
    printError("Currently Visible Inventories:")
    for _, name in ipairs(inventory.find()) do
      print("  " .. name)
    end
  end
  return false
end

if not checkRoles() then return end

-------------
-- Helpers --
-------------

--Marker slots are reserved for markets, nothing the transfer script does is allowed to touch them.
local function isMarkerSlot(packName, slot)
  if packName == roles.inbox
    or packName == roles.outbox
    or packname == roles.messy then
    return slot <= packs.markerSlots
  end
  return false
end

-- Every item stack matching 'query' (case-insensitive substring on the short name,
-- e.g. "Iron" matches "iron_ingot" and "iron_block").
-- Excludes the outbox, as we are never fetching from where we deposit.
-- Returns an array of {pack = name, slot = n, name = fullID, count = n}
local function findMatches(query)
  local q = query:lower()
  local matches = {}
  for packName, contents  in pairs(inventory.scanEach()) do
    if packName ~= roles.outbox then
      for slot, item in pairs(contents) do
        if not isMarkerSlot(packName, slot) then
          local _, short = inventory.splitName(item.name)
          if short:lower():find(q, 1, true) then
            matches[#matches + 1] = {
              pack = packName,
              slot = slot,
              name = item.name,
              count = item.count,
            }
          end
        end
      end
    end
  end
  return matches
end


-- Find a slot in 'destName' that can receive 'itemName'
-- Prefers the fullest, not full stack of that item (so we top up big stacks instead of sprinkling items around)
-- Falls back to the first empty non marker slot. returns nil if the pack cant take it.
local function findDestSlot(destName, itemName)
  local dest = peripheral.wrap(destName)
  if not dest then return nil end
  local contents = dest.list() or {}
  local size = dest.size and dest.size() or 0
  local bestMergeSlot = nil
  local bestMergeCount = -1
  local firstFree = nil
  for slot = 1, size do
    if isMarkerSlot(destName, slot) then
      -- We do nothing here, because we NEVER touch markers
    elseif contents[slot] then
      if contents[slot].name == itemName then
        -- Ask what the stack limit is for the slot, default is 64 if it errors or gives a non-number. 
        local limit = 64
        local ok, val = pcall(dest.getItemLimit, slot)
        if ok and type(val) == "number" then
          limit = val
        end
        local count = contents[slot].count
        if count < limit and count > bestMergeCount then
          bestMergeCount = count
          bestMergeSlot = slot
        end
      end
    elseif not firstFree then
      firstFree = slot
    end
  end
  return bestMergeSlot or firstFree
end

-- Given a stack list for one item, returns packs ordered by 'fullest non-full stack of that item," decending.
-- Packs with only full stacks of the item are left at the end.  
local function orderPacks(candidates)
  if not candidates then return {} end
  -- Reduce to one entry per pack, keeping the max non-full count
  local byPack = {}
  for _, c in ipairs(candidates) do
    local e = byPack[c.pack]
    if not e then
      e = {pack = c.pack, bestNonFull = -1}
      byPack[c.pack] = e
    end
    if c.count < c.limit and c.count > e.bestNonFull then
      e.bestNonFull = c.count
    end
  end
  local list = {}
  for _, e in pairs(byPack) do
    list[#list + 1] = e
  end
  table.sort(list, function(a,b) return a.bestNonFull > b.bestNonFull end)
  return list
end

--------------
-- Commands --
--------------

-- fetch [count] <item...>
--    Count defaults to 64 if the first word isnt a number.
--    Query can be mulriple words; theyre joined with spaces. 
local function cmdFetch(args)
  local count = 64
  local queryStart = 1

  if args[1] and tonumber(args[1]) then
    count = tonumber(args[1])
    queryStart = 2
  end

  local queryParts = {}
  for i = queryStart, #args do
    queryParts[#queryParts + 1] = args[i]
  end
  local query = table.concat(queryParts, " ")

  if query == "" then
    print("Usage: fetch [count] <item>")
    return
  end

  local matches = findMatches(query)
  if #matches == 0 then
    print(("No items matching '%s'."):format(query))
    return
  end

  -- Drain fuller stacks first so we don't leave a trail of near-empty
  -- stacks when we could have emptied a big one.
  table.sort(matches, function(a, b) return a.count > b.count end)

  local moved = 0
  local needed = count

  for _, m in ipairs(matches) do
    if needed <= 0 then
      break
    end

    local source = peripheral.wrap(m.pack)
    if source then
      local toMove = math.min(needed, m.count)

      -- pushItems(toName, fromSlot, limit, toSlot)
      -- call it on the source, pushing into the outbox. No toSlot --
      -- let the outbox decide where to land (it will merge with same items).
      local ok, actual = pcall(source.pushItems, roles.outbox, m.slot, toMove)

      if ok and actual and actual > 0 then
        moved = moved + actual
        needed = needed - actual
      elseif not ok then
        printError(("  push failed from %s slot %d: %s"):format(
          m.pack, m.slot, tostring(actual)))
      end
    end
  end

  print(("Fetched %d of %d '%s' into outbox."):format(moved, count, query))

end

-- store
--  Move everything from the inbox into packs that already hold that item
--  Anything without a match goes to the messy pack.
--  When multiple packs hold the item, prefers the pack with the fullest, non-full stack 
--  so partial stacks get topped off before new ones open.
local function cmdStore()
  local inbox = peripheral.wrap(roles.inbox)
  if not inbox then
    printError("Inbox not available.")
    return
  end

  local contents = inventory.listContents(roles.inbox) or {}

  -- Build an index: item name -> list of every stack of that item
  -- across the network, excluding the three role packs.
  -- Each entry: { pack = name, count = n, limit = n }
  local index = {}
  for packName, packContents in pairs(inventory.scanEach()) do
    if packName ~= roles.inbox
       and packName ~= roles.outbox
       and packName ~= roles.messy then
      for slot, item in pairs(packContents) do
        if not isMarkerSlot(packName, slot) then
          -- Query the stack limit for this slot.
          local limit = 64
          local ok, val = pcall(peripheral.call, packName, "getItemLimit", slot)
          if ok and type(val) == "number" then limit = val end
          local entry = index[item.name]
          if not entry then
            entry = {}
            index[item.name] = entry
          end
          entry[#entry + 1] = {
            pack = packName,
            count = item.count,
            limit = limit,
          }
        end
      end
    end
  end  local moved = 0
  local toMessy = 0
  -- Walk the inbox and move each stack.
  for slot, item in pairs(contents) do
    if not isMarkerSlot(roles.inbox, slot) then
      local destName, destSlot = nil, nil
      -- 1. Try packs that already hold this item.
      --    orderPacks puts the pack with the fullest partial stack first.
      for _, candidate in ipairs(orderPacks(index[item.name])) do
        local s = findDestSlot(candidate.pack, item.name)
        if s then
          destName, destSlot = candidate.pack, s
          break
        end
      end
      -- 2. If nothing fit, try the messy pack.
      if not destName then
        local s = findDestSlot(roles.messy, item.name)
        if s then
          destName, destSlot = roles.messy, s
        end
      end
      -- 3. Still nothing -- log and skip.
      if not destName then
        printError(("  no room for %s anywhere"):format(item.name))
      else
        -- pushItems(toName, fromSlot, limit, toSlot)
        local ok, actual = pcall(inbox.pushItems,
          destName, slot, item.count, destSlot)
        if ok and actual then
          moved = moved + actual
          if destName == roles.messy then
            toMessy = toMessy + actual
          end
        else
          printError(("  push failed %s -> %s: %s"):format(
            item.name, destName, tostring(actual)))
        end
      end
    end
  end
  print(("Stored %d items (%d to messy)."):format(moved, toMessy))
end

-- packs
--  Dump the resolved roles plus every visible inventory.
local function cmdPacks()
  for _, role in ipairs({ "inbox", "outbox", "messy" }) do
    print(("%-8s %s"):format(role, roles[role] or "(missing)"))
  end
  print("")
  print("All inventories:")
  for _, name in ipairs(inventory.find()) do
    print("  " .. name)
  end
end

-- Prints the applicable commands for fetch/store 
local function printHelp()
  print("Commands:")
  print("  fetch [count] <item>  pull items into outbox (default 64)")
  print("  store                 move inbox into matching packs")
  print("  packs                 show resolved role packs")
  print("  help                  this message")
  print("  exit                  quit")
end

----------
-- MAIN --
----------

-- Shell arguement mode: 'storage_transfer [cmd]' runs once, then exits
local args = { ... }
if #args > 0 then
  local cmd = table.remove(args, 1)
  if cmd == "fetch" then
    cmdFetch(args)
  elseif cmd == "store" then
    cmdStore()
  elseif cmd == "packs" then
    cmdPacks()
  else
    printHelp()
  end
  return
end

-- Interactive mode: banner then a promp loop.
print("storage_transfer -- type 'help' for commands.")
for _, role in ipairs({ "inbox", "outbox", "messy" }) do
  print(("  %-7s %s"):format(role, roles[role] or "(missing)"))
end

while true do
  write("> ")
  local line = read()

  if not line or line == "exit" or line == "quit" then
    break
  end

  -- Split on whitespace.
  local words = {}
  for word in line:gmatch("%S+") do
    words[#words + 1] = word
  end

  local cmd = words[1]
  if cmd then
    table.remove(words, 1)

    if cmd == "fetch" then
      cmdFetch(words)
    elseif cmd == "store" then
      cmdStore()
    elseif cmd == "packs" then
      cmdPacks()
    elseif cmd == "help" then
      printHelp()
    else
      print("Unknown command: " .. cmd)
    end
  end
end
