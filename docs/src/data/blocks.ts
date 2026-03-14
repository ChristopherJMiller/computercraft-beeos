export interface BlockTextures {
  top?: string
  bottom?: string
  front?: string
  back?: string
  left?: string
  right?: string
  side?: string
}

export interface BlockDef {
  id: string
  label: string
  position: [number, number, number]
  textures: BlockTextures
  scale?: [number, number, number]
}

// Turtle uses a UV atlas spritesheet — can't map to a cube, so we use a solid color
export interface ColorBlockDef {
  id: string
  label: string
  position: [number, number, number]
  color: string
}

const base = import.meta.env.BASE_URL
const t = (path: string) => `${base}textures/${path}`

// ── Monitor configuration ──
// Adjust these to match your in-game monitor setup.
// CC:Tweaked monitors are multi-block: each block is 1x1.
// The Lua display code adapts to any size via mon.getSize().
export const MONITOR_WIDTH = 4   // blocks wide
export const MONITOR_HEIGHT = 3  // blocks tall

// ── All blocks in a single row (Z=0, Y=0) facing +Z toward camera ──
//
// Layout (top-down):
//   Z=-1: ═══ cable backbone (X=0..10) ═══  all blocks have modems on back (-Z) face
//   Z=0:  Comp Api1 Api2 Samp Impr Mutr Extr Turtl Buf1 Buf2 Buf3
//   Y=1:  Mon  Mon  Mon                           (above computer area)
//
// Buffer chests bridge CC↔AE2: modem on back → CC network, AE2 import/export bus on top

export const machines: BlockDef[] = [
  {
    id: 'computer',
    label: 'Advanced Computer',
    position: [0, 0, 0],
    textures: {
      top: t('cc/computer_top_advanced.png'),
      bottom: t('cc/computer_side_advanced.png'),
      front: t('cc/computer_front_on_advanced.png'),
      back: t('cc/computer_side_advanced.png'),
      side: t('cc/computer_side_advanced.png'),
    },
  },
  {
    id: 'apiary-1',
    label: 'Industrial Apiary',
    position: [1, 0, 0],
    textures: {
      top: t('gendustry/apiary_top.png'),
      side: t('gendustry/apiary_side.png'),
    },
  },
  {
    id: 'apiary-2',
    label: 'Industrial Apiary',
    position: [2, 0, 0],
    textures: {
      top: t('gendustry/apiary_top.png'),
      side: t('gendustry/apiary_side.png'),
    },
  },
  {
    id: 'sampler',
    label: 'Genetic Sampler',
    position: [3, 0, 0],
    textures: {
      top: t('gendustry/sampler_top.png'),
      bottom: t('gendustry/sampler_bottom.png'),
      side: t('gendustry/sampler_side.png'),
    },
  },
  {
    id: 'imprinter',
    label: 'Genetic Imprinter',
    position: [4, 0, 0],
    textures: {
      top: t('gendustry/imprinter_top.png'),
      bottom: t('gendustry/imprinter_bottom.png'),
      side: t('gendustry/imprinter_side.png'),
    },
  },
  {
    id: 'mutatron',
    label: 'Mutatron',
    position: [5, 0, 0],
    textures: {
      top: t('gendustry/mutatron_top.png'),
      bottom: t('gendustry/mutatron_bottom.png'),
      side: t('gendustry/mutatron_side.png'),
    },
  },
  {
    id: 'extractor',
    label: 'DNA Extractor',
    position: [6, 0, 0],
    textures: {
      top: t('gendustry/extractor_top.png'),
      bottom: t('gendustry/extractor_bottom.png'),
      side: t('gendustry/extractor_side.png'),
    },
  },
]

// Crafting Turtle — UV atlas texture can't map to cube faces.
// Placed next to computer. Connected to network via adjacent Wired Modem Full Block.
export const turtle: ColorBlockDef = {
  id: 'turtle',
  label: 'Crafting Turtle',
  position: [-1, 0, 0],
  color: '#d4a017',
}

