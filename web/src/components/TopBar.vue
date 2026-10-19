<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { LOCALES_AVAILABLE, chooseLocale, locale, t } from '../i18n'
import type { MessageKey } from '../i18n'
import { useEditor } from '../stores/editor'
import { useHistory } from '../stores/history'
import { useTimeline } from '../stores/timeline'
import type { EntityKind } from '../types'
import Icon from './Icon.vue'
import PaletteMenu from './PaletteMenu.vue'
import SetPieceMenu from './SetPieceMenu.vue'

const editor = useEditor()
const timeline = useTimeline()
const history = useHistory()
const emit = defineEmits<{ closeScene: []; exit: [] }>()

const open = ref<string | null>(null)

type MenuItem =
  | { kind: 'item'; label: string; action: () => void; shortcut?: string; disabled?: boolean; checked?: boolean }
  | { kind: 'header'; label: string }
  | { kind: 'sep' }

interface Menu {
  id: string
  label: MessageKey
  items: MenuItem[]
}

const item = (label: string, action: () => void, extra: Partial<Extract<MenuItem, { kind: 'item' }>> = {}): MenuItem => ({ kind: 'item', label, action, ...extra })
const sep: MenuItem = { kind: 'sep' }
const header = (label: string): MenuItem => ({ kind: 'header', label })

const LANGUAGE_NAMES: Record<string, string> = { es: 'Español', en: 'English' }
const SPEEDS: { value: number; label: MessageKey }[] = [
  { value: 0.35, label: 'speedSlow' },
  { value: 1, label: 'speedNormal' },
  { value: 3, label: 'speedFast' },
]

