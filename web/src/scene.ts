import { t } from './i18n'
import type { MessageKey } from './i18n'
import type { EntityKind, Key, SceneData, SceneEntity, SceneType, Track, Vec3 } from './types'

export const SCHEMA = 1

export const KIND_LABEL: Record<EntityKind, MessageKey> = {
  ped: 'kindPed',
  vehicle: 'kindVehicle',
  prop: 'kindProp',
  sound: 'kindSound',
  crowd: 'kindCrowd',
}

const KIND_PREFIX: Record<EntityKind, string> = {
  ped: 'ped',
  vehicle: 'veh',
  prop: 'prop',
  sound: 'snd',
  crowd: 'crowd',
}

export function newScene(type: SceneType): SceneData {
  const ambience = type === 'ambience'
  return {
    schema: SCHEMA,
    settings: {
      weather: 'CLEAR',
      time: '12:00',
      duration: ambience ? 60000 : 10000,
      output: { letterbox: !ambience, hud: ambience },
      loop: ambience,
      active: false,
      schedule: null,
      trigger: null,
    },
    entities: [],
    tracks: [],
  }
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const asArray = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])

/**
 * Lua no distingue [] de {} ni conserva null: el JSON que llega del cliente puede traer
 * arrays vacíos como objetos y campos opcionales ausentes. Esto lo deja en la forma de SceneData.
 */
export function normalizeScene(raw: unknown, type: SceneType): SceneData {
  const base = newScene(type)
  if (!isObject(raw)) return base
  const settings = isObject(raw.settings) ? raw.settings : {}

  return {
    schema: typeof raw.schema === 'number' ? raw.schema : SCHEMA,
    settings: {
      ...base.settings,
      ...settings,
      output: { ...base.settings.output, ...(isObject(settings.output) ? settings.output : {}) },
      schedule: isObject(settings.schedule) ? (settings.schedule as SceneData['settings']['schedule']) : null,
      trigger: isObject(settings.trigger) ? (settings.trigger as SceneData['settings']['trigger']) : null,
    },
    entities: asArray<SceneEntity>(raw.entities).map((e) => ({
      ...e,
      props: isObject(e.props) ? e.props : {},
      networked: e.networked === true,
    })),
    tracks: asArray<Track>(raw.tracks).map((t) => {
      const track: Track = { id: t.id, target: t.target, channel: t.channel }
      if (t.channel === 'audio') track.clips = asArray(t.clips)
      else track.keys = asArray(t.keys)
      return track
    }),
  }
}

export function nextEntityId(scene: SceneData, kind: EntityKind): { id: string; label: string } {
  const prefix = KIND_PREFIX[kind]
  let max = 0
  for (const e of scene.entities) {
    const match = e.id.match(new RegExp(`^${prefix}_(\\d+)$`))
    if (match) max = Math.max(max, Number(match[1]))
  }
  return { id: `${prefix}_${max + 1}`, label: `${t(KIND_LABEL[kind])} ${max + 1}` }
}

export function transformTrack(scene: SceneData, entityId: string): Track | undefined {
  return scene.tracks.find((t) => t.target === entityId && t.channel === 'transform')
}

/** Transform base: la key de transform con menor t (igual que Scene.baseTransform en Lua). */
export function baseTransform(scene: SceneData, entityId: string): Key | undefined {
  const keys = transformTrack(scene, entityId)?.keys ?? []
  return keys.reduce<Key | undefined>((first, k) => (!first || k.t < first.t ? k : first), undefined)
}

/** Escribe el transform base. En la fase 0 no hay timeline: la key vive en t = 0. */
export function setBaseTransform(scene: SceneData, entityId: string, pos: Vec3, rot: Vec3) {
  let track = transformTrack(scene, entityId)
  if (!track) {
    track = { id: `tr_${entityId}`, target: entityId, channel: 'transform', keys: [] }
    scene.tracks.push(track)
  }
  // Se sustituye la key en vez de mutarla: los computed que la devuelven tienen que ver un objeto nuevo
  const key = baseTransform(scene, entityId)
  const keys = track.keys ?? []
  track.keys = key ? keys.map((k) => (k === key ? { ...k, pos, rot } : k)) : [{ t: 0, pos, rot }]
}

export function removeEntity(scene: SceneData, entityId: string) {
  scene.entities = scene.entities.filter((e) => e.id !== entityId)
  scene.tracks = scene.tracks.filter((t) => t.target !== entityId)
}

export function sceneStats(scene: SceneData) {
  let keys = 0
  for (const t of scene.tracks) keys += (t.keys?.length ?? 0) + (t.clips?.length ?? 0)
  return { entities: scene.entities.length, tracks: scene.tracks.length, keys }
}

export function formatDuration(ms: number) {
  const total = Math.round(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${String(s).padStart(2, '0')}`
}
