// Callbacks simulados para `npm run dev` fuera del juego. Guardan las escenas en localStorage.
import { newScene } from '../scene'
import type { SceneData, SceneMeta, SceneType, Vec3 } from '../types'

interface MockRow {
  meta: SceneMeta
  data: SceneData
}

const STORAGE_KEY = 'dwkambience:mock-scenes'
// Idioma del mock: ?lang=en en la URL para probar el inglés
const LOCALE = new URLSearchParams(location.search).get('lang') ?? 'es'
const PRESETS = ['custom', 'beach', 'business', 'club', 'concert', 'gangs', 'paparazzi', 'street']

function load(): MockRow[] {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '[]') as MockRow[]
  } catch {
    return []
  }
}

function store(rows: MockRow[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(rows))
  } catch {
    // sin almacenamiento: el mock sigue funcionando en memoria hasta recargar
  }
}

/** Imita el viaje por Lua: se pierden los null y los arrays vacíos pueden volver como objetos. */
function throughLua<T>(value: T): T {
  return JSON.parse(
    JSON.stringify(value, (_k, v) => {
      if (v === null) return undefined
      if (Array.isArray(v) && v.length === 0) return {}
      return v
    }),
  ) as T
}

function stats(data: SceneData) {
  let keys = 0
  for (const t of data.tracks ?? []) keys += (t.keys?.length ?? 0) + (t.clips?.length ?? 0)
  return { entityCount: data.entities?.length ?? 0, keyCount: keys }
}

let rows = load()
let openId: number | null = null
const poses = new Map<string, { pos: Vec3; rot: Vec3 }>()
const randomPos = (): Vec3 => [
  +(290 + Math.random() * 10).toFixed(3),
  +(-850 + Math.random() * 10).toFixed(3),
  28.8,
]

const handlers: Record<string, (data: any) => unknown> = {
  list: () => ({ ok: true, scenes: rows.map((r) => r.meta) }),

  create: ({ name, type, group }: { name: string; type: SceneType; group?: string }) => {
    const id = rows.reduce((max, r) => Math.max(max, r.meta.id), 0) + 1
    const data = newScene(type)
    if (type === 'ambience') data.settings.trigger = { center: randomPos(), enter: 80, exit: 100 }
    const meta: SceneMeta = {
      id, name, type, group: group?.trim() || null, studio: 1,
      durationMs: data.settings.duration, active: false, entityCount: 0, keyCount: 0,
      updatedBy: 'Dev', updatedAt: Date.now(), lockedBy: null,
    }
    rows.push({ meta, data })
    store(rows)
    openId = id
    return { ok: true, meta, data: throughLua(data), readOnly: false, lockedBy: null }
  },

  open: ({ id }: { id: number }) => {
    const row = rows.find((r) => r.meta.id === id)
    if (!row) return { ok: false, error: 'not_found' }
    openId = id
    return { ok: true, meta: row.meta, data: throughLua(row.data), readOnly: false, lockedBy: null }
  },

  save: ({ id, meta, data }: { id: number; meta: { name: string; group: string | null }; data: SceneData }) => {
    const row = rows.find((r) => r.meta.id === id)
    if (!row || openId !== id) return { ok: false, error: 'not_locked' }
    row.data = throughLua(data)
    row.meta = {
      ...row.meta, ...stats(data), name: meta.name, group: meta.group || null,
      durationMs: data.settings.duration, updatedAt: Date.now(),
    }
    store(rows)
    return { ok: true, meta: row.meta, rev: 1 }
  },

  closeScene: () => {
    openId = null
    return { ok: true }
  },

  delete: ({ id }: { id: number }) => {
    rows = rows.filter((r) => r.meta.id !== id)
    store(rows)
    return { ok: true }
  },

  spawnPoint: ({ model }: { model: string }) =>
    /^[\w-]+$/.test(model) ? { ok: true, pos: randomPos(), rot: [0, 0, +(Math.random() * 360).toFixed(2)] } : { ok: false, error: 'invalid_model' },

  pick: () => ({ ok: true, id: null }),

  cameraPoint: () => ({ ok: true, pos: randomPos() }),
  worldPoint: () => ({ ok: true, pos: randomPos() }),

  setActive: ({ id, active }: { id: number; active: boolean }) => {
    const row = rows.find((r) => r.meta.id === id)
    if (!row || row.meta.type !== 'ambience') return { ok: false, error: 'not_ambience' }
    row.meta = { ...row.meta, active }
    store(rows)
    return { ok: true, active }
  },

  preview: () => {
    window.postMessage({ action: 'preview', data: { active: true } }, '*')
    setTimeout(() => window.postMessage({ action: 'preview', data: { active: false } }, '*'), 1500)
    return { ok: true }
  },

  applyEntity: ({ entity, pos, rot }: { entity: { id: string }; pos: Vec3; rot: Vec3 }) => {
    if (pos && rot) poses.set(entity.id, { pos, rot })
    return { ok: true }
  },

  pose: ({ id }: { id: string }) => {
    const pose = poses.get(id)
    return pose ? { ok: true, ...pose } : { ok: false }
  },

  cameraPose: () => ({ ok: true, pos: randomPos(), rot: [-10, 0, +(Math.random() * 360).toFixed(2)], fov: 50 }),

  animInfo: ({ dict }: { dict: string }) => (dict ? { ok: true, length: 2000 } : { ok: false, error: 'invalid_anim' }),

  ground: () => ({ ok: true, pos: randomPos(), rot: [0, 0, 0] }),

  gizmo: ({ id }: { id: string }) => {
    window.postMessage({ action: 'gizmo', data: { active: true, id } }, '*')
    setTimeout(() => {
      window.postMessage({ action: 'gizmo', data: { active: false, id, confirmed: true, pos: randomPos(), rot: [0, 0, 45] } }, '*')
    }, 1200)
    return { ok: true }
  },

  exit: () => {
    setTimeout(() => window.postMessage({ action: 'open', data: { studios: { 1: { label: 'Studio 1', maxEntities: 300 } }, defaultStudio: 1, locale: LOCALE, presets: PRESETS, maxPedsPerAmbience: 60 } }, '*'), 800)
    return { ok: true }
  },
}

export async function mockNui<T>(event: string, data: unknown): Promise<T> {
  await new Promise((r) => setTimeout(r, 80))
  const handler = handlers[event]
  return (handler ? handler(data) : { ok: true }) as T
}

/** Simula que el cliente abre el editor al cargar la página. */
export function bootMock() {
  window.postMessage({ action: 'open', data: { studios: { 1: { label: 'Studio 1', maxEntities: 300 } }, defaultStudio: 1, locale: LOCALE, presets: PRESETS, maxPedsPerAmbience: 60 } }, '*')
}
