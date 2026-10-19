import { defineStore } from 'pinia'
import { computed, ref, shallowRef, triggerRef } from 'vue'
import { setLocale, t } from '../i18n'
import type { MessageKey } from '../i18n'
import { fetchNui } from '../nui'
import {
  baseTransform, nextEntityId, normalizeScene, removeEntity as removeFromScene, setBaseTransform,
} from '../scene'
import type { EntityKind, OpenResult, Result, SceneData, SceneEntity, SceneMeta, SceneRow, SceneType, Studio, Vec3 } from '../types'
import { useToasts } from './toasts'

const ERRORS: Record<string, MessageKey> = {
  forbidden: 'errForbidden',
  not_locked: 'errLocked',
  locked: 'errLocked',
  not_found: 'errNotFound',
  bad_name: 'errBadName',
  bad_group: 'errBadGroup',
  invalid_model: 'errInvalidModel',
  spawn_failed: 'errSpawnFailed',
  too_many_entities: 'errTooManyEntities',
  too_large: 'errTooLarge',
  corrupt_scene: 'errCorrupt',
  db_error: 'errDb',
}

// Los errores de validación del servidor ('invalid: ...') se muestran tal cual
const errorText = (code?: string) => (code ? (ERRORS[code] ? t(ERRORS[code]) : code) : t('errUnknown'))

function toStudios(raw: unknown): Record<number, Studio> {
  // Lua serializa { [1] = ... } como array JSON
  if (Array.isArray(raw)) return Object.fromEntries(raw.map((s, i) => [i + 1, s as Studio]))
  return (raw ?? {}) as Record<number, Studio>
}

