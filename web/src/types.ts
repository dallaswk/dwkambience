// Espejo en TS de shared/scene.lua (schema 2)

export type Vec3 = [number, number, number]
export type SceneType = 'cutscene' | 'ambience'
export type EntityKind = 'ped' | 'vehicle' | 'prop' | 'sound' | 'crowd'
export type Channel = 'transform' | 'anim' | 'camera' | 'audio' | 'event'
export type Ease = 'linear' | 'in' | 'out' | 'inOut' | 'spline'
export type EventType = 'fade' | 'subtitle' | 'trigger'

export type PropValue = boolean | number | string | (boolean | number | string)[] | Record<string, boolean | number | string>

export interface SceneEntity {
  id: string
  kind: EntityKind
  model: string
  label: string
  props: Record<string, PropValue>
  networked: boolean
}

/** Key de transform o de cámara */
export interface Key {
  t: number
  pos: Vec3
  rot: Vec3
  ease?: Ease
  fov?: number
}

export type EventKey =
  | { t: number; type: 'fade'; to: 0 | 1; duration: number }
  | { t: number; type: 'subtitle'; text: string; duration: number }
  | { t: number; type: 'trigger'; name: string }

export interface AudioClip {
  start: number
  asset: string
  volume: number
  loop: boolean
  fadeIn: number
  duration?: number
}

export interface AnimClip {
  start: number
  dict: string
  clip: string
  length: number
  duration: number
  loop: boolean
}

export type AnyKey = Key | EventKey
export type AnyClip = AudioClip | AnimClip

export interface Track {
  id: string
  target: string
  channel: Channel
  keys?: AnyKey[]
  clips?: AnyClip[]
}

export interface SceneSettings {
  weather: string
  time: string
  duration: number
  output: { letterbox: boolean; hud: boolean }
  loop: boolean
  active: boolean
  schedule: { from: string; to: string } | null
  trigger: { center: Vec3; enter: number; exit: number } | null
}

export interface SceneData {
  schema: number
  settings: SceneSettings
  entities: SceneEntity[]
  tracks: Track[]
}

export interface SceneMeta {
  id: number
  name: string
  type: SceneType
  group: string | null
  studio: number
  durationMs: number
  active: boolean
  entityCount: number
  keyCount: number
  updatedBy: string | null
  updatedAt: number | string | null
  lockedBy: string | null
}

export interface Studio {
  label: string
  maxEntities: number
}

export interface Result {
  ok: boolean
  error?: string
}

export interface OpenResult extends Result {
  meta: SceneMeta
  data: SceneData
  readOnly: boolean
  lockedBy: string | null
  failed?: string[]
}

export type SceneRow = SceneMeta
