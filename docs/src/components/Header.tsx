export default function Header() {
  return (
    <header>
      <div className="container">
        <h1>BeeOS <span>v0.1</span></h1>
        <p className="tagline">Autonomous bee breeding automation for ComputerCraft</p>
        <div className="install-box">
          <div className="label">Install in-game:</div>
          <code>wget https://raw.githubusercontent.com/ChristopherJMiller/computercraft-beeos/main/beeos/install.lua install.lua</code>
          <code>install</code>
        </div>
      </div>
    </header>
  )
}