const menus = computed<Menu[]>(() => {
  const hasScene = !!editor.scene
  const canEdit = editor.canEdit
  const id = editor.selectedId
  const isCutscene = editor.meta?.type === 'cutscene'
  const hasSelection = !!id || !!editor.selectedItem

  return [
    {
      id: 'file',
      label: 'file',
      items: [
        item(t('newOpenScene'), () => emit('closeScene'), { disabled: !hasScene }),
        item(t('save'), editor.save, { shortcut: 'Ctrl+S', disabled: !canEdit || !editor.dirty }),
        item(t('closeScene'), () => emit('closeScene'), { disabled: !hasScene }),
        sep,
        item(t('historyMenu'), editor.openHistory, { disabled: !hasScene }),
        item(t('exportScene'), () => editor.exportScene(), { disabled: !hasScene }),
        item(t('importScene'), editor.openImport),
        sep,
        item(t('exitEditor'), () => emit('exit')),
      ],
    },
    {
      id: 'edit',
      label: 'menuEdit',
      items: [
        item(t('undo'), editor.undo, { shortcut: 'Ctrl+Z', disabled: !canEdit || !history.canUndo }),
        item(t('redo'), editor.redo, { shortcut: 'Ctrl+Y', disabled: !canEdit || !history.canRedo }),
        sep,
        item(t('duplicateEntity'), () => id && editor.duplicateEntity(id), { shortcut: 'Ctrl+D', disabled: !canEdit || !id }),
        item(t('deleteSelection'), editor.deleteSelection, { shortcut: t('kbDelete'), disabled: !canEdit || !hasSelection }),
        item(t('deselect'), () => (editor.selectedItem ? timeline.select(null) : editor.select(null)), { shortcut: 'Esc', disabled: !hasSelection }),
      ],
    },
    {
      id: 'view',
      label: 'view',
      items: [
        item(t('entityLabels'), editor.toggleLabels, { checked: editor.showLabels }),
        ...(isCutscene ? [item(t('tlCameraView'), () => timeline.setCameraView(!timeline.cameraView), { checked: timeline.cameraView })] : []),
        sep,
        item(t('zoomTimelineIn'), () => (timeline.pxPerSec = Math.min(800, timeline.pxPerSec * 1.4)), { shortcut: t('kbCtrlWheel'), disabled: !hasScene }),
        item(t('zoomTimelineOut'), () => (timeline.pxPerSec = Math.max(10, timeline.pxPerSec / 1.4)), { disabled: !hasScene }),
      ],
    },
    {
      id: 'tools',
      label: 'menuTools',
      items: [
        item(t('move'), () => id && editor.startGizmo(id, 'translate'), { disabled: !canEdit || !id }),
        item(t('rotate'), () => id && editor.startGizmo(id, 'rotate'), { disabled: !canEdit || !id }),
        item(t('ground'), () => id && editor.ground(id), { disabled: !canEdit || !id }),
        item(t('focusCamera'), () => id && editor.focus(id), { shortcut: 'F', disabled: !id }),
        sep,
        item(t('recordKey'), editor.recordKey, { shortcut: 'K', disabled: !canEdit }),
        item(t('rec'), editor.record, { shortcut: 'R', disabled: !canEdit || !['ped', 'vehicle'].includes(editor.selected?.kind ?? '') }),
        item(t('toggleVisibility'), () => id && editor.toggleVisibility(id), { shortcut: 'H', disabled: !canEdit || !id }),
        item(t('saveSetPiece'), editor.saveSetPiece, { disabled: !canEdit || !editor.selectionIds.length }),
        item(t('groupAction'), editor.groupSelection, { shortcut: 'Ctrl+G', disabled: !canEdit || !editor.selectionIds.length }),
        item(t('evFadeOut'), () => editor.addEvent('fade'), { disabled: !canEdit }),
        item(t('evSubtitle'), () => editor.addEvent('subtitle'), { disabled: !canEdit }),
        item(t('evTrigger'), () => editor.addEvent('trigger'), { disabled: !canEdit }),
      ],
    },
    {
      id: 'world',
      label: 'menuWorld',
      items: [
        item(t('previewWorld'), editor.toggleWorldPreview, { checked: editor.worldPreview, disabled: !hasScene }),
        item(t('cameraToPlayer'), editor.cameraToPlayer),
        ...(isCutscene ? [sep, item(t('previewCutscene'), editor.preview, { shortcut: 'P', disabled: !hasScene })] : []),
      ],
    },
    {
      id: 'settings',
      label: 'menuSettings',
      items: [
        header(t('language')),
        ...LOCALES_AVAILABLE.map((l) => item(LANGUAGE_NAMES[l], () => chooseLocale(l), { checked: locale.value === l })),
        sep,
        header(t('cameraSpeed')),
        ...SPEEDS.map((s) => item(t(s.label), () => editor.setCamSpeed(s.value), { checked: editor.camSpeed === s.value })),
        sep,
        item(t('tlAutoKey'), () => (timeline.autoKey = !timeline.autoKey), { checked: timeline.autoKey }),
        item(t('tlSnap'), () => (timeline.snap = !timeline.snap), { checked: timeline.snap }),
      ],
    },
    {
      id: 'help',
      label: 'menuHelp',
      items: [
        item(t('shortcuts'), () => (editor.dialog = 'shortcuts'), { shortcut: '?' }),
        item(t('about'), () => (editor.dialog = 'about')),
      ],
    },
  ]
})

const PALETTES = computed<{ kind: EntityKind | 'screen'; label: MessageKey }[]>(() => [
  { kind: 'ped', label: 'palettePed' },
  { kind: 'vehicle', label: 'paletteVehicle' },
  { kind: 'prop', label: 'paletteProp' },
  { kind: 'screen', label: 'paletteScreen' },
  { kind: 'text', label: 'paletteText' },
  { kind: 'light', label: 'paletteLight' },
  { kind: 'ptfx', label: 'palettePtfx' },
  { kind: 'sound', label: 'paletteSound' },
  { kind: 'crowd', label: 'paletteCrowd' },
])

