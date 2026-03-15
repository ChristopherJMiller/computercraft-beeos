# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

BeeOS is a ComputerCraft (CC:Tweaked 1.89.2) bee automation system for the Meatballcraft modpack (Minecraft 1.12.2). It automates Forestry/Gendustry bee breeding, genetic sampling, template crafting, and species discovery using Plethora peripherals and wired networking.

Key mods: Plethora 1.2.3, Forestry 5.8.2, Gendustry 1.6.5.8, MagicBees 3.1.10.

## Development Environment

```bash
nixs                                    # Enter dev shell (alias for nix-shell)
nix develop -c luacheck beeos/          # Run a command via the flake without entering the shell
luacheck beeos/                         # Lint all Lua files (must pass with 0 warnings)
```

The Nix flake provides lua5.1, luacheck, python3, nodejs_22, gh, and jq. Target runtime is Lua 5.1 (CC:Tweaked). The `.luacheckrc` declares all CC:Tweaked globals (`peripheral`, `fs`, `http`, `term`, `turtle`, `sleep`, etc.).

There are no unit tests. Code is verified by running in-game on CC computers.

## Architecture

All Lua source lives in `beeos/`. The system runs on an Advanced Computer connected to peripherals via wired modems.

### Entry Points
- `beeos.lua` — Main orchestrator. Boots, scans the network, then runs all layers in parallel via `parallel.waitForAny()`. Also handles terminal commands and monitor touch events.
- `startup.lua` — Auto-start shim that calls `shell.run("beeos")`.
- `install.lua` — One-shot installer downloaded via `wget run`. Bootstraps `lib/updater.lua` first, then downloads everything else.
- `turtle/crafter.lua` — Runs on a separate Crafting Turtle. Polls its inventory and shapeless-crafts gene sample + blank template into filled templates.

### Layer System
The system has 6 toggleable layers that run as parallel coroutines:

| Layer | Module | Purpose |
|-------|--------|---------|
| 0 | `lib/tracker.lua` | Read-only inventory scanner. Builds species catalog (drones, princesses, samples, templates). |
| 1 | `lib/apiary.lua` | Manages industrial apiaries: loads bees, collects products. Also runs `lib/imprinter.lua` (trait imprinting) and `lib/analyzer.lua`. |
| 2 | `lib/sampler.lua` | Routes drones to Genetic Sampler, duplicates samples via Transposer, crafts templates via turtle. |
| 3 | `lib/discovery.lua` | Auto-breeds undiscovered species using mutation graph (BFS pathfinding). State machine: idle → preparing → imprinting → mutating. |
| 4 | `lib/surplus.lua` | Routes excess drones to DNA Extractor. |
| 5 | `lib/trait_export.lua` | Exports non-species gene samples to AE2. |

### Core Libraries
- `lib/bee.lua` — Parses Plethora `getItemMeta()` into clean bee/sample/template structs. Normalizes Gendustry internal species names.
- `lib/network.lua` — Auto-categorizes peripherals by pattern matching (apiaries, samplers, chests, etc.).
- `lib/inventory.lua` — Item movement via `pushItems`/`pullItems`. Supports multi-chest arrays and predicate-based search.
- `lib/mutations.lua` — Loads mutation graph from Forestry API or static preset (`data/presets/meatballcraft.lua`). BFS pathfinding for breeding paths.
- `lib/state.lua` — Persistent key-value store using `textutils.serialise` to `data/*.dat` files.
- `lib/display.lua` — Monitor rendering with tabbed UI and touch interaction.
- `lib/updater.lua` — OTA update from GitHub. Contains the canonical file manifest.

### Configuration
- `config.lua` — Default config (layer toggles, timing, thresholds, peripheral names). Not overwritten by updates.
- Runtime config overrides are persisted via `state.save("config_overrides", ...)` and merged at boot.
- Peripherals are assigned via `config.chests.*` and `config.machines.*`, or auto-detected by `lib/network.lua`.

### Data Flow
No AE2 bridge mod — BeeOS moves items between buffer chests that have AE2 import/export buses attached. Config values like `chests.droneBuffer` can be a single string or an array of peripheral names for multi-chest setups.

### Gendustry Machine Slots (1-indexed for CC)
- **Imprinter**: 1=template, 2=labware, 3=bee input, 4=output
- **Mutatron**: 1=parent1, 2=parent2, 3=output, 4=labware
- **Transposer**: 1=blank sample, 3=source sample (not consumed), 4=output copy
- **Sampler**: auto-detected slot layout

## Key Conventions

- All Lua files must pass `luacheck` with 0 warnings. Max line length is 120 chars.
- Species names are normalized via `bee.normalizeSpecies()` which strips mod prefixes like `gendustry.bees.species.`.
- Template species identification uses nbtHash lookup (persisted in `data/template_hashes.dat`), not displayName.
- The file manifest in `lib/updater.lua` must be updated when adding/removing files.
- Config values for chests/machines may be nil, a string, or a table of strings — use `inventory.normalize()` and `inventory.first()` to handle all cases.

## Verifying In-Game Source

The in-game CC computers pull source from GitHub via the updater. To check what's actually running in-game against the repo, shallow-clone into `/tmp`:

```bash
git clone --depth 1 https://github.com/ChristopherJMiller/computercraft-beeos.git /tmp/beeos
diff -r beeos/ /tmp/beeos/beeos/
```

This is useful for confirming the updater deployed correctly or spotting local config drift.

To check mod source code (APIs, slot layouts, peripheral methods), shallow-clone the relevant mod repos into `/tmp`:

```bash
git clone --depth 1 https://github.com/SquidDev-CC/CC-Tweaked.git /tmp/cc-tweaked
git clone --depth 1 https://github.com/SquidDev-CC/plethora.git /tmp/plethora
git clone --depth 1 https://github.com/bdew-minecraft/gendustry.git /tmp/gendustry
git clone --depth 1 https://github.com/ForestryMC/ForestryMC.git /tmp/forestry
git clone --depth 1 https://github.com/MagicBees/MagicBees.git /tmp/magicbees
```

This is the preferred way to verify peripheral method signatures, machine slot indices, or internal naming conventions against actual mod source.

## Docs Site

A React/Vite docs site lives in `docs/`. Built and deployed to GitHub Pages via `.github/workflows/deploy.yml`.

```bash
cd docs && npm ci && npm run build    # Build
cd docs && npx vite                   # Dev server
```
