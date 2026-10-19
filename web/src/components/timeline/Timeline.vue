<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { loadSounds, type SoundAsset } from '../../audio'
import { t } from '../../i18n'
import { formatTime, sceneDuration } from '../../scene'
import { useEditor } from '../../stores/editor'
import { useHistory } from '../../stores/history'
import { useTimeline } from '../../stores/timeline'
import type { EventType } from '../../types'
import Icon from '../Icon.vue'
import { PAD, drawLanes, drawRuler, hitItem, readPalette, tOf, xOf, type Palette, type View } from './draw'
import { HEADER_W, ROW_H, RULER_H, buildRows, type Row } from './rows'

const editor = useEditor()
const tl = useTimeline()
const history = useHistory()

const rows = computed(() => buildRows(editor.scene, editor.meta?.type))
const duration = computed(() => (editor.scene ? sceneDuration(editor.scene) : 0))
const isCutscene = computed(() => editor.meta?.type === 'cutscene')

const rulerCanvas = ref<HTMLCanvasElement | null>(null)
const lanesCanvas = ref<HTMLCanvasElement | null>(null)
const lanesWrap = ref<HTMLDivElement | null>(null)
const width = ref(600)

const menu = ref<'event' | 'music' | null>(null)
const sounds = ref<SoundAsset[]>([])

let palette: Palette
let raf = 0
let observer: ResizeObserver | null = null

function view(): View {
  return { width: width.value, pxPerMs: tl.pxPerSec / 1000, scrollMs: tl.scrollMs, duration: duration.value }
}

function sizeCanvas(canvas: HTMLCanvasElement, w: number, h: number) {
  const dpr = window.devicePixelRatio || 1
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr)
    canvas.height = Math.round(h * dpr)
    canvas.style.width = `${w}px`
    canvas.style.height = `${h}px`
  }
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  return ctx
}

// Bucle de dibujo: lee el estado sin pasar por el render de Vue
function frame() {
  raf = requestAnimationFrame(frame)
  const scene = editor.scene
  if (!scene || !rulerCanvas.value || !lanesCanvas.value) return

  const v = view()
  // Seguir el playhead mientras se reproduce
  if (tl.playing) {
    const x = xOf(v, tl.time)
    if (x > v.width - 40 || x < 0) tl.scrollMs = Math.max(0, tl.time - (v.width * 0.2) / v.pxPerMs)
  }

  const rulerCtx = sizeCanvas(rulerCanvas.value, v.width, RULER_H)
  drawRuler(rulerCtx, view(), RULER_H, palette, tl.time, tl.region)

  const lanesCtx = sizeCanvas(lanesCanvas.value, v.width, Math.max(ROW_H, rows.value.length * ROW_H))
  drawLanes(lanesCtx, view(), palette, rows.value, scene, tl.time, tl.selected, tl.selectedRow, tl.region)
}

onMounted(() => {
  palette = readPalette()
  observer = new ResizeObserver(([entry]) => {
    width.value = Math.max(100, Math.floor(entry.contentRect.width))
  })
  if (lanesWrap.value) observer.observe(lanesWrap.value)
  raf = requestAnimationFrame(frame)
  loadSounds().then((list) => (sounds.value = list))
  document.addEventListener('mousedown', closeMenus)
})

onBeforeUnmount(() => {
  cancelAnimationFrame(raf)
  observer?.disconnect()
  document.removeEventListener('mousedown', closeMenus)
})

function closeMenus(e: MouseEvent) {
  if (!(e.target as HTMLElement).closest('.add-menu')) menu.value = null
}

// --- Interacción con las pistas ------------------------------------------------

type Drag =
  | { mode: 'scrub' }
  | { mode: 'region'; anchor: number }
  | { mode: 'item'; kind: 'key' | 'clip'; startX: number; origin: number; moved: boolean }

let drag: Drag | null = null

