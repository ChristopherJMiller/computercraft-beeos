import Header from './components/Header'
import BlockScene from './components/BlockScene'
import LayerCards from './components/LayerCards'
import Features from './components/Features'
import QuickStart from './components/QuickStart'

export default function App() {
  return (
    <>
      <Header />
      <main className="container">
        <LayerCards />
        <section>
          <h2># Hardware Layout</h2>
          <BlockScene />
          <p>All machines connected via wired modems + networking cable. Computer orchestrates everything via <code>pushItems</code>/<code>pullItems</code> over the network.</p>
        </section>
        <Features />
        <QuickStart />
      </main>
      <footer>
        <p>BeeOS — <a href="https://github.com/ChristopherJMiller/computercraft-beeos">GitHub</a></p>
      </footer>
    </>
  )
}
