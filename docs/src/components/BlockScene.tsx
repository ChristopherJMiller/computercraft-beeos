import { Suspense } from 'react'
import { Canvas } from '@react-three/fiber'
import { OrbitControls } from '@react-three/drei'
import SetupDiagram from './SetupDiagram'

function Loader() {
  return (
    <mesh>
      <boxGeometry args={[0.5, 0.5, 0.5]} />
      <meshStandardMaterial color="#e2b714" wireframe />
    </mesh>
  )
}

export default function BlockScene() {
  return (
    <div className="scene-container">
      <Canvas
        camera={{
          // Positioned to see front faces (+Z) clearly, slightly above and to the right
          position: [5, 5, 10],
          fov: 50,
          near: 0.1,
          far: 100,
        }}
        gl={{ antialias: true }}
      >
        <color attach="background" args={['#0d1117']} />
        <ambientLight intensity={0.7} />
        <directionalLight position={[5, 10, 8]} intensity={0.8} />
        <directionalLight position={[-5, 3, -3]} intensity={0.2} />
        <Suspense fallback={<Loader />}>
          <SetupDiagram />
        </Suspense>
        <OrbitControls
          target={[0, 0, 0]}
          minDistance={3}
          maxDistance={30}
          enablePan={true}
          enableDamping={true}
          dampingFactor={0.1}
        />
      </Canvas>
      <p className="scene-hint">Drag to rotate &middot; Scroll to zoom &middot; Right-drag to pan &middot; Hover blocks for labels</p>
    </div>
  )
}
