import { t } from './i18n'
import type { MessageKey } from './i18n'
import type {
  AnyClip, AnyKey, Channel, EntityKind, Key, SceneData, SceneEntity, SceneType, Track, Vec3,
} from './types'

export const SCHEMA = 4

/** Targets que no son entidades (igual que Scene.RESERVED_TARGETS en Lua) */
export const CAMERA = 'camera'
export const EVENTS = 'events'
export const MUSIC = 'music'

export const KIND_LABEL: Record<EntityKind, MessageKey> = {
  ped: 'kindPed',
  vehicle: 'kindVehicle',
  prop: 'kindProp',
  sound: 'kindSound',
  crowd: 'kindCrowd',
  text: 'kindText',
  light: 'kindLight',
  ptfx: 'kindPtfx',
}

const KIND_PREFIX: Record<EntityKind, string> = {
  ped: 'ped',
  vehicle: 'veh',
  prop: 'prop',
  sound: 'snd',
  crowd: 'crowd',
  text: 'text',
  light: 'light',
  ptfx: 'fx',
}

const TRACK_PREFIX: Record<Channel, string> = {
  transform: 'tr',
  anim: 'an',
  camera: 'cam',
  audio: 'au',
  event: 'ev',
  visibility: 'vis',
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
      timecycle: null,
    },
    entities: [],
    tracks: [],
  }
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const asArray = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])

