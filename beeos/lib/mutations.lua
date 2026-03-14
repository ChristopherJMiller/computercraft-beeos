-- BeeOS Mutation Graph
-- Queries the Forestry mutation registry via Plethora and provides
-- pathfinding through the bee breeding tree.

local network = require("lib.network")

local mutations = {}

-- Mutation graph: adjacency list
-- { [resultSpecies] = { { parent1, parent2, chance }, ... } }
mutations.graph = {}

-- All known species
mutations.allSpecies = {}

-- Reverse map: which results can a species be part of?
-- { [speciesName] = { resultSpecies1, resultSpecies2, ... } }
mutations.participatesIn = {}

--- Query the mutation list from a Forestry Analyzer peripheral.
-- @param analyzerName Peripheral name (or nil to auto-detect)
-- @return boolean success
function mutations.load(analyzerName)
  local analyzer
  if analyzerName then
    analyzer = peripheral.wrap(analyzerName)
  else
    -- Auto-detect: find any peripheral with getMutationsList
    local _
    _, analyzer = network.findWithMethod("getMutationsList")
  end

  if not analyzer or not analyzer.getMutationsList then
    return false, "No analyzer with getMutationsList found"
  end

  -- Query all bee mutations
  local ok, mutList = pcall(analyzer.getMutationsList, "rootBees")
  if not ok then
    return false, "getMutationsList failed: " .. tostring(mutList)
  end

  -- Also get all species
  if analyzer.getSpeciesList then
    local ok2, specList = pcall(analyzer.getSpeciesList, "rootBees")
    if ok2 and specList then
      mutations.allSpecies = {}
      for i = 1, #specList do
        local species = specList[i]
        -- Species entries may be tables or strings depending on Plethora version
        local name = type(species) == "table" and (species.displayName or species.name) or tostring(species)
        mutations.allSpecies[#mutations.allSpecies + 1] = name
      end
      table.sort(mutations.allSpecies)
    end
  end

  -- Build graph
  mutations.graph = {}
  mutations.participatesIn = {}

  for _, mut in ipairs(mutList) do
    -- Mutation entry structure (verify with Phase 0):
    -- { allele1 = "Species1", allele2 = "Species2", result = "ResultSpecies", chance = 0.15 }
    local parent1 = mut.allele1 or mut.parent1 or mut[1]
    local parent2 = mut.allele2 or mut.parent2 or mut[2]
    local result = mut.result or mut[3]
    local chance = mut.chance or mut[4] or 0

    -- Normalize: extract display names if they're tables
    if type(parent1) == "table" then parent1 = parent1.displayName or parent1.name end
    if type(parent2) == "table" then parent2 = parent2.displayName or parent2.name end
    if type(result) == "table" then result = result.displayName or result.name end

    if parent1 and parent2 and result then
      if not mutations.graph[result] then
        mutations.graph[result] = {}
      end
      mutations.graph[result][#mutations.graph[result] + 1] = {
        parent1 = parent1,
        parent2 = parent2,
        chance = chance,
      }

      -- Build reverse map
      for _, parent in ipairs({ parent1, parent2 }) do
        if not mutations.participatesIn[parent] then
          mutations.participatesIn[parent] = {}
        end
        -- Avoid duplicates
        local found = false
        for _, r in ipairs(mutations.participatesIn[parent]) do
          if r == result then found = true; break end
        end
        if not found then
          mutations.participatesIn[parent][#mutations.participatesIn[parent] + 1] = result
        end
      end
    end
  end

  return true
end

--- Find the best mutation path to produce a target species.
-- Uses BFS from known (discovered) species.
-- @param targetSpecies Species name to breed
-- @param knownSpecies Set of species we already have { [name] = true }
-- @return List of breeding steps, or nil if unreachable
--   Each step: { parent1, parent2, result, chance }
function mutations.findPath(targetSpecies, knownSpecies)
  if knownSpecies[targetSpecies] then
    return {}  -- Already known
  end

  -- BFS: find mutation steps needed
  -- Each node is a species, edges are "can be produced from known parents"
  local visited = {}
  local parent = {}  -- backtrack: parent[species] = { step that produces it }

  -- Start: all known species
  for species in pairs(knownSpecies) do
    visited[species] = true
  end

  -- Find all species reachable in one step from known
  local function expandFrontier()
    local newSpecies = {}
    for result, mutationList in pairs(mutations.graph) do
      if not visited[result] then
        for _, mut in ipairs(mutationList) do
          if visited[mut.parent1] and visited[mut.parent2] then
            visited[result] = true
            parent[result] = {
              parent1 = mut.parent1,
              parent2 = mut.parent2,
              result = result,
              chance = mut.chance,
            }
            newSpecies[#newSpecies + 1] = result
            break  -- Found one path to this species, that's enough
          end
        end
      end
    end
    return newSpecies
  end

  -- BFS layers
  local maxDepth = 50  -- Safety limit
  for _ = 1, maxDepth do
    local frontier = expandFrontier()
    if #frontier == 0 then
      break  -- No more species reachable
    end

    if visited[targetSpecies] then
      -- Found a path! Backtrack to build the step list.
      local path = {}
      local current = targetSpecies
      while parent[current] do
        table.insert(path, 1, parent[current])
        -- Mark the parents as "need to discover" if they aren't in original known set
        local step = parent[current]
        if not knownSpecies[step.parent1] then
          current = step.parent1
        elseif not knownSpecies[step.parent2] then
          current = step.parent2
        else
          break  -- Both parents are known, we're done
        end
      end
      return path
    end
  end

  return nil  -- Unreachable
end

--- Get the next best species to discover via auto-discovery.
-- Picks the undiscovered species closest (fewest steps) to known species.
-- @param knownSpecies Set of known species { [name] = true }
-- @param skipSpecies Set of species to skip { [name] = true }
-- @param prioritySpecies Ordered list of priority species names
-- @return species name, mutation step table, or nil
function mutations.getNextTarget(knownSpecies, skipSpecies, prioritySpecies)
  skipSpecies = skipSpecies or {}

  -- Check priority species first
  if prioritySpecies then
    for _, species in ipairs(prioritySpecies) do
      if not knownSpecies[species] and not skipSpecies[species] then
        -- Check if reachable in one step
        local mutList = mutations.graph[species]
        if mutList then
          for _, mut in ipairs(mutList) do
            if knownSpecies[mut.parent1] and knownSpecies[mut.parent2] then
              return species, mut
            end
          end
        end
      end
    end
  end

  -- Find all species reachable in one step (prefer high chance mutations)
  local candidates = {}
  for result, mutList in pairs(mutations.graph) do
    if not knownSpecies[result] and not skipSpecies[result] then
      for _, mut in ipairs(mutList) do
        if knownSpecies[mut.parent1] and knownSpecies[mut.parent2] then
          candidates[#candidates + 1] = {
            species = result,
            mutation = mut,
          }
          break
        end
      end
    end
  end

  if #candidates == 0 then
    return nil  -- Nothing reachable
  end

  -- Sort by mutation chance (highest first)
  table.sort(candidates, function(a, b)
    return (a.mutation.chance or 0) > (b.mutation.chance or 0)
  end)

  return candidates[1].species, candidates[1].mutation
end

--- Get total counts for display.
-- @param knownSpecies Set of known species
-- @return discovered count, total count, reachable count
function mutations.getCounts(knownSpecies)
  local discovered = 0
  for _ in pairs(knownSpecies) do
    discovered = discovered + 1
  end

  local total = 0
  for _ in pairs(mutations.graph) do
    total = total + 1
  end
  -- Add species that appear only as parents (base species)
  local allSpeciesSet = {}
  for result in pairs(mutations.graph) do
    allSpeciesSet[result] = true
  end
  for _, mutList in pairs(mutations.graph) do
    for _, mut in ipairs(mutList) do
      allSpeciesSet[mut.parent1] = true
      allSpeciesSet[mut.parent2] = true
    end
  end
  total = 0
  for _ in pairs(allSpeciesSet) do total = total + 1 end

  -- Count reachable (could be discovered in one step)
  local reachable = 0
  for result, mutList in pairs(mutations.graph) do
    if not knownSpecies[result] then
      for _, mut in ipairs(mutList) do
        if knownSpecies[mut.parent1] and knownSpecies[mut.parent2] then
          reachable = reachable + 1
          break
        end
      end
    end
  end

  return discovered, total, reachable
end

return mutations