function localX(e: PointerEvent, el: HTMLElement) {
  return e.clientX - el.getBoundingClientRect().left
}

function onRulerDown(e: PointerEvent) {
  const el = e.currentTarget as HTMLElement
  el.setPointerCapture(e.pointerId)
  const time = tl.snapTime(tOf(view(), localX(e, el)))
  if (e.shiftKey) {
    drag = { mode: 'region', anchor: time }
    tl.region = null
  } else {
    drag = { mode: 'scrub' }
    tl.pause()
    tl.setTime(time)
  }
}

function onLanesDown(e: PointerEvent) {
  const el = e.currentTarget as HTMLElement
  const scene = editor.scene
  if (!scene) return
  el.setPointerCapture(e.pointerId)
  const x = localX(e, el)
  const y = e.clientY - el.getBoundingClientRect().top
  const row = rows.value[Math.floor(y / ROW_H)]
  if (!row) return
  selectRow(row)

  const hit = hitItem(scene, row, view(), x)
  if (hit) {
    tl.select(hit)
    const sel = editor.selectedItem
    const origin = sel ? ('t' in sel.item ? sel.item.t : sel.item.start) : 0
    drag = { mode: 'item', kind: hit.kind, startX: x, origin, moved: false }
    return
  }

  tl.select(null)
  tl.pause()
  drag = { mode: 'scrub' }
  tl.setTime(tl.snapTime(tOf(view(), x)))
}

function onMove(e: PointerEvent) {
  if (!drag) return
  const el = e.currentTarget as HTMLElement
  const x = localX(e, el)
  const time = tOf(view(), x)

  if (drag.mode === 'scrub') {
    tl.setTime(tl.snapTime(time))
  } else if (drag.mode === 'region') {
    const end = tl.snapTime(time)
    tl.region = end === drag.anchor ? null : { start: Math.max(0, Math.min(drag.anchor, end)), end: Math.max(drag.anchor, end) }
  } else if (editor.canEdit) {
    if (!drag.moved && Math.abs(x - drag.startX) < 3) return
    if (!drag.moved) {
      editor.checkpoint() // una sola instantánea por arrastre
      drag.moved = true
    }
    const next = Math.max(0, tl.snapTime(drag.origin + (x - drag.startX) / view().pxPerMs))
    editor.updateSelected(drag.kind === 'key' ? { t: next } : { start: next }, false)
  }
}

function onUp() {
  drag = null
}

function onWheel(e: WheelEvent) {
  const lanes = lanesWrap.value
  if (!lanes) return
  if (e.ctrlKey || e.metaKey) {
    e.preventDefault()
    const x = e.clientX - lanes.getBoundingClientRect().left
    const anchor = tOf(view(), x)
    tl.pxPerSec = Math.max(10, Math.min(800, tl.pxPerSec * (e.deltaY < 0 ? 1.15 : 1 / 1.15)))
    tl.scrollMs = Math.max(0, anchor - ((x - PAD) * 1000) / tl.pxPerSec)
  } else if (e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
    e.preventDefault()
    const delta = e.shiftKey ? e.deltaY : e.deltaX
    tl.scrollMs = Math.max(0, tl.scrollMs + (delta * 1000) / tl.pxPerSec)
  }
}

function zoom(factor: number) {
  tl.pxPerSec = Math.max(10, Math.min(800, tl.pxPerSec * factor))
}

function selectRow(row: Row) {
  tl.selectedRow = row.id
  if (row.entityId && row.entityId !== editor.selectedId) editor.select(row.entityId)
}

function rowLabel(row: Row) {
  return row.label ?? (row.labelKey ? t(row.labelKey) : '')
}

function addEvent(type: EventType) {
  menu.value = null
  editor.addEvent(type)
}

function addFade(to: 0 | 1) {
  addEvent('fade')
  if (to === 0) editor.updateSelected({ to: 0 }, false)
}

