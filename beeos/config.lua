-- BeeOS Configuration
-- Edit these values to match your physical setup.
-- Peripheral names are discovered by running: tools/scan

local config = {}

-- === Layer Toggles ===
-- Which layers are enabled on startup
config.layers = {
  tracker = true,     -- Layer 0: Passive species tracking (always recommended)
  apiary = false,     -- Layer 1: Apiary management
  sampler = false,    -- Layer 2: Sample & template management
  discovery = false,  -- Layer 3: Auto-discovery via Mutatron
  surplus = false,    -- Layer 4: Surplus drone management
}

-- === Timing (seconds) ===
config.timing = {
  trackerInterval = 15,   -- How often to scan inventories
  apiaryInterval = 5,     -- How often to check apiaries
  samplerInterval = 5,    -- How often to check sampler status
  discoveryInterval = 10, -- How often to check discovery progress
}

-- === Thresholds ===
config.thresholds = {
  minSamplesPerSpecies = 3,   -- Minimum gene samples to keep per species
  minDronesPerSpecies = 2,    -- Minimum drones to keep per species
  maxDronesPerSpecies = 64,   -- Surplus drones above this go to DNA Extractor
  minLabware = 8,             -- Request more labware from AE2 when below this
  minBlankTemplates = 4,      -- Request more blank templates when below this
}

-- === Named Chests ===
-- Set these to the peripheral names of your buffer chests.
-- Run tools/scan to discover names.
config.chests = {
  droneBuffer = nil,      -- "minecraft:chest_0"
  sampleStorage = nil,    -- "minecraft:chest_1"
  templateOutput = nil,   -- "minecraft:chest_2" (AE2 import bus attached)
  supplyInput = nil,      -- "minecraft:chest_3" (AE2 export bus: labware, blanks, rocky bees)
  princessStorage = nil,  -- "minecraft:chest_4" (princess overflow when apiaries full)
  export = nil,           -- "minecraft:chest_5" (AE2 import bus: combs, surplus, waste)
  traitTemplates = nil,   -- "minecraft:chest_6" (pre-stocked trait templates for imprinter)

  -- Legacy aliases (still work if export is nil)
  productOutput = nil,
  surplusOutput = nil,
}

-- === Trait Imprinting ===
-- Ideal traits to imprint on bees before they enter apiaries.
-- Set a trait to true to require it, false/nil to skip.
config.traits = {
  caveDwelling = true,
  neverSleeps = true,
  toleratesRain = true,
  -- temperatureTolerance and humidityTolerance need Phase 0 verification
  -- of exact string format from getItemMeta
}

-- === Machine Overrides ===
-- By default, BeeOS auto-discovers machines via network scan.
-- Set specific names here to override auto-discovery, or leave nil.
config.machines = {
  samplers = nil,       -- e.g. { "gendustry:sampler_0" }
  imprinters = nil,     -- e.g. { "gendustry:imprinter_0" }
  mutatrons = nil,      -- e.g. { "gendustry:mutatron_0" }
  dnaExtractors = nil,  -- e.g. { "gendustry:extractor_0" }
  analyzer = nil,       -- e.g. "forestry:analyzer_0" (for mutation queries)
}

-- === Apiary Assignments ===
-- Map apiary peripheral names to species they should breed.
-- If nil, BeeOS manages assignments automatically.
-- Example: { ["gendustry:industrial_apiary_0"] = "Forest" }
config.apiaryAssignments = nil

-- === Discovery ===
config.discovery = {
  -- Species to prioritize in auto-discovery (bred first)
  prioritySpecies = {},
  -- Species to skip (never try to breed these)
  skipSpecies = {},
  -- Max concurrent mutation attempts
  maxConcurrentMutations = 1,
}

-- === Display ===
config.display = {
  monitorSide = nil,  -- nil = auto-detect, or "left", "right", "top", etc.
  refreshRate = 2,    -- Monitor refresh interval in seconds
}

-- === Crafting Turtle ===
config.turtle = {
  name = nil,  -- Peripheral name of crafting turtle on network, nil = auto-detect
}

return config