function spawnFrom(kind: EntityKind | 'screen', model: string) {
  if (kind === 'screen') editor.spawnScreen(model)
  else if (kind === 'sound') editor.spawnSound(model)
  else if (kind === 'crowd') editor.spawnCrowd(model)
  else if (kind === 'text') editor.spawnText(model)
  else if (kind === 'light') editor.spawnLight(model)
  else if (kind === 'ptfx') editor.spawnPtfx(model)
  else editor.spawn(kind as EntityKind, model)
}

const savedLabel = computed(() => {
  if (editor.saving) return t('saving')
  if (editor.readOnly) return t('readOnly')
  if (editor.dirty) return t('unsaved')
  if (!editor.savedAt) return ''
  const d = new Date(editor.savedAt)
  return t('savedAt', { time: `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` })
})

// Presupuesto: verde por encima de 50 fps, aviso entre 30 y 50, peligro por debajo
const perfLevel = computed(() => {
  const fps = editor.perf?.fps ?? 60
  return fps < 30 ? 'danger' : fps < 50 ? 'warn' : ''
})

const nearLimit = computed(() => !!editor.studio && editor.entityCount >= editor.studio.maxEntities * 0.9)

function toggle(name: string) {
  open.value = open.value === name ? null : name
}

// Con un menú abierto, pasar el ratón por otro lo abre (como en una barra de menús de escritorio)
function hover(name: string) {
  if (open.value && open.value !== name && menus.value.some((m) => m.id === open.value)) open.value = name
}

function run(entry: Extract<MenuItem, { kind: 'item' }>) {
  if (entry.disabled) return
  open.value = null
  entry.action()
}

function onDocClick(e: MouseEvent) {
  if (!(e.target as HTMLElement).closest('.menu-root')) open.value = null
}
onMounted(() => document.addEventListener('mousedown', onDocClick))
onBeforeUnmount(() => document.removeEventListener('mousedown', onDocClick))
</script>

<template>
  <header class="topbar">
    <div class="left">
      <span class="brand">dwkambience</span>

      <nav class="menus">
        <div v-for="menu in menus" :key="menu.id" class="menu-root" @mouseenter="hover(menu.id)">
          <button class="btn ghost menu-btn" :class="{ active: open === menu.id }" @click="toggle(menu.id)">{{ t(menu.label) }}</button>
          <div v-if="open === menu.id" class="dropdown" role="menu">
            <template v-for="(entry, i) in menu.items" :key="i">
              <div v-if="entry.kind === 'sep'" class="sep" />
              <div v-else-if="entry.kind === 'header'" class="menu-header">{{ entry.label }}</div>
              <button v-else role="menuitem" :disabled="entry.disabled" @click="run(entry)">
                <span class="check-slot"><span v-if="entry.checked !== undefined" class="check" :class="{ on: entry.checked }" /></span>
                <span class="entry-label">{{ entry.label }}</span>
                <span v-if="entry.shortcut" class="faint shortcut">{{ entry.shortcut }}</span>
              </button>
            </template>
          </div>
        </div>
      </nav>

      <div class="divider" />

      <div v-for="p in PALETTES" :key="p.kind" class="menu-root palette-root">
        <button
          class="btn ghost"
          :class="{ active: open === p.kind }"
          :disabled="!editor.canEdit"
          :title="t(p.label)"
          @click="toggle(p.kind)"
        >
          <Icon :name="p.kind" :size="15" />
          <span class="palette-label">{{ t(p.label) }}</span>
        </button>
        <PaletteMenu
          :kind="p.kind"
          :open="open === p.kind"
          @spawn="(model) => spawnFrom(p.kind, model)"
          @close="open = null"
        />
      </div>
    </div>

    <div class="menu-root palette-root">
      <button class="btn ghost" :class="{ active: open === 'setpiece' }" :disabled="!editor.canEdit" :title="t('paletteSetPiece')" @click="toggle('setpiece')">
        <Icon name="setpiece" :size="15" />
        <span class="palette-label">{{ t('paletteSetPiece') }}</span>
      </button>
      <SetPieceMenu :open="open === 'setpiece'" @close="open = null" />
    </div>

    <div v-if="editor.meta" class="center">
      <span class="faint group">{{ editor.meta.group || t('ungrouped') }}</span>
      <span class="faint group">/</span>
      <span class="name">{{ editor.meta.name }}</span>
      <Icon v-if="editor.readOnly" name="lock" :size="13" class="faint" />
      <span class="saved" :class="{ dirty: editor.dirty && !editor.readOnly }">{{ savedLabel }}</span>
    </div>

    <div class="right">
      <span v-if="editor.perf && editor.scene" class="perf mono" :class="perfLevel" :title="t('perfTitle', { peds: editor.perf.peds })">
        {{ editor.perf.ms.toFixed(1) }} ms · {{ editor.perf.fps }} fps
      </span>
      <span v-if="editor.studio" class="counter mono" :class="{ warn: nearLimit }">
        {{ editor.studio.label }} // {{ editor.entityCount }}/{{ editor.studio.maxEntities }}
      </span>
      <button v-if="editor.meta?.type === 'cutscene'" class="btn ghost" :disabled="!editor.scene" :title="t('previewCutscene')" @click="editor.preview()">
        <Icon name="play" :size="14" /> <span class="palette-label">{{ t('preview') }}</span>
      </button>
      <button v-if="editor.scene" class="btn primary" :disabled="!editor.canEdit || !editor.dirty || editor.saving" @click="editor.save">
        <Icon name="save" :size="14" /> {{ t('save') }}
      </button>
      <button class="btn icon ghost" :title="t('exitEditor')" @click="emit('exit')">
        <Icon name="exit" />
      </button>
    </div>
  </header>