// Wired Modem Full Block — adjacent to turtle, connects it to the cable network.
// Turtles can't equip wired modems; a full block modem next to it exposes
// the turtle as a peripheral on the wired network.
export const turtleModemBlock: BlockDef = {
  id: 'turtle-modem',
  label: 'Wired Modem (Full Block)',
  position: [-1, 0, -1],
  textures: {
    top: t('cc/wired_modem_face.png'),
    side: t('cc/wired_modem_face.png'),
    front: t('cc/wired_modem_face.png'),
  },
}

// ── Monitor wall (Y=1+, Z=0) ── configurable multi-block display above computer
export const monitors: BlockDef[] = Array.from(
  { length: MONITOR_WIDTH * MONITOR_HEIGHT },
  (_, i) => {
    const x = i % MONITOR_WIDTH
    const y = Math.floor(i / MONITOR_WIDTH) + 1  // Y=1 and up (above machine row)
    return {
      id: `monitor-${i + 1}`,
      label: 'Advanced Monitor',
      position: [x, y, 0] as [number, number, number],
      textures: {
        front: t('cc/adv_monitor4.png'),
        side: t('cc/computer_side_advanced.png'),
        top: t('cc/computer_side_advanced.png'),
        bottom: t('cc/computer_side_advanced.png'),
      },
    }
  }
)

// ── Buffer chests ── bridge CC wired network ↔ AE2
// Modem on back face connects to CC cable; AE2 import/export bus on top connects to ME network
export const storage: BlockDef[] = [
  {
    id: 'buffer-1',
    label: 'Buffer Chest (AE2 Bus)',
    position: [7, 0, 0],
    textures: {
      top: t('ae2/chest_top.png'),
      front: t('ae2/chest_front.png'),
      side: t('ae2/chest_side.png'),
    },
  },
  {
    id: 'buffer-2',
    label: 'Buffer Chest (AE2 Bus)',
    position: [8, 0, 0],
    textures: {
      top: t('ae2/chest_top.png'),
      front: t('ae2/chest_front.png'),
      side: t('ae2/chest_side.png'),
    },
  },
  {
    id: 'buffer-3',
    label: 'Buffer Chest (AE2 Bus)',
    position: [9, 0, 0],
    textures: {
      top: t('ae2/chest_top.png'),
      front: t('ae2/chest_front.png'),
      side: t('ae2/chest_side.png'),
    },
  },
]

// ── Wired modems ── flat on back (-Z) face of each block, facing the cable backbone
export interface ModemDef {
  id: string
  position: [number, number, number]
  face: 'north' | 'south' | 'east' | 'west'
}

export const modems: ModemDef[] = [
  // Turtle uses a Wired Modem Full Block (turtleModemBlock) instead of a face modem
  { id: 'modem-computer', position: [0, 0, 0], face: 'north' },
  { id: 'modem-apiary1', position: [1, 0, 0], face: 'north' },
  { id: 'modem-apiary2', position: [2, 0, 0], face: 'north' },
  { id: 'modem-sampler', position: [3, 0, 0], face: 'north' },
  { id: 'modem-imprinter', position: [4, 0, 0], face: 'north' },
  { id: 'modem-mutatron', position: [5, 0, 0], face: 'north' },
  { id: 'modem-extractor', position: [6, 0, 0], face: 'north' },
  { id: 'modem-buffer1', position: [7, 0, 0], face: 'north' },
  { id: 'modem-buffer2', position: [8, 0, 0], face: 'north' },
  { id: 'modem-buffer3', position: [9, 0, 0], face: 'north' },
]

// ── Networking cable backbone ── runs at Z=-1 behind everything
// Extends from X=-2 (past turtle modem) to X=9 (last buffer chest)
export const cablePositions: [number, number, number][] = Array.from(
  { length: 12 },
  (_, i) => [i - 2, 0, -1] as [number, number, number]
)

// Texture paths for cable and modem rendering
export const cableTexture = t('cc/cable_core.png')
export const modemFaceTexture = t('cc/wired_modem_face.png')
export const modemBackTexture = t('cc/modem_back.png')

// All textured full-size blocks
export const allBlocks: BlockDef[] = [...machines, ...monitors, ...storage, turtleModemBlock]
