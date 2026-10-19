// Espejo en TS de shared/scene.lua (schema 1)

export type Vec3 = [number, number, number]
export type SceneType = 'cutscene' | 'ambience'
export type EntityKind = 'ped' | 'vehicle' | 'prop' | 'sound' | 'crowd'
export type Channel = 'transform' | 'camera' | 'audio'
export type Ease = 'linear' | 'in' | 'out' | 'inOut'

export type PropValue = boolean | number | string | (boolean | number | string)[] | Record<string, boolean | number | string>

export interface SceneEntity {
  id: string
  kind: EntityKind
  model: string
  label: string
  props: Record<string, PropValue>
  networked: boolean
}

export interface Key {
  t: number
  pos: Vec3
  rot: Vec3
  ease?: Ease
  fov?: number
}

export interface Clip {
  start: number
  asset: string
  volume: number
  loop: boolean
  fadeIn: number
}

export interface Track {
  id: string
  target: string
  channel: Channel
  keys?: Key[]
  clips?: Clip[]
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
