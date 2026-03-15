-- BeeOS Mutation Preset: Meatballcraft
-- Forestry 5.8.2.426 + Gendustry 1.6.5.8 custom bees
-- Source: Forestry mc-1.12 BeeDefinition.java + meatball_bees.cfg
--
-- MagicBees 3.1.10 mutations not yet included (needs JAR decompilation).
-- MagicBees species still appear via getSpeciesList() API.

local preset = {}

preset.name = "Meatballcraft"
preset.version = 1

-- Mutation graph: { [resultSpecies] = { { parent1, parent2, chance }, ... } }
-- Chance normalized 0-1 (matches mutations.lua convention)
-- Display names match Plethora getSpeciesList() output
preset.mutations = {

  -- ==============================
  -- Forestry Base Mutations
  -- ==============================

  -- Common: all overworld hive bee combinations (C(6,2) = 15)
  ["Common"] = {
    { parent1 = "Forest",   parent2 = "Meadows",  chance = 0.15 },
    { parent1 = "Forest",   parent2 = "Modest",   chance = 0.15 },
    { parent1 = "Forest",   parent2 = "Tropical", chance = 0.15 },
    { parent1 = "Forest",   parent2 = "Wintry",   chance = 0.15 },
    { parent1 = "Forest",   parent2 = "Marshy",   chance = 0.15 },
    { parent1 = "Meadows",  parent2 = "Modest",   chance = 0.15 },
    { parent1 = "Meadows",  parent2 = "Tropical", chance = 0.15 },
    { parent1 = "Meadows",  parent2 = "Wintry",   chance = 0.15 },
    { parent1 = "Meadows",  parent2 = "Marshy",   chance = 0.15 },
    { parent1 = "Modest",   parent2 = "Tropical", chance = 0.15 },
    { parent1 = "Modest",   parent2 = "Wintry",   chance = 0.15 },
    { parent1 = "Modest",   parent2 = "Marshy",   chance = 0.15 },
    { parent1 = "Tropical", parent2 = "Wintry",   chance = 0.15 },
    { parent1 = "Tropical", parent2 = "Marshy",   chance = 0.15 },
    { parent1 = "Wintry",   parent2 = "Marshy",   chance = 0.15 },
  },

  -- Cultivated: Common + each overworld hive bee
  ["Cultivated"] = {
    { parent1 = "Common", parent2 = "Forest",   chance = 0.12 },
    { parent1 = "Common", parent2 = "Meadows",  chance = 0.12 },
    { parent1 = "Common", parent2 = "Modest",   chance = 0.12 },
    { parent1 = "Common", parent2 = "Tropical", chance = 0.12 },
    { parent1 = "Common", parent2 = "Wintry",   chance = 0.12 },
    { parent1 = "Common", parent2 = "Marshy",   chance = 0.12 },
  },

  -- Noble branch
  ["Noble"]    = { { parent1 = "Common", parent2 = "Cultivated", chance = 0.10 } },
  ["Majestic"] = { { parent1 = "Noble",  parent2 = "Cultivated", chance = 0.08 } },
  ["Imperial"] = { { parent1 = "Noble",  parent2 = "Majestic",   chance = 0.08 } },

  -- Industrious branch
  ["Diligent"]    = { { parent1 = "Common",   parent2 = "Cultivated", chance = 0.10 } },
  ["Unweary"]     = { { parent1 = "Diligent", parent2 = "Cultivated", chance = 0.08 } },
  ["Industrious"] = { { parent1 = "Diligent", parent2 = "Unweary",    chance = 0.08 } },

  -- Heroic branch
  ["Heroic"] = { { parent1 = "Steadfast", parent2 = "Valiant", chance = 0.06 } },

  -- Infernal branch (Nether biome required)
  ["Sinister"] = {
    { parent1 = "Cultivated", parent2 = "Modest",   chance = 0.60 },
    { parent1 = "Cultivated", parent2 = "Tropical", chance = 0.60 },
  },
  ["Fiendish"] = {
    { parent1 = "Sinister", parent2 = "Cultivated", chance = 0.40 },
    { parent1 = "Sinister", parent2 = "Modest",     chance = 0.40 },
    { parent1 = "Sinister", parent2 = "Tropical",   chance = 0.40 },
  },
  ["Demonic"] = { { parent1 = "Sinister", parent2 = "Fiendish", chance = 0.25 } },

  -- Austere branch (Hot/Hellish + Arid required)
  ["Frugal"] = {
    { parent1 = "Modest", parent2 = "Sinister", chance = 0.16 },
    { parent1 = "Modest", parent2 = "Fiendish", chance = 0.10 },
  },
  ["Austere"] = { { parent1 = "Modest", parent2 = "Frugal", chance = 0.08 } },

  -- Tropical branch
  ["Exotic"] = { { parent1 = "Austere", parent2 = "Tropical", chance = 0.12 } },
  ["Edenic"] = { { parent1 = "Exotic",  parent2 = "Tropical", chance = 0.08 } },

  -- End branch
  ["Spectral"]   = { { parent1 = "Hermitic", parent2 = "Ended", chance = 0.04 } },
  ["Phantasmal"] = { { parent1 = "Spectral", parent2 = "Ended", chance = 0.02 } },

  -- Frozen branch (Icy/Cold temperature required)
  ["Icy"]     = { { parent1 = "Industrious", parent2 = "Wintry", chance = 0.12 } },
  ["Glacial"] = { { parent1 = "Icy",         parent2 = "Wintry", chance = 0.08 } },

  -- Vengeful branch
  ["Vindictive"] = { { parent1 = "Monastic", parent2 = "Demonic",    chance = 0.04 } },
  ["Vengeful"] = {
    { parent1 = "Demonic",  parent2 = "Vindictive", chance = 0.08 },
    { parent1 = "Monastic", parent2 = "Vindictive", chance = 0.08 },
  },
  ["Avenging"] = { { parent1 = "Vengeful", parent2 = "Vindictive", chance = 0.04 } },

  -- Festive branch (date-restricted, secret)
  ["Leporine"] = { { parent1 = "Meadows",  parent2 = "Forest",  chance = 0.10 } },
  ["Merry"]    = { { parent1 = "Wintry",   parent2 = "Forest",  chance = 0.10 } },
  ["Tipsy"]    = { { parent1 = "Wintry",   parent2 = "Meadows", chance = 0.10 } },
  ["Tricky"]   = { { parent1 = "Sinister", parent2 = "Common",  chance = 0.10 } },

  -- Agrarian branch (Plains biome required)
  ["Rural"]    = { { parent1 = "Meadows",  parent2 = "Diligent",    chance = 0.12 } },
  ["Farmerly"] = { { parent1 = "Rural",    parent2 = "Unweary",     chance = 0.10 } },
  ["Agrarian"] = { { parent1 = "Farmerly", parent2 = "Industrious", chance = 0.06 } },

  -- Boggy branch (Warm + Damp required)
  ["Miry"]  = { { parent1 = "Marshy", parent2 = "Noble", chance = 0.15 } },
  ["Boggy"] = { { parent1 = "Marshy", parent2 = "Miry",  chance = 0.09 } },

  -- Monastic branch
  ["Secluded"] = { { parent1 = "Monastic", parent2 = "Austere",  chance = 0.12 } },
  ["Hermitic"] = { { parent1 = "Monastic", parent2 = "Secluded", chance = 0.08 } },

  -- ==============================
  -- Meatballcraft Custom Bees
  -- (from gendustry meatball_bees.cfg)
  -- ==============================

  ["Meatball"] = {
    { parent1 = "Industrious", parent2 = "Diligent", chance = 0.10 },
    { parent1 = "Industrious", parent2 = "Common",   chance = 0.10 },
  },
  -- Springwater, Gorgon, Formic: no breeding mutations
  -- (obtained via dungeon drops / Sacred Cinders Super Apiary)
}

-- Fallback species list (used only when getSpeciesList API unavailable)
-- Normally the API provides all 386+ species including MagicBees
preset.species = {
  -- Base hive species (not bred, found in world)
  "Forest", "Meadows", "Modest", "Tropical", "Wintry", "Marshy",
  "Steadfast", "Valiant", "Ended", "Monastic",
  -- Forestry bred species
  "Common", "Cultivated",
  "Noble", "Majestic", "Imperial",
  "Diligent", "Unweary", "Industrious",
  "Heroic",
  "Sinister", "Fiendish", "Demonic",
  "Frugal", "Austere",
  "Exotic", "Edenic",
  "Spectral", "Phantasmal",
  "Icy", "Glacial",
  "Vindictive", "Vengeful", "Avenging",
  "Leporine", "Merry", "Tipsy", "Tricky",
  "Rural", "Farmerly", "Agrarian",
  "Miry", "Boggy",
  "Secluded", "Hermitic",
  -- Meatballcraft custom
  "Meatball", "Spring Water", "Gorgon", "Formic",
}

return preset
