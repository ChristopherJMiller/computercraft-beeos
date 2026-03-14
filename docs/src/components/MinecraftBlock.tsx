import { useRef, useState, useMemo } from 'react'
import { useLoader } from '@react-three/fiber'
import { Html } from '@react-three/drei'
import * as THREE from 'three'
import type { BlockTextures } from '../data/blocks'

interface MinecraftBlockProps {
  position: [number, number, number]
  textures: BlockTextures
  label: string
  scale?: [number, number, number]
}

// Face order for boxGeometry: +x (right), -x (left), +y (top), -y (bottom), +z (front), -z (back)
function resolveTexturePaths(textures: BlockTextures): string[] {
  const side = textures.side ?? textures.front ?? ''
  const top = textures.top ?? side
  const bottom = textures.bottom ?? side
  const front = textures.front ?? side
  const back = textures.back ?? side
  const left = textures.left ?? side
  const right = textures.right ?? side
  return [right, left, top, bottom, front, back]
}

export default function MinecraftBlock({ position, textures, label, scale }: MinecraftBlockProps) {
  const meshRef = useRef<THREE.Mesh>(null)
  const [hovered, setHovered] = useState(false)

  const paths = useMemo(() => resolveTexturePaths(textures), [textures])
  const loadedTextures = useLoader(THREE.TextureLoader, paths)

  const materials = useMemo(() => {
    return loadedTextures.map((tex) => {
      const cloned = tex.clone()
      cloned.magFilter = THREE.NearestFilter
      cloned.minFilter = THREE.NearestFilter
      cloned.colorSpace = THREE.SRGBColorSpace
      return new THREE.MeshStandardMaterial({
        map: cloned,
        emissive: hovered ? '#ffffff' : '#000000',
        emissiveIntensity: hovered ? 0.12 : 0,
      })
    })
  }, [loadedTextures, hovered])

  const s = scale ?? [0.95, 0.95, 0.95]

  return (
    <group position={position}>
      <mesh
        ref={meshRef}
        material={materials}
        scale={s}
        onPointerOver={(e) => { e.stopPropagation(); setHovered(true); document.body.style.cursor = 'pointer' }}
        onPointerOut={() => { setHovered(false); document.body.style.cursor = 'auto' }}
      >
        <boxGeometry args={[1, 1, 1]} />
      </mesh>
      {hovered && (
        <Html
          position={[0, (s[1] / 2) + 0.3, 0]}
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
