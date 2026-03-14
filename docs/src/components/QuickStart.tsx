const steps = [
  'Set up hardware: computer, monitor, wired modems, networking cable to all machines',
  'Place buffer chests with AE2 import/export buses',
  'Run the installer on the computer',
  <>Run <code>tools/scan</code> to discover peripheral names</>,
  <>Run <code>tools/inspect &lt;chest&gt; &lt;slot&gt;</code> to verify bee reading works</>,
  <>Edit <code>config.lua</code> with your chest/machine names</>,
  <>Run <code>beeos</code> — starts with passive tracker only</>,
  'Enable layers as you verify each one works',
]

export default function QuickStart() {
  return (
    <section>
      <h2># Quick Start</h2>
      <ol className="features">
        {steps.map((step, i) => (
          <li key={i}>{step}</li>
        ))}
      </ol>
    </section>
  )
}