function addMusic(asset: string) {
  menu.value = null
  editor.addMusic(asset)
}

function onDurationChange(e: Event) {
  editor.setDuration(Number((e.target as HTMLInputElement).value) * 1000)
}
</script>

<template>
  <footer class="timeline">
    <div class="toolbar">
      <div class="group">
        <button class="btn icon ghost" :title="t('tlStart')" @click="tl.jump('start')"><Icon name="skipStart" /></button>
        <button class="btn icon ghost" :title="t('tlPrevKey')" @click="tl.jump('prev')"><Icon name="prevKey" /></button>
        <button class="btn icon play" :title="tl.playing ? t('tlPause') : t('tlPlay')" @click="tl.toggle()">
          <Icon :name="tl.playing ? 'pause' : 'play'" />
        </button>
        <button class="btn icon ghost" :title="t('tlNextKey')" @click="tl.jump('next')"><Icon name="nextKey" /></button>
        <button class="btn icon ghost" :title="t('tlEnd')" @click="tl.jump('end')"><Icon name="skipEnd" /></button>
        <span class="clock mono">{{ formatTime(tl.time) }} <span class="faint">/ {{ formatTime(duration) }}</span></span>
      </div>

      <div class="group">
        <button class="btn" :disabled="!editor.canEdit" :title="t('tlKeyHint')" @click="editor.recordKey()">
          <Icon name="key" :size="14" /> {{ t('tlKey') }}
        </button>
        <button class="btn ghost" :class="{ active: tl.autoKey }" @click="tl.autoKey = !tl.autoKey">{{ t('tlAutoKey') }}</button>
        <button v-if="isCutscene" class="btn ghost" :class="{ active: tl.cameraView }" @click="tl.setCameraView(!tl.cameraView)">
          <Icon name="camera" :size="14" /> {{ t('tlCameraView') }}
        </button>
        <button class="btn icon ghost" :class="{ active: tl.loop }" :title="t('tlLoop')" @click="tl.loop = !tl.loop"><Icon name="loop" /></button>
        <button class="btn icon ghost" :class="{ active: tl.snap }" :title="t('tlSnap')" @click="tl.snap = !tl.snap"><Icon name="magnet" /></button>
      </div>

      <div class="group">
        <div class="add-menu">
          <button class="btn ghost" :disabled="!editor.canEdit" @click="menu = menu === 'event' ? null : 'event'">
            <Icon name="flag" :size="14" /> {{ t('tlAddEvent') }}
          </button>
          <div v-if="menu === 'event'" class="dropdown">
            <button @click="addFade(1)">{{ t('evFadeOut') }}</button>
            <button @click="addFade(0)">{{ t('evFadeIn') }}</button>
            <button @click="addEvent('subtitle')">{{ t('evSubtitle') }}</button>
            <button @click="addEvent('trigger')">{{ t('evTrigger') }}</button>
          </div>
        </div>
        <div class="add-menu">
          <button class="btn ghost" :disabled="!editor.canEdit" @click="menu = menu === 'music' ? null : 'music'">
            <Icon name="music" :size="14" /> {{ t('tlAddMusic') }}
          </button>
          <div v-if="menu === 'music'" class="dropdown scroll">
            <p v-if="!sounds.length" class="empty faint">{{ t('noSounds') }}</p>
            <button v-for="s in sounds" :key="s.id" class="mono" @click="addMusic(s.id)">{{ s.id }}</button>
          </div>
        </div>
        <button class="btn icon ghost" :disabled="!history.canUndo || !editor.canEdit" :title="t('tlUndo')" @click="editor.undo()"><Icon name="undo" /></button>
        <button class="btn icon ghost" :disabled="!history.canRedo || !editor.canEdit" :title="t('tlRedo')" @click="editor.redo()"><Icon name="redo" /></button>
        <button class="btn icon ghost" :title="t('tlZoomOut')" @click="zoom(1 / 1.4)"><Icon name="zoomOut" /></button>
        <button class="btn icon ghost" :title="t('tlZoomIn')" @click="zoom(1.4)"><Icon name="zoomIn" /></button>
        <label class="duration" :title="t('tlDuration')">
          <span class="faint">{{ t('tlDuration') }}</span>
          <input
            type="number"
            min="1"
            step="0.5"
            :value="(editor.scene?.settings.duration ?? 0) / 1000"
            :disabled="!editor.canEdit"
            @change="onDurationChange"
          />
        </label>
      </div>
    </div>

    <div class="ruler-row">
      <div class="corner" :style="{ width: `${HEADER_W}px` }" />
      <canvas
        ref="rulerCanvas"
        class="ruler"
        @pointerdown="onRulerDown"
        @pointermove="onMove"
        @pointerup="onUp"
        @dblclick="tl.region = null"
        @wheel="onWheel"
      />
    </div>

    <div class="tracks scroll">
      <div class="headers" :style="{ width: `${HEADER_W}px` }">
        <button
          v-for="row in rows"
          :key="row.id"
          class="header"
          :class="{ selected: row.id === tl.selectedRow, sub: !!row.subKey }"
          :style="{ height: `${ROW_H}px` }"
          @click="selectRow(row)"
        >
          <Icon :name="row.icon" :size="13" />
          <span class="label">{{ rowLabel(row) }}</span>
          <span v-if="row.subKey" class="faint sublabel">{{ t(row.subKey) }}</span>
        </button>
      </div>
      <div ref="lanesWrap" class="lanes" @wheel="onWheel">
        <canvas ref="lanesCanvas" @pointerdown="onLanesDown" @pointermove="onMove" @pointerup="onUp" />
      </div>
    </div>
  </footer>