</template>

<style scoped>
.topbar {
  grid-area: top;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 0 8px 0 14px;
  background: var(--surface-1);
}
.left, .right, .center, .menus { display: flex; align-items: center; gap: 2px; }
.center { gap: 6px; min-width: 0; font-size: var(--fs-sm); }
.right { gap: 10px; }
.brand { font-weight: 700; letter-spacing: 0.02em; margin-right: 10px; }
.menu-btn { padding: 0 9px; }
.palette-root .btn { padding: 0 8px; }
/* En pantallas estrechas las paletas quedan solo con icono (el nombre sigue en el título) */
@media (max-width: 1750px) {
  .palette-label { display: none; }
  .group { display: none; }
}
.divider { width: 1px; height: 20px; background: var(--line); margin: 0 6px; }
.name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 200px; }
.group { white-space: nowrap; }
.saved { color: var(--text-3); margin-left: 6px; white-space: nowrap; }
.saved.dirty { color: var(--warning); }
.counter { font-size: var(--fs-xs); color: var(--text-2); white-space: nowrap; }
.counter.warn { color: var(--warning); }
.perf { font-size: var(--fs-xs); color: var(--text-3); white-space: nowrap; }
.perf.warn { color: var(--warning); }
.perf.danger { color: var(--danger); }

.menu-root { position: relative; }
.dropdown {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  min-width: 240px;
  padding: 6px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  z-index: 20;
}
.dropdown button {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 7px 10px 7px 6px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  text-align: left;
  font-size: var(--fs-sm);
  cursor: pointer;
}
.dropdown button:hover:not(:disabled) { background: var(--surface-hover); }
.dropdown button:disabled { color: var(--text-3); cursor: default; }
.entry-label { flex: 1; white-space: nowrap; }
.shortcut { font-size: var(--fs-xs); }
.check-slot { width: 10px; display: flex; justify-content: center; }
.check { width: 7px; height: 7px; border-radius: 50%; background: var(--surface-3); }
.check.on { background: var(--accent); }
.menu-header { padding: 6px 10px 4px 24px; font-size: var(--fs-xs); font-weight: 600; color: var(--text-3); }
.sep { height: 1px; background: var(--line); margin: 6px 4px; }
</style>
