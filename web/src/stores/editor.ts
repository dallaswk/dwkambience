import { defineStore } from 'pinia'
import { computed, ref, shallowRef, triggerRef } from 'vue'
import { setLocale, t } from '../i18n'
import type { MessageKey } from '../i18n'
import { fetchNui } from '../nui'
import {
  CAMERA, EVENTS, MUSIC, addClip, addEventKey, findTrack, keyIndexAt, nextEntityId, normalizeScene, sceneDuration,
  scenePeds, sceneWeight, setTrackKeys, upsertVisibilityKey, visibleAt,
  removeEntity as removeFromScene, removeItem, transformTrack, updateClip, updateKey, upsertPoseKey,
} from '../scene'
import type {
  AnyClip, AnyKey, CrowdDef, EntityKind, EventType, Key, LightDef, OpenResult, PtfxDef, ScreenDef, SetPieceData, SoundDef, TextDef, Result, SceneData, SceneEntity, SceneMeta, SceneRow,
  SceneType, Studio, Track, Vec3,
} from '../types'
import { LIGHT_STYLES, TEXT_STYLES } from '../catalog'
import { buildExport, type ExportFile } from '../transfer'
import { useHistory } from './history'
import { useConfirm } from './confirm'
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
  bad_type: 'errNotAScene',
  spawn_failed: 'errSpawnFailed',
  too_many_entities: 'errTooManyEntities',
  too_many_peds: 'errTooManyPeds',
  too_many_networked: 'networkLimit',
  not_ambience: 'errNotAmbience',
  too_large: 'errTooLarge',
  corrupt_scene: 'errCorrupt',
  db_error: 'errDb',
  db_not_ready: 'errDbNotReady',
  need_vehicle: 'errNeedVehicle',
  not_recordable: 'errNotRecordable',
  too_short: 'errTooShort',
  empty_set_piece: 'errEmptySetPiece',
  bad_set_piece: 'errBadSetPiece',
  unavailable: 'errUnavailable',
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
  const previewing = ref(false)
  const worldPreview = ref(false)
  const camSpeed = ref(1)
  const dialog = ref<'shortcuts' | 'about' | null>(null)
  const crowdPresets = ref<string[]>([])
  const maxPedsPerAmbience = ref(60)
  const placingPoints = ref(false) // clic en el viewport añade puntos a la multitud seleccionada
  const ptfxCatalog = ref<{ asset: string; effect: string }[]>([])
  const recording = ref(false)
  const multiSelected = ref<string[]>([]) // selección múltiple (Ctrl+clic) para set pieces
  const setPieces = ref<{ id: number; name: string }[]>([])
  const screenProps = ref<{ model: string; target: string }[]>([])
  const transfer = ref<{ mode: 'export'; name: string; json: string } | { mode: 'import' } | null>(null)

  const studio = computed<Studio | null>(() => (meta.value ? studios.value[meta.value.studio] ?? null : null))
  // Cada persona de una multitud cuenta para el límite del estudio
  const entityCount = computed(() => (scene.value ? sceneWeight(scene.value) : 0))
  const pedCount = computed(() => (scene.value ? scenePeds(scene.value) : 0))
  const networkedCount = computed(() => scene.value?.entities.filter((e) => e.networked).length ?? 0)
  const maxNetworked = computed(() => studio.value?.maxNetworked ?? 0)
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

  function show(payload: { studios: unknown; locale?: unknown; presets?: unknown; maxPedsPerAmbience?: unknown; ptfx?: unknown; screens?: unknown }) {
    setLocale(payload.locale)
    crowdPresets.value = Array.isArray(payload.presets) ? (payload.presets as string[]) : []
    if (typeof payload.maxPedsPerAmbience === 'number') maxPedsPerAmbience.value = payload.maxPedsPerAmbience
    ptfxCatalog.value = Array.isArray(payload.ptfx) ? (payload.ptfx as { asset: string; effect: string }[]) : []
    screenProps.value = Array.isArray(payload.screens) ? (payload.screens as { model: string; target: string }[]) : []
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
    worldPreview.value = false
    previewing.value = false
    placingPoints.value = false
    recording.value = false
    multiSelected.value = []
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

  async function spawn(kind: EntityKind, model: string, extra: Partial<SceneEntity> = {}) {
    if (!scene.value || !canEdit.value) return
    if (studio.value && entityCount.value >= studio.value.maxEntities) return fail({ ok: false, error: 'too_many_entities' })

    const point = await fetchNui<Result & { pos: Vec3; rot: Vec3 }>('spawnPoint', { kind, model })
    if (!point?.ok) return fail(point)

    const { id, label } = nextEntityId(scene.value, kind)
    const entity: SceneEntity = { id, kind, model, label, props: {}, networked: false, ...extra }
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

  /** Punto que mira la cámara (sobre el mapa si lo hay) */
  async function cameraPoint(): Promise<Vec3 | null> {
    const result = await fetchNui<Result & { pos: Vec3 }>('cameraPoint')
    return result?.ok ? result.pos : null
  }

  function pedsLeft() {
    return Math.min(
      meta.value?.type === 'ambience' ? maxPedsPerAmbience.value - pedCount.value : Infinity,
      studio.value ? studio.value.maxEntities - entityCount.value : Infinity,
    )
  }

  async function spawnSound(asset: string) {
    if (!scene.value || !canEdit.value) return
    const pos = await cameraPoint()
    if (!pos) return
    const { id, label } = nextEntityId(scene.value, 'sound')
    const entity: SceneEntity = { id, kind: 'sound', label: `${label} · ${asset}`.slice(0, 64), props: {}, networked: false,
      sound: { asset, volume: 1, range: 30, loop: true } }
    const at = useTimeline().snapTime(useTimeline().time)
    edit((s) => {
      s.entities = [...s.entities, entity]
      upsertPoseKey(s, id, 'transform', { t: at, pos: [pos[0], pos[1], pos[2] + 1], rot: [0, 0, 0] })
    })
    select(id)
  }

  async function spawnCrowd(preset: string) {
    if (!scene.value || !canEdit.value) return
    const count = Math.min(10, pedsLeft())
    if (count < 1) return fail({ ok: false, error: meta.value?.type === 'ambience' ? 'too_many_peds' : 'too_many_entities' })
    const pos = await cameraPoint()
    if (!pos) return
    const { id, label } = nextEntityId(scene.value, 'crowd')
    const crowd: CrowdDef = { preset, count, seed: newSeed(), points: [pos], spread: 4, facing: 'random' }
    const entity: SceneEntity = { id, kind: 'crowd', label, props: {}, networked: false, crowd }
    edit((s) => {
      s.entities = [...s.entities, entity]
    })
    select(id)
  }

  const newSeed = () => 1 + Math.floor(Math.random() * 2147483645)

  function updateCrowd(id: string, patch: Partial<CrowdDef>) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity?.crowd) return
    const crowd = { ...entity.crowd, ...patch }
    if (crowd.facing !== 'point') delete crowd.lookAt
    if (!crowd.models?.length) delete crowd.models
    if (!crowd.scenario) delete crowd.scenario
    updateEntity(id, { crowd })
  }

  function regenerateCrowd(id: string) {
    updateCrowd(id, { seed: newSeed() })
  }

  async function addCrowdPoint(id: string, pos?: Vec3) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity?.crowd || entity.crowd.points.length >= 32) return
    const point = pos ?? (await cameraPoint())
    if (point) updateCrowd(id, { points: [...entity.crowd.points, point] })
  }

  function removeCrowdPoint(id: string, index: number) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity?.crowd || entity.crowd.points.length <= 1) return
    updateCrowd(id, { points: entity.crowd.points.filter((_, i) => i !== index) })
  }

  async function crowdLookAtCamera(id: string) {
    const point = await cameraPoint()
    if (point) updateCrowd(id, { facing: 'point', lookAt: point })
  }

  /** Clic en el viewport en modo "colocar puntos" */
  async function placePoint(x: number, y: number) {
    const id = selectedId.value
    if (!id) return
    const result = await fetchNui<Result & { pos: Vec3 }>('worldPoint', { x, y })
    if (result?.ok) addCrowdPoint(id, result.pos)
  }

  function updateSound(id: string, patch: Partial<SoundDef>) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (entity?.sound) updateEntity(id, { sound: { ...entity.sound, ...patch } })
  }

  async function moveToCamera(id: string) {
    const pos = await cameraPoint()
    if (pos) setPose(id, [pos[0], pos[1], pos[2] + 1], [0, 0, 0])
  }

  // --- Texto 3D, luces y partículas ---------------------------------------------------

  async function spawnFx(kind: 'text' | 'light' | 'ptfx', def: TextDef | LightDef | PtfxDef, labelSuffix = '') {
    if (!scene.value || !canEdit.value) return
    const pos = await cameraPoint()
    if (!pos) return
    const { id, label } = nextEntityId(scene.value, kind)
    const entity: SceneEntity = { id, kind, label: `${label}${labelSuffix}`.slice(0, 64), props: {}, networked: false, [kind]: def }
    const at = useTimeline().snapTime(useTimeline().time)
    edit((s) => {
      s.entities = [...s.entities, entity]
      upsertPoseKey(s, id, 'transform', { t: at, pos: [pos[0], pos[1], pos[2] + 1.5], rot: [0, 0, 0] })
    })
    select(id)
  }

  function spawnText(style: string) {
    const s = TEXT_STYLES[style] ?? TEXT_STYLES.normal
    spawnFx('text', { content: t('textDefault'), color: s.color, scale: s.scale, font: s.font, outline: true, backface: false })
  }

  function spawnLight(style: string) {
    spawnFx('light', { ...(LIGHT_STYLES[style] ?? LIGHT_STYLES.warm) })
  }

  function spawnPtfx(key: string) {
    const [asset, effect] = key.split('/')
    spawnFx('ptfx', { asset, effect, scale: 1 }, ` · ${effect}`)
  }

  const defaultScreen = (): ScreenDef => ({ content: t('screenDefault'), color: [255, 255, 255], background: [0, 0, 0], scale: 1, font: 4 })

  function spawnScreen(model: string) {
    spawn('prop', model, { screen: defaultScreen() })
  }

  function isScreenModel(model?: string) {
    return !!model && screenProps.value.some((s) => s.model === model)
  }

  function setScreen(id: string, screen: ScreenDef | undefined) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity) return
    const next = { ...entity }
    if (screen) next.screen = screen
    else delete next.screen
    edit((s) => {
      s.entities = s.entities.map((e) => (e.id === id ? next : e))
    })
  }

  function updateScreen(id: string, patch: Partial<ScreenDef>) {
    const current = scene.value?.entities.find((e) => e.id === id)?.screen
    setScreen(id, { ...(current ?? defaultScreen()), ...patch })
  }

  /** Cambia la definición de texto, luz o partículas de una entidad */
  function updateDef(id: string, kind: 'text' | 'light' | 'ptfx', patch: Partial<TextDef & LightDef & PtfxDef>) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    const current = entity?.[kind]
    if (!current) return
    const next = { ...current, ...patch } as TextDef & LightDef & PtfxDef
    if (kind === 'light' && next.type === 'point') {
      delete next.angle
      delete next.falloff
    } else if (kind === 'light' && next.type === 'spot') {
      next.angle ??= 30
      next.falloff ??= 2
    }
    updateEntity(id, { [kind]: next })
  }

  /** Key de visibilidad en el instante actual que invierte el estado (mostrar/ocultar desde aquí) */
  function toggleVisibility(id: string) {
    if (!scene.value) return
    const at = useTimeline().snapTime(useTimeline().time)
    const visible = visibleAt(scene.value, id, at)
    const hasKeys = !!findTrack(scene.value, id, 'visibility')?.keys?.length
    edit((s) => {
      // Sin keys previas, se fija también el estado inicial: si no, la primera key mandaría desde t = 0
      if (!hasKeys && at > 0) upsertVisibilityKey(s, id, 0, visible)
      upsertVisibilityKey(s, id, at, !visible)
    })
  }

  // --- Grabación en vivo --------------------------------------------------------------

  async function record() {
    const entity = selected.value
    if (!entity || !canEdit.value || recording.value) return
    if (entity.kind !== 'ped' && entity.kind !== 'vehicle') return fail({ ok: false, error: 'not_recordable' })
    const timeline = useTimeline()
    timeline.pause()
    const result = await fetchNui<Result>('record', { id: entity.id, startT: timeline.snapTime(timeline.time), hint: t('recHint') })
    if (result && result.ok === false) fail(result)
  }

  function onRecording(data: { active: boolean; id: string; keys?: unknown; error?: string }) {
    recording.value = data.active
    if (data.active) return
    const keys = Array.isArray(data.keys) ? (data.keys as Key[]) : []
    if (!keys.length) return fail({ ok: false, error: data.error ?? 'too_short' })
    const from = keys[0].t
    const to = keys[keys.length - 1].t
    // Las keys grabadas sustituyen a las que había en ese tramo de la pista
    edit((s) => {
      const kept = ((transformTrack(s, data.id)?.keys ?? []) as Key[]).filter((k) => k.t < from || k.t > to)
      setTrackKeys(s, data.id, 'transform', [...kept, ...keys])
    })
    toasts.push(t('recDone', { n: keys.length }), 'success')
    useTimeline().setTime(to)
  }

  // --- Selección múltiple y set pieces ---------------------------------------------

  /** Ctrl+clic: añade o quita una entidad de la selección múltiple */
  function toggleMulti(id: string) {
    const set = new Set(multiSelected.value)
    if (selectedId.value && !set.size) set.add(selectedId.value)
    if (set.has(id)) set.delete(id)
    else set.add(id)
    multiSelected.value = [...set]
    selectedId.value = id
    useTimeline().select(null)
    fetchNui('select', { id })
    refreshPose()
  }

  const selectionIds = computed(() => {
    const ids = new Set(multiSelected.value)
    if (selectedId.value) ids.add(selectedId.value)
    return [...ids]
  })

  async function loadSetPieces() {
    const result = await fetchNui<Result & { items: { id: number; name: string }[] }>('setPieces')
    if (result?.ok) setPieces.value = Array.isArray(result.items) ? result.items : []
  }

  /** Guarda la selección (entidades y sus pistas) como set piece con nombre */
  async function saveSetPiece() {
    if (!scene.value) return
    const ids = selectionIds.value
    if (!ids.length) return fail({ ok: false, error: 'empty_set_piece' })
    const name = await useConfirm().askText({ title: t('saveSetPiece'), body: t('setPieceNameHint', { n: ids.length }), confirm: t('save'), placeholder: t('setPieceName') })
    if (!name) return

    const entities = scene.value.entities.filter((e) => ids.includes(e.id))
    const tracks = scene.value.tracks.filter((tr) => ids.includes(tr.target))
    // Origen: media de las posiciones iniciales; inicio: la primera key o clip
    const points: Vec3[] = []
    let start = Infinity
    for (const e of entities) {
      const first = (transformTrack(scene.value, e.id)?.keys?.[0] as Key | undefined)?.pos ?? e.crowd?.points[0]
      if (first) points.push(first)
    }
    for (const tr of tracks) {
      for (const k of tr.keys ?? []) start = Math.min(start, k.t)
      for (const c of tr.clips ?? []) start = Math.min(start, c.start)
    }
    const origin: Vec3 = points.length
      ? [0, 1, 2].map((i) => points.reduce((sum, p) => sum + p[i], 0) / points.length) as Vec3
      : [0, 0, 0]
    const data: SetPieceData = { schema: scene.value.schema, origin, start: Number.isFinite(start) ? start : 0, entities, tracks }

    const result = await fetchNui<Result>('setPieceSave', { name, data })
    if (!result?.ok) return fail(result)
    toasts.push(t('setPieceSaved', { name }), 'success')
    loadSetPieces()
  }

  /** Inserta una set piece donde mira la cámara y a partir del instante actual, con ids nuevos */
  async function insertSetPiece(id: number) {
    if (!scene.value || !canEdit.value) return
    const result = await fetchNui<Result & { data: SetPieceData }>('setPieceGet', { id })
    if (!result?.ok) return fail(result)
    const piece = normalizeScene({ schema: result.data.schema, settings: scene.value.settings, entities: result.data.entities, tracks: result.data.tracks }, 'cutscene')
    const weight = piece.entities.reduce((sum, e) => sum + (e.kind === 'crowd' ? e.crowd?.count ?? 0 : ['ped', 'vehicle', 'prop'].includes(e.kind) ? 1 : 0), 0)
    if (weight > pedsLeft()) return fail({ ok: false, error: 'too_many_entities' })
    const target = await cameraPoint()
    if (!target) return

    const origin = result.data.origin
    const offset = [target[0] - origin[0], target[1] - origin[1], target[2] - origin[2]]
    const move = (p: Vec3): Vec3 => [p[0] + offset[0], p[1] + offset[1], p[2] + offset[2]]
    const dt = useTimeline().snapTime(useTimeline().time) - (result.data.start ?? 0)
    let firstId: string | null = null

    edit((s) => {
      const idMap = new Map<string, string>()
      for (const e of piece.entities) {
        const { id: newId } = nextEntityId(s, e.kind)
        idMap.set(e.id, newId)
        firstId ??= newId
        const copy: SceneEntity = { ...e, id: newId }
        if (e.crowd) copy.crowd = { ...e.crowd, points: e.crowd.points.map(move), lookAt: e.crowd.lookAt && move(e.crowd.lookAt) }
        if (copy.crowd && !copy.crowd.lookAt) delete copy.crowd.lookAt
        s.entities = [...s.entities, copy]
      }
      for (const tr of piece.tracks) {
        const target = idMap.get(tr.target)
        if (!target) continue
        s.tracks = [...s.tracks, {
          ...tr,
          id: `${tr.id.split('_')[0]}_${target}`,
          target,
          keys: tr.keys?.map((k) => ({ ...k, t: Math.max(0, k.t + dt), ...('pos' in k ? { pos: move(k.pos) } : {}) })),
          clips: tr.clips?.map((c) => ({ ...c, start: Math.max(0, c.start + dt) })),
        }]
      }
    })
    if (firstId) select(firstId)
    toasts.push(t('setPieceInserted'), 'success')
  }

  async function deleteSetPiece(id: number, name: string) {
    const ok = await useConfirm().ask({ title: t('deleteSetPieceTitle', { name }), body: t('deleteSetPieceBody'), confirm: t('delete'), danger: true })
    if (!ok) return
    const result = await fetchNui<Result>('setPieceDelete', { id })
    if (!result?.ok) return fail(result)
    loadSetPieces()
  }

  /** Pone o quita una entidad en red. Por encima del límite avisa y la deja local. */
  async function setNetworked(id: string, networked: boolean) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity || !canEdit.value) return
    if (networked && networkedCount.value >= maxNetworked.value) {
      toasts.push(t('networkLimit'), 'warning', 6000)
      return
    }
    let props = entity.props
    if (networked && entity.kind === 'vehicle') {
      const result = await fetchNui<Result & { type: string }>('vehicleType', { model: entity.model })
      props = { ...props, vehicleType: result?.ok ? result.type : 'automobile' }
    }
    updateEntity(id, { networked, props })
  }

  // --- Exportar / importar ------------------------------------------------------------

  /** Exporta la escena abierta (con los cambios sin guardar) o, con id, una de la lista */
  async function exportScene(id?: number) {
    if (id === undefined || id === meta.value?.id) {
      if (!scene.value || !meta.value) return
      const file = buildExport(meta.value.name, meta.value.type, meta.value.group, scene.value)
      transfer.value = { mode: 'export', name: meta.value.name, json: JSON.stringify(file, null, 2) }
      return
    }
    const result = await fetchNui<Result & { name: string; type: SceneType; group: string | null; data: unknown }>('export', { id })
    if (!result?.ok) return fail(result)
    const data = normalizeScene(result.data, result.type)
    transfer.value = { mode: 'export', name: result.name, json: JSON.stringify(buildExport(result.name, result.type, result.group ?? null, data), null, 2) }
  }

  function openImport() {
    transfer.value = { mode: 'import' }
  }

  async function importScene(file: ExportFile, name: string, group: string) {
    const result = await fetchNui<OpenResult>('import', { name, group, type: file.type, data: file.data })
    if (!result?.ok) return fail(result)
    transfer.value = null
    adopt(result)
    toasts.push(t('imported', { name }), 'success')
    refreshList()
  }

  // --- Ambience: zona, horario e interruptor ---------------------------------------

  function setTrigger(patch: Partial<NonNullable<SceneData['settings']['trigger']>>) {
    const current = scene.value?.settings.trigger
    if (!current) return
    const trigger = { ...current, ...patch }
    if (trigger.exit < trigger.enter) trigger.exit = trigger.enter
    setSettings({ trigger })
  }

  async function centerZoneOnCamera() {
    const pos = await cameraPoint()
    if (!pos || !scene.value) return
    const current = scene.value.settings.trigger
    setSettings({ trigger: { enter: current?.enter ?? 80, exit: current?.exit ?? 100, center: pos } })
  }

  /** Interruptor on/off: se aplica al momento en el servidor, sin guardar la escena */
  async function setActive(id: number, active: boolean) {
    const result = await fetchNui<Result & { active: boolean }>('setActive', { id, active })
    if (!result?.ok) return fail(result)
    if (meta.value?.id === id) meta.value = { ...meta.value, active: result.active }
    rows.value = rows.value.map((r) => (r.id === id ? { ...r, active: result.active } : r))
    toasts.push(t(result.active ? 'ambienceOn' : 'ambienceOff'), 'success')
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
    multiSelected.value = []
    pose.value = null
    fetchNui('select', { id })
    if (id) {
      useTimeline().select(null)
      refreshPose()
    }
  }

  async function pick(x: number, y: number, additive = false) {
    const result = await fetchNui<Result & { id: string | null }>('pick', { x, y })
    if (additive && result?.id) return toggleMulti(result.id)
    multiSelected.value = []
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

  /** Copia una entidad y sus pistas con id nuevo, desplazada 1 m en X para que no se solapen. */
  function duplicateEntity(id: string) {
    const source = scene.value?.entities.find((e) => e.id === id)
    if (!scene.value || !source || !canEdit.value) return
    if (pedsLeft() < Math.max(1, source.crowd?.count ?? 1)) return fail({ ok: false, error: 'too_many_entities' })

    const { id: newId } = nextEntityId(scene.value, source.kind)
    const copy: SceneEntity = { ...source, id: newId, label: `${source.label}${t('copySuffix')}`.slice(0, 64) }
    if (source.crowd) copy.crowd = { ...source.crowd, points: source.crowd.points.map((p) => [p[0] + 1, p[1], p[2]] as Vec3) }
    edit((s) => {
      s.entities = [...s.entities, copy]
      const tracks = s.tracks
        .filter((tr) => tr.target === id)
        .map((tr) => ({
          ...tr,
          id: tr.id.replace(id, newId),
          target: newId,
          keys: tr.keys?.map((k) => ('pos' in k ? { ...k, pos: [k.pos[0] + 1, k.pos[1], k.pos[2]] as Vec3 } : k)),
          clips: tr.clips?.map((c) => ({ ...c })),
        }))
      s.tracks = [...s.tracks, ...tracks]
    })
    select(newId)
  }

  function deleteSelection() {
    if (selectedItem.value) deleteSelected()
    else if (selectedId.value) removeEntity(selectedId.value)
  }

  function toggleWorldPreview() {
    worldPreview.value = !worldPreview.value
    fetchNui('previewWorld', { active: worldPreview.value })
  }

  function cameraToPlayer() {
    fetchNui('cameraToPlayer')
  }

  function setCamSpeed(multiplier: number) {
    camSpeed.value = multiplier
    fetchNui('camSpeed', { multiplier })
  }

  /** Reproduce la cutscene tal como está (sin guardar) con letterbox, fundidos y música. */
  async function preview() {
    if (!scene.value || meta.value?.type !== 'cutscene' || previewing.value || sceneDuration(scene.value) <= 0) return
    useTimeline().pause()
    syncNow()
    const result = await fetchNui<Result>('preview', { data: scene.value })
    if (result && result.ok === false) fail(result)
  }

  function onPreview(data: { active: boolean }) {
    previewing.value = data.active
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
    screenProps, spawnScreen, isScreenModel, setScreen, updateScreen,
    transfer, exportScene, openImport, importScene, networkedCount, maxNetworked, setNetworked,
    ptfxCatalog, recording, multiSelected, selectionIds, setPieces, spawnText, spawnLight, spawnPtfx, updateDef,
    toggleVisibility, record, onRecording, toggleMulti, loadSetPieces, saveSetPiece, insertSetPiece, deleteSetPiece,
    crowdPresets, maxPedsPerAmbience, placingPoints, pedCount, spawnSound, spawnCrowd, updateCrowd, regenerateCrowd,
    addCrowdPoint, removeCrowdPoint, crowdLookAtCamera, placePoint, updateSound, moveToCamera, setTrigger,
    centerZoneOnCamera, setActive,
    previewing, worldPreview, camSpeed, dialog, duplicateEntity, deleteSelection, toggleWorldPreview, cameraToPlayer,
    setCamSpeed, preview, onPreview,
    toggleLabels, undo, redo, checkpoint, schedulePoseRefresh, recordKey, addEvent, addMusic, addAnimClip,
    updateSelected, deleteSelected, setDuration,
  }
})
