-- BeeOS Layer 1: Apiary Manager
-- Monitors Industrial Apiaries, auto-restarts them, routes output.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")
local imprinter = require("lib.imprinter")
local state = require("lib.state")

local apiary = {}

-- Apiary status tracking
apiary.status = {}
-- { [name] = { species, state, lastCheck, products } }

--- Check if an apiary is assigned to breed mode.
-- @param name Peripheral name
-- @param config BeeOS config
-- @return boolean
function apiary.isBreedMode(name, config)
  return config.apiaryAssignments
    and config.apiaryAssignments[name] == "breed"
end

--- Check a single apiary and manage it.
-- @param name Peripheral name of the apiary
-- @param p Wrapped peripheral
-- @param config BeeOS config table
-- @param machines Table from network.scan()
-- @return Status table for this apiary
function apiary.check(name, p, config, machines)
  local status = apiary.status[name] or {
    species = nil,
    state = "unknown",
    lastCheck = 0,
  }

  local breedMode = apiary.isBreedMode(name, config)

  -- Check for active queen
  local queen = nil
  if p.getQueen then
    queen = p.getQueen()
  end

  if queen then
    local species = "Unknown"
    if queen.individual and queen.individual.genome then
      species = queen.individual.genome.active.species.displayName or "Unknown"
    end
    status.species = species

    if breedMode then
      -- Breed mode: extract queen immediately for trait imprinting
      tracker.addLog("Breed apiary: extracting queen (" .. species .. ")")
      apiary.extractInputs(name, p, config)
      apiary.extractOutput(name, p, config)
      status.state = "idle"

      local restarted = apiary.tryRestart(name, p, config, machines)
      if restarted then
        status.state = "restarting"
        tracker.addLog("Restarted breed apiary: " .. name)
      end
    else
      status.state = "running"
    end
  else
    -- No queen — apiary needs attention
    status.state = "idle"

    -- Extract all output items
    apiary.extractOutput(name, p, config)

    -- Try to restart with available princess + drone
    local restarted = apiary.tryRestart(name, p, config, machines)
    if restarted then
      status.state = "restarting"
      tracker.addLog("Restarted apiary: " .. name)
    end
  end

  status.lastCheck = os.clock()
  apiary.status[name] = status
  return status
end

