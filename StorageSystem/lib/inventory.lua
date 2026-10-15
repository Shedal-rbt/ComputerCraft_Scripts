--lib/inventory.lua
--
-- Shared helpers for finding and scanning inventories.
--
local inventory = {}
--
local SIDE_NAMES = {
  left = true, right = true, top = true,
  bottom = true, front = true, back = true,
}

--Returns true if 'name' looks like an inventory peripheral.
function inventory.isInventory(name)
  -- if SIDE_NAMES[name] then return false end
  local methods = peripheral.getMethods(name) or {}
  local hasList, hasSize = false, false
  -- Go through methods, see if it has size/list
  for _, m in ipairs(methods) do
    if m == "list" then hasList = true end
    if m == "size" then hasSize = true end
  end
  return hasList and hasSize
end

  -- Returns contents or nil
function inventory.listContents(name)
  local ok, contents = pcall(peripheral.call, name, "list")
  if ok and contents then return contents end
  return nil
end

  --Builds a unique string that describes an inventories contents.
  -- 2 inventories with the same fingerprint are the same block. 
function inventory.fingerprint(name)
  local contents = inventory.listContents(name)
  if not contents then return nil end

  local parts = {}
  for slot, item in pairs(contents) do
      parts[#parts + 1] = slot .. ":" .. item.name .. "=" .. item.count
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

  -- returns an array of names for every unqiue inventory on the network
function inventory.find()
  local names, seen = {}, {}
  for _, name in ipairs(peripheral.getNames()) do 
    if inventory.isInventory(name) then
      local fp = inventory.fingerprint(name)
      -- If we cant Fingerprint, better to count it. Better to double/triple count than not count at all.
      if not fp or fp == "" then
        names[#names + 1] = name
      elseif not seen[fp] then
        seen[fp] = true
        names[#names + 1] = name
      end
    end
  end
  return names
end

-- Totals every item across every unique inventory, returns 2 values
  -- Totals -- table: item name -> {count = n}
  -- invCount -- how many inventories had atleast 1 item
function inventory.scan()
  local totals = {}
  local invCount = 0
  for _, name in ipairs(inventory.find()) do
    local contents = inventory.listContents(name)
    if contents then
      local used = false
      for _, item in pairs(contents) do
        used = true
        local e = totals[item.name]
        if e then 
          e.count = e.count + item.count
        else
            totals[item.name] = {count = item.count}
        end
      end
      if used then invCount = invCount + 1 end
    end
  end
  return totals, invCount
end

  --totals all items in 1 specific inventory by peripheral name
function inventory.scanOne(name)
  local contents = inventory.listContents(name)
  return contents or {}
end

-- Returns { [PeripheralName] = ContentsTable} for
-- each unique inventory.
-- ContentsTable is what list() returns: slot->name, count }
function inventory.scanEach()
  local out = {}
  for _, name in ipairs(inventory.find()) do
    local contents = inventory.listContents(name)
    if contents then
      out[name] = contents
    end
  end
  return out
end

-- Splits an item into its mod name and item name
-- Returns mod name and item name seperately, if no mod name detected, returns "" and original string. 
function inventory.splitName(full)
  local mod, name = full:match("^([^:]+):(.+)$")
  if mod then
    return mod, name
  end
  return "", full
end

-- does this inventory's contents match the given signature?
-- signature is an array like {{name = "..."},{name = "..."},{name = "..."}, ... }
-- missing signature means "any" for that slot.
function inventory.matchSignature(contents, signature)
  for i, expected in ipairs(signature) do
    local item = contents[i]
    if not item then return false end
    if expected.name and item.name ~= expected.name then return false end
    if expected.count and item.count < expected.count then return false end
  end
  return true
end

function inventory.resolveRoles(roles)
  local resolved = {}
  for _, name in ipairs(inventory.find()) do
    local contents = inventory.listContents(name)
    if contents then
      for role, signature in pairs(roles) do 
        if inventory.matchSignature(contents, signature) then
          resolved[role] = name]
        end
      end
    end
  end
  return resolved
end
return inventory
