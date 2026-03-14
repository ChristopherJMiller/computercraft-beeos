import { useState, useMemo } from 'react'
import { useLoader } from '@react-three/fiber'
import { Html } from '@react-three/drei'
import * as THREE from 'three'
import MinecraftBlock from './MinecraftBlock'
import {
  allBlocks,
  turtle,
  modems,
  cablePositions,
  cableTexture,
  modemFaceTexture,
  modemBackTexture,
} from '../data/blocks'

const CABLE_SIZE = 0.25
const MODEM_THICKNESS = 0.125
const MODEM_SIZE = 0.75

function CableBlock({ position }: { position: [number, number, number] }) {
  const [tex] = useLoader(THREE.TextureLoader, [cableTexture])

  const material = useMemo(() => {
    const cloned = tex.clone()
    cloned.magFilter = THREE.NearestFilter
    cloned.minFilter = THREE.NearestFilter
    cloned.colorSpace = THREE.SRGBColorSpace
    return new THREE.MeshStandardMaterial({ map: cloned })
  }, [tex])

  return (
    <mesh position={position} material={material}>
      <boxGeometry args={[0.98, CABLE_SIZE, CABLE_SIZE]} />
    </mesh>
  )
}

// Short cable stub connecting a modem to the backbone (runs in Z direction)
function CableStub({ position }: { position: [number, number, number] }) {
  const [tex] = useLoader(THREE.TextureLoader, [cableTexture])

  const material = useMemo(() => {
    const cloned = tex.clone()
    cloned.magFilter = THREE.NearestFilter
    cloned.minFilter = THREE.NearestFilter
    cloned.colorSpace = THREE.SRGBColorSpace
    return new THREE.MeshStandardMaterial({ map: cloned })
  }, [tex])

  return (
    <mesh position={position} material={material}>
      <boxGeometry args={[CABLE_SIZE, CABLE_SIZE, 0.4]} />
    </mesh>
  )
}

function WiredModem({ position, face }: { position: [number, number, number]; face: 'north' | 'south' | 'east' | 'west' }) {
  const [faceTex, backTex] = useLoader(THREE.TextureLoader, [modemFaceTexture, modemBackTexture])

  const materials = useMemo(() => {
    const makeMat = (t: THREE.Texture) => {
      const cloned = t.clone()
      cloned.magFilter = THREE.NearestFilter
      cloned.minFilter = THREE.NearestFilter
      cloned.colorSpace = THREE.SRGBColorSpace
      return new THREE.MeshStandardMaterial({ map: cloned })
    }
    const fMat = makeMat(faceTex)
    const bMat = makeMat(backTex)
    // boxGeometry face order: +x, -x, +y, -y, +z, -z
    // Modem face texture faces outward (away from parent block)
    switch (face) {
      case 'south': return [bMat, bMat, bMat, bMat, fMat, bMat]  // +Z outward
      case 'north': return [bMat, bMat, bMat, bMat, bMat, fMat]  // -Z outward
      case 'east':  return [fMat, bMat, bMat, bMat, bMat, bMat]
      case 'west':  return [bMat, fMat, bMat, bMat, bMat, bMat]
    }
  }, [faceTex, backTex, face])

  // Modem protrudes from the parent block face
  const offset: [number, number, number] = (() => {
    switch (face) {
      case 'south': return [0, 0, 0.5 + MODEM_THICKNESS / 2]
      case 'north': return [0, 0, -(0.5 + MODEM_THICKNESS / 2)]
      case 'east':  return [0.5 + MODEM_THICKNESS / 2, 0, 0]
      case 'west':  return [-(0.5 + MODEM_THICKNESS / 2), 0, 0]
    }
  })()

  const size: [number, number, number] = (() => {
    switch (face) {
      case 'south':
      case 'north': return [MODEM_SIZE, MODEM_SIZE, MODEM_THICKNESS]
      case 'east':
      case 'west':  return [MODEM_THICKNESS, MODEM_SIZE, MODEM_SIZE]
    }
  })()

  return (
    <mesh
      position={[
        position[0] + offset[0],
        position[1] + offset[1],
        position[2] + offset[2],
      ]}
      material={materials}
    >
      <boxGeometry args={size} />
    </mesh>
  )
}

// Solid-colored cube for blocks without usable face textures (e.g. turtle UV atlas)
function ColorBlock({ position, color, label }: { position: [number, number, number]; color: string; label: string }) {
  const [hovered, setHovered] = useState(false)

  return (
    <group position={position}>
      <mesh
        onPointerOver={(e) => { e.stopPropagation(); setHovered(true); document.body.style.cursor = 'pointer' }}
        onPointerOut={() => { setHovered(false); document.body.style.cursor = 'auto' }}
      >
        <boxGeometry args={[0.95, 0.95, 0.95]} />
        <meshStandardMaterial
          color={color}
          emissive={hovered ? '#ffffff' : '#000000'}
          emissiveIntensity={hovered ? 0.12 : 0}
        />
      </mesh>
      {hovered && (
        <Html
          position={[0, 0.75, 0]}
          center
          style={{
            background: '#16213e',
            border: '1px solid #e2b714',
            borderRadius: '6px',
            padding: '4px 8px',
            color: '#e0e0e0',
            fontSize: '12px',
            fontFamily: "'Courier New', monospace",
            whiteSpace: 'nowrap',
            pointerEvents: 'none',
          }}
        >
          {label}
        </Html>
      )}
    </group>
  )
}

export default function SetupDiagram() {
  // Center scene: blocks span X=-1 (turtle) to X=9 (last buffer)
  const centerX = 4

  return (
    <group position={[-centerX, 0, 0.5]}>
      {/* Ground plane */}
      <gridHelper
        args={[16, 16, '#2a2a4a', '#1a1a2e']}
        position={[4, -0.475, -0.5]}
      />

      {/* ── Full-size textured blocks (machines, monitors, storage, turtle modem) ── */}
      {allBlocks.map((block) => (
        <MinecraftBlock
          key={block.id}
          position={block.position}
          textures={block.textures}
          label={block.label}
          scale={block.scale}
        />
      ))}

      {/* ── Crafting Turtle (solid gold — UV atlas can't be cube-mapped) ── */}
      {/* Placed next to computer, connected via adjacent Wired Modem Full Block */}
      <ColorBlock
        position={turtle.position}
        color={turtle.color}
        label={turtle.label}
      />

      {/* ── Wired modems on back face of machines and buffer chests ── */}
      {modems.map((modem) => (
        <WiredModem
          key={modem.id}
          position={modem.position}
          face={modem.face}
        />
      ))}

      {/* ── Cable backbone (Z=-1, running X=-2 to X=9) ── */}
      {cablePositions.map((pos, i) => (
        <CableBlock key={`cable-${i}`} position={pos} />
      ))}

      {/* ── Cable stubs: connect each face modem to the backbone ── */}
      {/* Machines and buffer chests at X=0..9 */}
      {Array.from({ length: 10 }, (_, i) => (
        <CableStub key={`stub-${i}`} position={[i, 0, -0.7]} />
      ))}
    </group>
  )
}