const usesClips = (channel: Channel) => channel === 'audio' || channel === 'anim'

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
      timecycle: isObject(settings.timecycle) ? (settings.timecycle as SceneData['settings']['timecycle']) : null,
    },
    entities: asArray<SceneEntity>(raw.entities).map((e) => ({
      ...e,
      props: isObject(e.props) ? e.props : {},
      networked: e.networked === true,
    })),
    tracks: asArray<Track>(raw.tracks).map((tr) => {
      const track: Track = { id: tr.id, target: tr.target, channel: tr.channel }
      if (usesClips(tr.channel)) track.clips = asArray(tr.clips)
      else track.keys = asArray(tr.keys)
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

// --- Pistas ----------------------------------------------------------------
// Todas las funciones que modifican sustituyen la pista (y sus listas) en vez de mutarlas:
// la escena vive en un shallowRef y los computed comparan por referencia.

export function findTrack(scene: SceneData, target: string, channel: Channel): Track | undefined {
  return scene.tracks.find((tr) => tr.target === target && tr.channel === channel)
}

export function transformTrack(scene: SceneData, entityId: string): Track | undefined {
  return findTrack(scene, entityId, 'transform')
}

function putTrack(scene: SceneData, track: Track) {
  const exists = scene.tracks.some((tr) => tr.id === track.id)
  scene.tracks = exists ? scene.tracks.map((tr) => (tr.id === track.id ? track : tr)) : [...scene.tracks, track]
}

function ensureTrack(scene: SceneData, target: string, channel: Channel): Track {
  const existing = findTrack(scene, target, channel)
  if (existing) return existing
  const id = target === CAMERA || target === EVENTS || target === MUSIC ? TRACK_PREFIX[channel] : `${TRACK_PREFIX[channel]}_${target}`
  return usesClips(channel) ? { id, target, channel, clips: [] } : { id, target, channel, keys: [] }
}

const byTime = (a: AnyKey, b: AnyKey) => a.t - b.t
const byStart = (a: AnyClip, b: AnyClip) => a.start - b.start

export function keyIndexAt(track: Track | undefined, time: number) {
  return track?.keys?.findIndex((k) => k.t === time) ?? -1
}

/** Inserta o sustituye la key de pose en su instante. */
export function upsertPoseKey(scene: SceneData, target: string, channel: 'transform' | 'camera', key: Key) {
  const track = ensureTrack(scene, target, channel)
  const keys = (track.keys ?? []) as Key[]
  const previous = keys.find((k) => k.t === key.t)
  const merged: Key = previous?.ease ? { ease: previous.ease, ...key } : key
  const next = keys.filter((k) => k.t !== key.t)
  putTrack(scene, { ...track, keys: [...next, merged].sort(byTime) })
}

/** Sustituye todas las keys de una pista (la crea si no existe). */
export function setTrackKeys(scene: SceneData, target: string, channel: Channel, keys: AnyKey[]) {
  const track = ensureTrack(scene, target, channel)
  putTrack(scene, { ...track, keys: [...keys].sort(byTime) })
}

/** Key de visibilidad en un instante (sustituye la que hubiera en ese t). */
export function upsertVisibilityKey(scene: SceneData, target: string, time: number, visible: boolean) {
  const track = ensureTrack(scene, target, 'visibility')
  const keys = (track.keys ?? []).filter((k) => k.t !== time)
  putTrack(scene, { ...track, keys: [...keys, { t: time, visible }].sort(byTime) })
}

/** ¿Visible en t? Igual que Evaluate.visible en Lua. */
export function visibleAt(scene: SceneData, target: string, time: number) {
  const keys = (findTrack(scene, target, 'visibility')?.keys ?? []) as { t: number; visible: boolean }[]
  if (!keys.length) return true
  let current = keys[0]
  for (const k of keys) if (k.t <= time) current = k
  return current.visible
}

export function addEventKey(scene: SceneData, key: AnyKey) {
  const track = ensureTrack(scene, EVENTS, 'event')
  putTrack(scene, { ...track, keys: [...(track.keys ?? []), key].sort(byTime) })
}

export function addClip(scene: SceneData, target: string, channel: 'audio' | 'anim', clip: AnyClip) {
  const track = ensureTrack(scene, target, channel)
  putTrack(scene, { ...track, clips: [...(track.clips ?? []), clip].sort(byStart) })
}

/** Cambia una key. Devuelve su nuevo índice (las keys se reordenan) o -1 si choca con otra en el mismo t. */
export function updateKey(scene: SceneData, trackId: string, index: number, patch: Partial<AnyKey>): number {
  const track = scene.tracks.find((tr) => tr.id === trackId)
  const keys = track?.keys
  if (!track || !keys?.[index]) return -1
  const updated = { ...keys[index], ...patch } as AnyKey
  if (track.channel !== 'event' && keys.some((k, i) => i !== index && k.t === updated.t)) return -1
  const next = keys.map((k, i) => (i === index ? updated : k)).sort(byTime)
  putTrack(scene, { ...track, keys: next })
  return next.indexOf(updated)
}

export function updateClip(scene: SceneData, trackId: string, index: number, patch: Partial<AnyClip>): number {
  const track = scene.tracks.find((tr) => tr.id === trackId)
  const clips = track?.clips
  if (!track || !clips?.[index]) return -1
  const updated = { ...clips[index], ...patch } as AnyClip
  const next = clips.map((c, i) => (i === index ? updated : c)).sort(byStart)
  putTrack(scene, { ...track, clips: next })
  return next.indexOf(updated)
}

/** Borra una key o clip; la pista se elimina si se queda vacía. */
export function removeItem(scene: SceneData, trackId: string, index: number) {
  const track = scene.tracks.find((tr) => tr.id === trackId)
  if (!track) return
  const next: Track = track.clips
    ? { ...track, clips: track.clips.filter((_, i) => i !== index) }
    : { ...track, keys: (track.keys ?? []).filter((_, i) => i !== index) }
  const empty = (next.clips ?? next.keys ?? []).length === 0
  scene.tracks = empty ? scene.tracks.filter((tr) => tr.id !== trackId) : scene.tracks.map((tr) => (tr.id === trackId ? next : tr))
}

export function removeEntity(scene: SceneData, entityId: string) {
  scene.entities = scene.entities.filter((e) => e.id !== entityId)
  scene.tracks = scene.tracks.filter((tr) => tr.target !== entityId)
}

/** Primera key de transform (la pose base cuando no hay timeline). */
export function baseTransform(scene: SceneData, entityId: string): Key | undefined {
  const keys = (transformTrack(scene, entityId)?.keys ?? []) as Key[]
  return keys.reduce<Key | undefined>((first, k) => (!first || k.t < first.t ? k : first), undefined)
}

export function clipEnd(clip: AnyClip, sceneEnd: number) {
  if ('dict' in clip) return clip.start + clip.duration
  if (clip.duration) return clip.start + clip.duration
  return clip.loop ? sceneEnd : clip.start + 3000
}

/** Todos los instantes con key o inicio de clip, ordenados y sin repetir (para saltar entre keys). */
export function keyTimes(scene: SceneData): number[] {
  const set = new Set<number>()
  for (const tr of scene.tracks) {
    for (const k of tr.keys ?? []) set.add(k.t)
    for (const c of tr.clips ?? []) set.add(c.start)
  }
  return [...set].sort((a, b) => a - b)
}

/** Entidades de juego que representa (una multitud cuenta tantas como personas), igual que en Lua */
export const GAME_KINDS: EntityKind[] = ['ped', 'vehicle', 'prop']

export function entityWeight(entity: SceneEntity) {
  if (entity.kind === 'crowd') return entity.crowd?.count ?? 0
  return GAME_KINDS.includes(entity.kind) ? 1 : 0
}

export function sceneWeight(scene: SceneData) {
  return scene.entities.reduce((sum, e) => sum + entityWeight(e), 0)
}

export function scenePeds(scene: SceneData) {
  return scene.entities.reduce((sum, e) => sum + (e.kind === 'ped' || e.kind === 'crowd' ? entityWeight(e) : 0), 0)
}

export function sceneStats(scene: SceneData) {
  let keys = 0
  for (const tr of scene.tracks) keys += (tr.keys?.length ?? 0) + (tr.clips?.length ?? 0)
  return { entities: scene.entities.length, tracks: scene.tracks.length, keys }
}

/** Duración efectiva: la de settings o la última key si va más allá (igual que Scene.stats). */
export function sceneDuration(scene: SceneData) {
  const times = keyTimes(scene)
  return Math.max(scene.settings.duration, times[times.length - 1] ?? 0)
}

export function formatDuration(ms: number) {
  const total = Math.round(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${String(s).padStart(2, '0')}`
}

/** m:ss.d */
export function formatTime(ms: number) {
  const tenths = Math.floor(Math.max(0, ms) / 100)
  const m = Math.floor(tenths / 600)
  const s = Math.floor((tenths % 600) / 10)
  return `${m}:${String(s).padStart(2, '0')}.${tenths % 10}`
}

export const vec3Equal = (a: Vec3, b: Vec3) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2]