--- Extract output items from an apiary.
-- Routes products to export, drones to buffer, princesses to princessStorage or buffer.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
function apiary.extractOutput(name, p, config)
  local size = p.size and p.size() or 0

  -- Industrial Apiary layout (verify with tools/slots):
  -- Slots 1-2: princess/drone input
  -- Slots 3-6: upgrades
  -- Slots 7+: output
  -- We scan all slots and only extract from output area
  local outputStart = 7  -- Adjust after Phase 0 testing

  for slot = outputStart, size do
    local meta = p.getItemMeta and p.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      if itemName:find("bee_princess") or itemName:find("bee_queen") then
        -- Princess → princessStorage only (don't mix with drone buffer)
        if inventory.first(config.chests.princessStorage) then
          inventory.moveTo(name, slot, config.chests.princessStorage)
        end

      elseif itemName:find("bee_drone") then
        -- Drones go to processing buffer
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(name, slot, config.chests.droneBuffer)
        end

      else
        -- Products (honeycombs, etc.) go to export chest
        local exportChests = inventory.getExportChests(config)
        if inventory.first(exportChests) then
          inventory.moveTo(name, slot, exportChests)
        end
      end
    end
  end
end

--- Extract bees from apiary input slots (for shutdown/recovery/breed mode).
-- Only extracts from slots 1-2 (princess/queen and drone inputs).
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
function apiary.extractInputs(name, p, config)
  for slot = 1, 2 do
    local meta = p.getItemMeta and p.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""
      if itemName:find("bee_princess") or itemName:find("bee_queen") then
        -- Route to princessStorage (trait imprinter will pick up from there)
        if inventory.first(config.chests.princessStorage) then
          inventory.moveTo(name, slot, config.chests.princessStorage)
        end
      elseif itemName:find("bee_drone") then
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(name, slot, config.chests.droneBuffer)
        end
      end
    end
  end
end

--- Try to restart an apiary with a princess and drone.
-- Breed-mode apiaries pull from princessStorage without trait checks.
-- Production apiaries pull from apiaryReady first (pre-imprinted),
-- falling back to princessStorage with trait checks.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
-- @param machines Table from network.scan()
-- @return boolean True if successfully restarted
function apiary.tryRestart(name, p, config, machines)
  local breedMode = apiary.isBreedMode(name, config)

  -- Check what species this apiary should breed
  local targetSpecies = nil
  if config.apiaryAssignments and not breedMode then
    targetSpecies = config.apiaryAssignments[name]
  end

  -- Check bootstrap queue for priority species (when no assignment set)
  local bootstrapTarget = nil
  if not targetSpecies and not breedMode then
    local queue = state.load("bootstrap_queue", {})
    bootstrapTarget = next(queue)
  end

  if breedMode then
    return apiary.tryRestartBreed(name, config)
  end

  -- Production mode: try apiaryReady first, then fall back to princessStorage
  local readyChests = config.chests.apiaryReady
  if readyChests then
    -- Try queens from apiaryReady (no trait check needed)
    local wantSpecies = targetSpecies or bootstrapTarget
    local qSlot, qSrc = apiary.findQueen(config, wantSpecies, readyChests)
    if not qSlot then
      qSlot, qSrc = apiary.findQueen(config, nil, readyChests)
    end
    if qSlot then
      local moved = inventory.move(qSrc, qSlot, name, 1, 1)
      if moved > 0 then
        tracker.addLog("Queen placed from apiaryReady: " .. name)
        return true
      end
    end

    -- Try princess+drone from apiaryReady (no trait check needed)
    local pSlot, pSrc = apiary.findPrincess(config,
      wantSpecies, readyChests)
    if pSlot then
      local droneSlot, droneSrc = apiary.findDrone(config, wantSpecies)
      if not droneSlot then
        droneSlot, droneSrc = apiary.findDrone(config, nil)
      end
      if droneSlot then
        local movedP = inventory.move(pSrc, pSlot, name, 1, 1)
        if movedP > 0 then
          local movedD = inventory.move(droneSrc, droneSlot, name, 2, 1)
          if movedD > 0 then
            tracker.addLog("Princess+drone from apiaryReady: " .. name)
            return true
          end
        end
      end
    end
  end

  -- Fallback: princessStorage with trait checks (original behavior)
  -- Try queens first
  local queenSpecies = targetSpecies or bootstrapTarget
  local queenSlot, queenSource = apiary.findQueen(config, queenSpecies)
  if not queenSlot then
    queenSlot, queenSource = apiary.findQueen(config, nil)
  end
  if queenSlot then
    local qPeri = peripheral.wrap(queenSource)
    if qPeri then
      local queenInfo = bee.inspect(qPeri, queenSlot)
      if queenInfo and imprinter.needsImprinting(queenInfo, config) then
        imprinter.sendToImprinter(queenSource, queenSlot, machines, config)
        return false
      end
    end

    local movedQueen = inventory.move(queenSource, queenSlot, name, 1, 1)
    if movedQueen > 0 then
      tracker.addLog("Queen placed in apiary: " .. name)
      return true
    end
  end

  -- Fall through to princess+drone logic
  if not inventory.first(config.chests.droneBuffer) then return false end

  local princessSlot, princessSource = apiary.findPrincess(config,
    targetSpecies or bootstrapTarget)
  if not princessSlot then return false end

  local sourcePeri = peripheral.wrap(princessSource)
  if not sourcePeri then return false end

  local princessInfo = bee.inspect(sourcePeri, princessSlot)
  if princessInfo and imprinter.needsImprinting(princessInfo, config) then
    imprinter.sendToImprinter(princessSource, princessSlot, machines, config)
    return false
  end

  local wantSpecies = targetSpecies or (princessInfo and princessInfo.species)
  local droneSlot, droneSource = apiary.findDrone(config, wantSpecies, machines)
  if not droneSlot then return false end

  local movedPrincess = inventory.move(princessSource, princessSlot, name, 1, 1)
  if movedPrincess > 0 then
    local movedDrone = inventory.move(droneSource, droneSlot, name, 2, 1)
    if movedDrone > 0 then
      return true
    end
  end

  return false
end

--- Try to restart a breed-mode apiary.
-- Grabs any princess + any drone from storage, no trait checks.
-- @param name Peripheral name
-- @param config BeeOS config
-- @return boolean True if successfully restarted
function apiary.tryRestartBreed(name, config)
  if not inventory.first(config.chests.droneBuffer) then return false end

  local princessSlot, princessSource = apiary.findPrincess(config, nil)
  if not princessSlot then return false end

  local droneSlot, droneSource = apiary.findDrone(config, nil)
  if not droneSlot then return false end

  local movedPrincess = inventory.move(princessSource, princessSlot, name, 1, 1)
  if movedPrincess > 0 then
    local movedDrone = inventory.move(droneSource, droneSlot, name, 2, 1)
    if movedDrone > 0 then
      tracker.addLog("Breed apiary loaded: " .. name)
      return true
    end
  end

  return false
end

--- Find a drone in droneBuffer.
-- Optionally checks traits and sends to imprinter if needed.
-- @param config BeeOS config
-- @param wantSpecies Optional species filter
-- @param machines Optional machines table (for imprinter fallback)
-- @return slot, sourceName or nil, nil
function apiary.findDrone(config, wantSpecies, machines)
  local droneMatches = inventory.findAcross(config.chests.droneBuffer, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  for _, match in ipairs(droneMatches) do
    -- findAcross already confirmed bee_drone in name; skip redundant isDrone check
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri then
      local info = bee.inspect(bufPeri, match.slot)
      if info and (not wantSpecies or info.species == wantSpecies) then
        if machines and imprinter.needsImprinting(info, config) then
          imprinter.sendToImprinter(match.source, match.slot,
            machines, config)
        else
          return match.slot, match.source
        end
      end
    end
  end

  return nil, nil
end

--- Find a princess in storage.
-- @param config BeeOS config
-- @param targetSpecies Optional species filter
-- @param chests Optional chest config override (defaults to princessStorage)
-- @return slot, sourceName or nil, nil
function apiary.findPrincess(config, targetSpecies, chests)
  local sources = inventory.normalize(chests or config.chests.princessStorage)

  for _, sourceName in ipairs(sources) do
    local peri = peripheral.wrap(sourceName)
    if peri then
      local size = peri.size and peri.size() or 0
      for slot = 1, size do
        if bee.isPrincess(peri, slot) then
          if targetSpecies then
            local info = bee.inspect(peri, slot)
            if info and info.species == targetSpecies then
              return slot, sourceName
            end
          else
            return slot, sourceName
          end
        end
      end
    end
  end

  return nil, nil
end

--- Find a queen in storage.
-- Queens can be placed directly in an apiary without a drone.
-- @param config BeeOS config
-- @param targetSpecies Optional species filter
-- @param chests Optional chest config override (defaults to princessStorage)
-- @return slot, sourceName or nil, nil
function apiary.findQueen(config, targetSpecies, chests)
  local sources = inventory.normalize(chests or config.chests.princessStorage)
  for _, sourceName in ipairs(sources) do
    local peri = peripheral.wrap(sourceName)
    if peri then
      local size = peri.size and peri.size() or 0
      for slot = 1, size do
        if bee.isQueen(peri, slot) then
          if targetSpecies then
            local info = bee.inspect(peri, slot)
            if info and info.species == targetSpecies then
              return slot, sourceName
            end
          else
            return slot, sourceName
          end
        end
      end
    end
  end
  return nil, nil
end

--- Get a list of all apiary statuses for display.
-- @return List of { name, species, state }
function apiary.getStatuses()
  local list = {}
  for name, status in pairs(apiary.status) do
    list[#list + 1] = {
      name = name,
      species = status.species or "None",
      state = status.state,
    }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

return apiary
