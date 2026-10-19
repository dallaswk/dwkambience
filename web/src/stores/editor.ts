import { defineStore } from 'pinia'
import { computed, ref, shallowRef, triggerRef } from 'vue'
import { setLocale, t } from '../i18n'
import type { MessageKey } from '../i18n'
import { fetchNui } from '../nui'
import {
  CAMERA, EVENTS, MUSIC, addClip, addEventKey, findTrack, keyIndexAt, nextEntityId, normalizeScene,
  removeEntity as removeFromScene, removeItem, transformTrack, updateClip, updateKey, upsertPoseKey,
} from '../scene'
import type {
  AnyClip, AnyKey, EntityKind, EventType, OpenResult, Result, SceneData, SceneEntity, SceneMeta, SceneRow,
  SceneType, Studio, Track, Vec3,
} from '../types'
import { useHistory } from './history'
import { useTimeline } from './timeline'
import { useToasts } from './toasts'

const ERRORS: Record<string, MessageKey> = {
  forbidden: 'errForbidden',
  not_locked: 'errLocked',
  locked: 'errLocked',
  not_found: 'errNotFound',
  bad_name: 'errBadName',
  bad_group: 'errBadGroup',
  invalid_model: 'errInvalidModel',
  invalid_anim: 'errInvalidAnim',
  spawn_failed: 'errSpawnFailed',
  too_many_entities: 'errTooManyEntities',
  too_large: 'errTooLarge',
  corrupt_scene: 'errCorrupt',
  db_error: 'errDb',
  db_not_ready: 'errDbNotReady',
}

// Los errores de validación del servidor ('invalid: ...') se muestran tal cual
const errorText = (code?: string) => (code ? (ERRORS[code] ? t(ERRORS[code]) : code) : t('errUnknown'))

const SYNC_DELAY = 120
const POSE_DELAY = 120

function toStudios(raw: unknown): Record<number, Studio> {
  // Lua serializa { [1] = ... } como array JSON
  if (Array.isArray(raw)) return Object.fromEntries(raw.map((s, i) => [i + 1, s as Studio]))
  return (raw ?? {}) as Record<number, Studio>
}

export interface Pose {
  pos: Vec3
  rot: Vec3
}

export interface SelectedItem {
  track: Track
  index: number
  kind: 'key' | 'clip'
  item: AnyKey | AnyClip
}