export const useEditor = defineStore('editor', () => {
  const toasts = useToasts()

  const visible = ref(false)
  const studios = ref<Record<number, Studio>>({})
  const rows = ref<SceneRow[]>([])
  const loadingList = ref(false)

  const meta = ref<SceneMeta | null>(null)
  // Documento grande fuera de la reactividad profunda: se muta en sitio y se avisa con touch()
  // Regla: se sustituye el objeto que cambia (entidad, key, settings), nunca se muta en sitio
  const scene = shallowRef<SceneData | null>(null)
  const readOnly = ref(false)
  const lockedBy = ref<string | null>(null)
  const dirty = ref(false)
  const savedAt = ref<number | null>(null)
  const saving = ref(false)

  const selectedId = ref<string | null>(null)
  const gizmoActive = ref(false)
  const showLabels = ref(true)

  const studio = computed<Studio | null>(() => (meta.value ? studios.value[meta.value.studio] ?? null : null))
  const entityCount = computed(() => scene.value?.entities.length ?? 0)
  const selected = computed<SceneEntity | null>(() => scene.value?.entities.find((e) => e.id === selectedId.value) ?? null)
  const canEdit = computed(() => !!scene.value && !readOnly.value)

  function touch() {
    triggerRef(scene)
    dirty.value = true
  }

  function fail(result: Result | undefined, fallback?: string) {
    toasts.push(errorText(result?.error ?? fallback), 'error')
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
    meta.value = null
    scene.value = null
    selectedId.value = null
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
    meta.value = result.meta
    scene.value = normalizeScene(result.data, result.meta.type)
    readOnly.value = result.readOnly
    lockedBy.value = result.lockedBy ?? null
    selectedId.value = null
    dirty.value = false
    savedAt.value = null

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
    if (!scene.value || readOnly.value) return
    scene.value.settings = { ...scene.value.settings, ...patch }
    touch()
  }

  // --- Entidades ------------------------------------------------------------

  async function pushEntity(entity: SceneEntity) {
    if (!scene.value) return false
    const key = baseTransform(scene.value, entity.id)
    const result = await fetchNui<Result>('applyEntity', { entity, pos: key?.pos, rot: key?.rot })
    if (!result?.ok) fail(result)
    return !!result?.ok
  }

  async function spawn(kind: EntityKind, model: string) {
    if (!scene.value || !canEdit.value) return
    if (studio.value && entityCount.value >= studio.value.maxEntities) return fail({ ok: false, error: 'too_many_entities' })

    const point = await fetchNui<Result & { pos: Vec3; rot: Vec3 }>('spawnPoint', { kind, model })
    if (!point?.ok) return fail(point)

    const { id, label } = nextEntityId(scene.value, kind)
    const entity: SceneEntity = { id, kind, model, label, props: {}, networked: false }
    scene.value.entities = [...scene.value.entities, entity]
    setBaseTransform(scene.value, id, point.pos, point.rot)

    if (!(await pushEntity(entity))) {
      removeFromScene(scene.value, id)
      triggerRef(scene)
      return
    }
    touch()
    select(id)
  }

  function updateEntity(id: string, patch: Partial<Omit<SceneEntity, 'id' | 'kind'>>) {
    if (!scene.value || !canEdit.value) return
    const index = scene.value.entities.findIndex((e) => e.id === id)
    if (index < 0) return
    const entity = { ...scene.value.entities[index], ...patch }
    scene.value.entities = scene.value.entities.map((e, i) => (i === index ? entity : e))
    touch()
    pushEntity(entity)
  }

  function setProp(id: string, key: string, value: SceneEntity['props'][string] | undefined) {
    const entity = scene.value?.entities.find((e) => e.id === id)
    if (!entity || !canEdit.value) return
    const props = { ...entity.props }
    if (value === undefined || value === '') delete props[key]
    else props[key] = value
    updateEntity(id, { props })
  }

  function setTransform(id: string, pos: Vec3, rot: Vec3, sync = true) {
    if (!scene.value || !canEdit.value) return
    setBaseTransform(scene.value, id, pos, rot)
    touch()
    const entity = scene.value.entities.find((e) => e.id === id)
    if (sync && entity) pushEntity(entity)
  }

  async function removeEntity(id: string) {
    if (!scene.value || !canEdit.value) return
    removeFromScene(scene.value, id)
    touch()
    if (selectedId.value === id) selectedId.value = null
    await fetchNui('removeEntity', { id })
  }

  function select(id: string | null) {
    selectedId.value = id
    fetchNui('select', { id })
  }

  async function pick(x: number, y: number) {
    const result = await fetchNui<Result & { id: string | null }>('pick', { x, y })
    selectedId.value = result?.id ?? null
  }

  async function ground(id: string) {
    if (!canEdit.value) return
    const result = await fetchNui<Result & { pos: Vec3; rot: Vec3 }>('ground', { id })
    if (result?.ok) setTransform(id, result.pos, result.rot, false)
  }

  async function startGizmo(id: string, mode: 'translate' | 'rotate') {
    if (!canEdit.value || gizmoActive.value) return
    const result = await fetchNui<Result>('gizmo', { id, mode })
    if (result && result.ok === false) fail(result)
  }

  function onGizmo(data: { active: boolean; id: string; confirmed?: boolean; pos?: Vec3; rot?: Vec3 }) {
    gizmoActive.value = data.active
    if (!data.active && data.confirmed && data.pos && data.rot) setTransform(data.id, data.pos, data.rot, false)
  }

  function focus(id: string) {
    fetchNui('focus', { id })
  }

  function toggleLabels() {
    showLabels.value = !showLabels.value
    fetchNui('labels', { enabled: showLabels.value })
  }

  return {
    visible, studios, rows, loadingList, meta, scene, readOnly, lockedBy, dirty, savedAt, saving,
    selectedId, selected, gizmoActive, showLabels, studio, entityCount, canEdit,
    show, hide, exit, refreshList, createScene, openScene, closeScene, deleteScene, save, setMeta, setSettings,
    spawn, updateEntity, setProp, setTransform, removeEntity, select, pick, ground, startGizmo, onGizmo, focus,
    toggleLabels,
  }
})