</template>

<style scoped>
.timeline { grid-area: timeline; display: flex; flex-direction: column; min-height: 0; background: var(--surface-1); }

.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  height: 40px;
  padding: 0 8px;
  background: var(--surface-2);
}
.group { display: flex; align-items: center; gap: 4px; }
.btn { height: 28px; }
.btn.icon { width: 28px; }
.play { background: var(--accent); color: var(--on-accent); }
.play:hover:not(:disabled) { background: var(--accent-hover); }
.clock { margin-left: 10px; font-size: var(--fs-sm); }
.duration { display: flex; align-items: center; gap: 6px; margin-left: 6px; font-size: var(--fs-xs); }
.duration input { width: 64px; padding: 4px 6px; }

.add-menu { position: relative; }
.dropdown {
  position: absolute;
  bottom: calc(100% + 6px);
  left: 0;
  min-width: 190px;
  max-height: 240px;
  padding: 6px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  z-index: 20;
}
.dropdown button {
  display: block;
  width: 100%;
  padding: 7px 10px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  text-align: left;
  font-size: var(--fs-sm);
  cursor: pointer;
}
.dropdown button:hover { background: var(--surface-hover); }
.empty { margin: 4px; font-size: var(--fs-xs); line-height: 1.5; white-space: normal; }

.ruler-row { display: flex; height: 24px; flex-shrink: 0; }
.corner { flex-shrink: 0; background: var(--surface-2); }
.ruler { flex: 1; display: block; cursor: ew-resize; }

.tracks { flex: 1; display: flex; align-items: flex-start; min-height: 0; }
.headers { flex-shrink: 0; display: flex; flex-direction: column; }
.header {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 10px;
  border: none;
  background: var(--surface-1);
  color: var(--text-2);
  font-size: var(--fs-xs);
  text-align: left;
  cursor: pointer;
}
.header.sub { padding-left: 14px; }
.header:hover { color: var(--text); }
.header.selected { background: var(--surface-3); color: var(--text); }
.header .label { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sublabel { font-size: 10px; }
.lanes { flex: 1; min-width: 0; }
.lanes canvas { display: block; }
</style>
