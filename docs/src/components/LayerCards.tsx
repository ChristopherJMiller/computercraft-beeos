const layers = [
  {
    id: 'l0',
    tag: 'ALWAYS ON',
    tagClass: 'tag-always',
    title: 'Layer 0: Passive Tracker',
    desc: 'Scans all inventories. Builds species catalog with sample counts, template availability, drone/princess stock. Never moves items.',
  },
  {
    id: 'l1',
    tag: 'TOGGLEABLE',
    tagClass: 'tag-toggle',
    title: 'Layer 1: Apiary Manager',
    desc: 'Monitors Industrial Apiaries. Auto-restarts dead queens. Routes products to AE2, drones to processing, princesses back to apiaries.',
  },
  {
    id: 'l2',
    tag: 'TOGGLEABLE',
    tagClass: 'tag-toggle',
    title: 'Layer 2: Sample & Templates',
    desc: 'Maintains minimum genetic samples per species. Routes drones to Genetic Sampler. Crafts templates via crafting turtle.',
  },
  {
    id: 'l3',
    tag: 'TOGGLEABLE',
    tagClass: 'tag-toggle',
    title: 'Layer 3: Auto-Discovery',
    desc: 'Traverses the full mutation tree via BFS. Uses the basic Mutatron to discover and catalog every reachable bee species autonomously.',
  },
]

export default function LayerCards() {
  return (
    <section>
      <h2># System Layers</h2>
      <p>BeeOS runs as independent, toggleable layers. Enable what you need.</p>
      <div className="layers">
        {layers.map((l) => (
          <div key={l.id} className={`layer-card ${l.id}`}>
            <span className={`tag ${l.tagClass}`}>{l.tag}</span>
            <h3>{l.title}</h3>
            <p>{l.desc}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