export const useEditor = defineStore('editor', () => {
  const toasts = useToasts()
  const history = useHistory()

  const visible = ref(false)
  const studios = ref<Record<number, Studio>>({})
  const rows = ref<SceneRow[]>([])
  const loadingList = ref(false)

  const meta = ref<SceneMeta | null>(null)
  // Regla: se sustituye el objeto que cambia (entidad, key, settings, pista), nunca se muta en sitio
  const scene = shallowRef<SceneData | null>(null)
  const readOnly = ref(false)
  const lockedBy = ref<string | null>(null)
  const dirty = ref(false)
  const savedAt = ref<number | null>(null)
  const saving = ref(false)

  const selectedId = ref<string | null>(null)
  const pose = ref<Pose | null>(null) // pose de la entidad seleccionada en el instante actual
  const gizmoActive = ref(false)
  const showLabels = ref(true)

  const studio = computed<Studio | null>(() => (meta.value ? studios.value[meta.value.studio] ?? null : null))
  const entityCount = computed(() => scene.value?.entities.length ?? 0)
  const selected = computed<SceneEntity | null>(() => scene.value?.entities.find((e) => e.id === selectedId.value) ?? null)
  const canEdit = computed(() => !!scene.value && !readOnly.value)

  function fail(result: Result | undefined, fallback?: string) {
    toasts.push(errorText(result?.error ?? fallback), 'error')
  }

  // --- Sincronización con el cliente ------------------------------------------

  let syncTimer: ReturnType<typeof setTimeout> | null = null
  function syncNow() {
    if (syncTimer) clearTimeout(syncTimer)
    syncTimer = null
    if (scene.value) fetchNui('syncScene', { data: scene.value })
  }
  function scheduleSync() {
    if (syncTimer) clearTimeout(syncTimer)
    syncTimer = setTimeout(syncNow, SYNC_DELAY)
  }

  let poseTimer: ReturnType<typeof setTimeout> | null = null
  async function refreshPose() {
    const id = selectedId.value
    if (!id) {
      pose.value = null
      return
    }
    const result = await fetchNui<Result & Pose>('pose', { id })
    if (selectedId.value === id) pose.value = result?.ok ? { pos: result.pos, rot: result.rot } : null
  }
  function schedulePoseRefresh() {
    if (poseTimer) clearTimeout(poseTimer)
    poseTimer = setTimeout(refreshPose, POSE_DELAY)
  }

  /** Aplica una edición: guarda instantánea para deshacer, avisa a Vue y sincroniza el cliente. */
  function edit(fn: (s: SceneData) => void, checkpoint = true) {
    if (!scene.value || readOnly.value) return false
    if (checkpoint) history.checkpoint(scene.value)
    fn(scene.value)
    triggerRef(scene)
    dirty.value = true
    scheduleSync()
    return true
  }

  function checkpoint() {
    if (scene.value && !readOnly.value) history.checkpoint(scene.value)
  }

  function restore(next: SceneData | null) {
    if (!next) return
    scene.value = next
    triggerRef(scene)
    dirty.value = true
    useTimeline().select(null)
    if (selectedId.value && !next.entities.some((e) => e.id === selectedId.value)) selectedId.value = null
    syncNow()
    schedulePoseRefresh()
  }

  function undo() {
    if (scene.value && !readOnly.value) restore(history.undo(scene.value))
  }

  function redo() {
    if (scene.value && !readOnly.value) restore(history.redo(scene.value))
  }

  // --- Ciclo de vida --------------------------------------------------------

  function show(payload: { studios: unknown; locale?: unknown }) {
    setLocale(payload.locale)
    studios.value = toStudios(payload.studios)
    visible.value = true
    refreshList()
  }

  function hide() {
    visible.value = false
    resetScene()
  }

  function resetScene() {
    useTimeline().reset()
    history.reset()
    meta.value = null
    scene.value = null
    selectedId.value = null
    pose.value = null
    readOnly.value = false
    lockedBy.value = null
    dirty.value = false
    savedAt.value = null
    gizmoActive.value = false
  }

  async function exit() {
    await fetchNui('exit')
    hide()
  }

  async function refreshList() {
    loadingList.value = true
    const result = await fetchNui<Result & { scenes: SceneRow[] }>('list')
    loadingList.value = false
    if (result?.ok) rows.value = result.scenes ?? []
    else fail(result)
  }

  function adopt(result: OpenResult) {
    resetScene()
    meta.value = result.meta
    scene.value = normalizeScene(result.data, result.meta.type)
    readOnly.value = result.readOnly
    lockedBy.value = result.lockedBy ?? null

    toasts.push(t('loaded', { name: result.meta.name }), 'success')
    if (result.readOnly) toasts.push(t('readOnlyBy', { who: result.lockedBy ?? t('someone') }), 'warning', 6000)
    const failed = Array.isArray(result.failed) ? result.failed : []
    if (failed.length) toasts.push(t('couldNotSpawn', { list: failed.join(', ') }), 'warning', 6000)
  }

  async function createScene(name: string, type: SceneType, group: string) {
    const result = await fetchNui<OpenResult>('create', { name, type, group })
    if (!result?.ok) return fail(result)
    adopt(result)
    refreshList()
  }

  async function openScene(id: number) {
    const result = await fetchNui<OpenResult>('open', { id })
    if (!result?.ok) return fail(result)
    adopt(result)
  }

  async function closeScene() {
    await fetchNui('closeScene')
    resetScene()
    refreshList()
  }

  async function deleteScene(id: number) {
    const result = await fetchNui<Result>('delete', { id })
    if (!result?.ok) return fail(result)
    if (meta.value?.id === id) resetScene()
    toasts.push(t('sceneDeleted'))
    refreshList()
  }

  async function save() {
    if (!scene.value || !meta.value || readOnly.value || saving.value) return
    saving.value = true
    const result = await fetchNui<Result & { meta: SceneMeta }>('save', {
      id: meta.value.id,
      meta: { name: meta.value.name, group: meta.value.group ?? '' },
      data: scene.value,
    })
    saving.value = false
    if (!result?.ok) return fail(result)
    meta.value = { ...meta.value, ...result.meta }
    dirty.value = false
    savedAt.value = Date.now()
  }

  function setMeta(patch: Partial<Pick<SceneMeta, 'name' | 'group'>>) {
    if (!meta.value || readOnly.value) return
    meta.value = { ...meta.value, ...patch }
    dirty.value = true
  }

  function setSettings(patch: Partial<SceneData['settings']>) {
    edit((s) => {
      s.settings = { ...s.settings, ...patch }
    })
  }

  // --- Entidades ------------------------------------------------------------

  async function spawn(kind: EntityKind, model: string) {
    if (!scene.value || !canEdit.value) return
    if (studio.value && entityCount.value >= studio.value.maxEntities) return fail({ ok: false, error: 'too_many_entities' })

    const point = await fetchNui<Result & { pos: Vec3; rot: Vec3 }>('spawnPoint', { kind, model })
    if (!point?.ok) return fail(point)

    const { id, label } = nextEntityId(scene.value, kind)
    const entity: SceneEntity = { id, kind, model, label, props: {}, networked: false }
    const result = await fetchNui<Result>('applyEntity', { entity, pos: point.pos, rot: point.rot })
    if (!result?.ok) return fail(result)

    const timeline = useTimeline()
    const at = timeline.snapTime(timeline.time)
    edit((s) => {
      s.entities = [...s.entities, entity]
      upsertPoseKey(s, id, 'transform', { t: at, pos: point.pos, rot: point.rot })
    })
    select(id)
  }

  function updateEntity(id: string, patch: Partial<Omit<SceneEntity, 'id' | 'kind'>>) {
    edit((s) => {
      s.entities = s.entities.map((e) => (e.id === id ? { ...e, ...patch } : e))
    })
  }

  function setProp(id: string, key: string, value: SceneEntity['props'][string] | undefined) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity) return
    const props = { ...entity.props }
    if (value === undefined || value === '') delete props[key]
    else props[key] = value
    updateEntity(id, { props })
  }

  /**
   * Nueva pose de una entidad en el instante actual. Se graba como key si la pista está vacía,
   * si Auto key está activo o si ya hay una key en ese instante. Si no, solo se mueve en el mundo
   * hasta que se pulse Key (al mover el timeline vuelve a la pose de las keys).
   */
  function setPose(id: string, pos: Vec3, rot: Vec3, alreadyInWorld = false) {
    if (!scene.value || !canEdit.value) return
    const timeline = useTimeline()
    const at = timeline.snapTime(timeline.time)
    const track = transformTrack(scene.value, id)
    const record = !track?.keys?.length || timeline.autoKey || keyIndexAt(track, at) >= 0

    pose.value = { pos, rot }
    if (record) {
      edit((s) => upsertPoseKey(s, id, 'transform', { t: at, pos, rot }))
    } else {
      toasts.push(t('poseNotKeyed'), 'info')
    }
    if (!alreadyInWorld) {
      const entity = scene.value.entities.find((e) => e.id === id)
      if (entity) fetchNui('applyEntity', { entity, pos, rot })
    }
  }

  async function removeEntity(id: string) {
    if (!edit((s) => removeFromScene(s, id))) return
    if (selectedId.value === id) select(null)
    await fetchNui('removeEntity', { id })
  }

  function select(id: string | null) {
    selectedId.value = id
    pose.value = null
    fetchNui('select', { id })
    if (id) {
      useTimeline().select(null)
      refreshPose()
    }
  }

  async function pick(x: number, y: number) {
    const result = await fetchNui<Result & { id: string | null }>('pick', { x, y })
    selectedId.value = result?.id ?? null
    if (selectedId.value) useTimeline().select(null)
    refreshPose()
  }

  async function ground(id: string) {
    if (!canEdit.value) return
    const result = await fetchNui<Result & Pose>('ground', { id })
    if (result?.ok) setPose(id, result.pos, result.rot, true)
  }

  async function startGizmo(id: string, mode: 'translate' | 'rotate') {
    if (!canEdit.value || gizmoActive.value) return
    useTimeline().pause()
    const result = await fetchNui<Result>('gizmo', { id, mode })
    if (result && result.ok === false) fail(result)
  }

  function onGizmo(data: { active: boolean; id: string; confirmed?: boolean; pos?: Vec3; rot?: Vec3 }) {
    gizmoActive.value = data.active
    if (!data.active && data.confirmed && data.pos && data.rot) setPose(data.id, data.pos, data.rot, true)
  }

  function focus(id: string) {
    fetchNui('focus', { id })
  }

  function toggleLabels() {
    showLabels.value = !showLabels.value
    fetchNui('labels', { enabled: showLabels.value })
  }

  // --- Timeline: keys, clips y eventos ------------------------------------------

  /** Botón Key: graba la pose de la cámara (Camera view, fila de cámara o nada seleccionado) o de la entidad seleccionada. */
  async function recordKey() {
    if (!scene.value || !canEdit.value) return
    const timeline = useTimeline()
    const at = timeline.snapTime(timeline.time)

    if (timeline.cameraView || timeline.selectedRow === CAMERA || !selectedId.value) {
      if (meta.value?.type !== 'cutscene') return
      const cam = await fetchNui<Result & Pose & { fov: number }>('cameraPose')
      if (!cam?.ok) return
      edit((s) => upsertPoseKey(s, CAMERA, 'camera', { t: at, pos: cam.pos, rot: cam.rot, fov: cam.fov }))
      return
    }

    const id = selectedId.value
    const current = await fetchNui<Result & Pose>('pose', { id })
    if (!current?.ok) return
    edit((s) => upsertPoseKey(s, id, 'transform', { t: at, pos: current.pos, rot: current.rot }))
  }

  function selectItemAt(target: string, channel: Track['channel'], kind: 'key' | 'clip', item: AnyKey | AnyClip) {
    const track = scene.value && findTrack(scene.value, target, channel)
    const list: (AnyKey | AnyClip)[] = (kind === 'key' ? track?.keys : track?.clips) ?? []
    const index = list.indexOf(item)
    if (track && index >= 0) useTimeline().select({ trackId: track.id, index, kind })
  }

  function addEvent(type: EventType) {
    const timeline = useTimeline()
    const at = timeline.snapTime(timeline.time)
    const key: AnyKey = type === 'fade'
      ? { t: at, type, to: 1, duration: 1000 }
      : type === 'subtitle'
        ? { t: at, type, text: t('subtitleDefault'), duration: 3000 }
        : { t: at, type, name: 'trigger' }
    edit((s) => addEventKey(s, key))
    selectItemAt(EVENTS, 'event', 'key', key)
  }

  function addMusic(asset: string) {
    const timeline = useTimeline()
    const clip: AnyClip = { start: timeline.snapTime(timeline.time), asset, volume: 1, loop: false, fadeIn: 0 }
    edit((s) => addClip(s, MUSIC, 'audio', clip))
    selectItemAt(MUSIC, 'audio', 'clip', clip)
  }

  async function addAnimClip(id: string, dict: string, clip: string) {
    const info = await fetchNui<Result & { length: number }>('animInfo', { dict, clip })
    if (!info?.ok) return fail(info)
    const timeline = useTimeline()
    const item: AnyClip = {
      start: timeline.snapTime(timeline.time), dict, clip,
      length: info.length, duration: info.length, loop: false,
    }
    edit((s) => addClip(s, id, 'anim', item))
    selectItemAt(id, 'anim', 'clip', item)
  }

  const selectedItem = computed<SelectedItem | null>(() => {
    const sel = useTimeline().selected
    const track = sel ? scene.value?.tracks.find((tr) => tr.id === sel.trackId) : undefined
    const item = sel && track ? (sel.kind === 'key' ? track.keys : track.clips)?.[sel.index] : undefined
    return sel && track && item ? { track, index: sel.index, kind: sel.kind, item } : null
  })

  /** Cambia la key o clip seleccionado. checkpoint = false en los arrastres (la instantánea se toma al empezar). */
  function updateSelected(patch: Partial<AnyKey> | Partial<AnyClip>, checkpoint = true) {
    const sel = selectedItem.value
    if (!sel) return false
    let index = -1
    edit((s) => {
      index = sel.kind === 'key'
        ? updateKey(s, sel.track.id, sel.index, patch as Partial<AnyKey>)
        : updateClip(s, sel.track.id, sel.index, patch as Partial<AnyClip>)
    }, checkpoint)
    if (index >= 0) useTimeline().select({ trackId: sel.track.id, index, kind: sel.kind })
    return index >= 0
  }

  function deleteSelected() {
    const sel = selectedItem.value
    if (!sel) return
    edit((s) => removeItem(s, sel.track.id, sel.index))
    useTimeline().select(null)
  }

  function setDuration(ms: number) {
    if (!Number.isFinite(ms) || ms < 1000) return
    setSettings({ duration: Math.round(ms) })
  }

  return {
    visible, studios, rows, loadingList, meta, scene, readOnly, lockedBy, dirty, savedAt, saving,
    selectedId, selected, pose, gizmoActive, showLabels, studio, entityCount, canEdit, selectedItem,
    show, hide, exit, refreshList, createScene, openScene, closeScene, deleteScene, save, setMeta, setSettings,
    spawn, updateEntity, setProp, setPose, removeEntity, select, pick, ground, startGizmo, onGizmo, focus,
    toggleLabels, undo, redo, checkpoint, schedulePoseRefresh, recordKey, addEvent, addMusic, addAnimClip,
    updateSelected, deleteSelected, setDuration,
  }
})
