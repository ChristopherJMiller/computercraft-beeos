const features = [
  'Reads full bee genetics via Plethora (species, traits, active/inactive alleles)',
  'Queries the entire mutation graph at runtime — no hardcoded data',
  'Auto-discovers custom modpack bees (MagicBees, Gendustry, pack-specific)',
  'BFS pathfinding through the mutation tree for optimal breeding order',
  'Touch-screen monitor with species grid, apiary status, discovery progress',
  'Toggle layers on/off independently via monitor touch or terminal commands',
  'Surplus drones automatically routed to DNA Extractor',
  'Crafts genetic templates via crafting turtle (no per-species AE2 patterns needed)',
  'Persistent state survives computer reboots',
  'Error recovery: crashed layers auto-restart without taking down the system',
]

const mods = [
  'CC:Tweaked',
  'Plethora',
  'Forestry',
  'Gendustry',
  'MagicBees',
  'Applied Energistics 2',
  'Binnie Mods',
]

export default function Features() {
  return (
    <>
      <section>
        <h2># Features</h2>
        <ul className="features">
          {features.map((f) => (
            <li key={f}>{f}</li>
          ))}
        </ul>
      </section>

      <section>
        <h2># Compatible Mods</h2>
        <div className="mods">
          {mods.map((m) => (
            <span key={m} className="mod-badge">{m}</span>
          ))}
        </div>
        <p style={{ marginTop: '1rem', color: 'var(--text-dim)' }}>
          Built for MeatballCraft (1.12.2) but should work with any modpack containing these mods.
        </p>
      </section>
    </>
  )
}
