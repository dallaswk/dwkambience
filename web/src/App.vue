<script setup lang="ts">
import { onBeforeUnmount, onMounted } from 'vue'
import ConfirmDialog from './components/ConfirmDialog.vue'
import HelpDialog from './components/HelpDialog.vue'
import TransferDialog from './components/TransferDialog.vue'
import HistoryDialog from './components/HistoryDialog.vue'
import Inspector from './components/Inspector.vue'
import Outliner from './components/Outliner.vue'
import SceneManager from './components/SceneManager.vue'
import SceneSummary from './components/SceneSummary.vue'
import Timeline from './components/timeline/Timeline.vue'
import Toasts from './components/Toasts.vue'
import TopBar from './components/TopBar.vue'
import Viewport from './components/Viewport.vue'
import { t } from './i18n'
import { bootMock } from './mocks'
import { fetchNui, inGame, onNuiMessage } from './nui'
import { handleAudio3D, type Audio3DMessage } from './audio3d'
import { handleMusic, type MusicMessage } from './music'
import { useConfirm } from './stores/confirm'
import { useEditor } from './stores/editor'
import { useTimeline } from './stores/timeline'

const editor = useEditor()
const timeline = useTimeline()
const confirm = useConfirm()

async function confirmDiscard() {
  if (!editor.dirty || editor.readOnly) return true
  return confirm.ask({
    title: t('discardTitle'),
    body: t('discardBody', { name: editor.meta?.name ?? '' }),
    confirm: t('discardConfirm'),
    danger: true,
  })
}

async function closeScene() {
  if (await confirmDiscard()) editor.closeScene()
}

async function exit() {
  if (await confirmDiscard()) editor.exit()
}

const isTyping = (el: EventTarget | null) =>
  el instanceof HTMLElement && (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA')

// Mientras se escribe, el cliente deja de pasar el teclado al juego (si no, WASD movería la cámara)
function onFocusIn(e: FocusEvent) {
  if (isTyping(e.target)) fetchNui('typing', { active: true })
}
function onFocusOut(e: FocusEvent) {
  if (isTyping(e.target) && !isTyping(e.relatedTarget)) fetchNui('typing', { active: false })
}

function onKey(e: KeyboardEvent) {
  if (!editor.visible || confirm.request || editor.dialog || editor.transfer || editor.revisions !== null) return
  const key = e.key.toLowerCase()
  const mod = e.ctrlKey || e.metaKey
  if (mod && key === 's') {
    e.preventDefault()
    editor.save()
    return
  }
  if (isTyping(e.target) || editor.previewing || editor.recording) return
  if (key === '?') {
    editor.dialog = 'shortcuts'
    return
  }
  if (!editor.scene) return

  if (mod && (key === 'y' || (key === 'z' && e.shiftKey))) {
    e.preventDefault()
    editor.redo()
  } else if (mod && key === 'z') {
    e.preventDefault()
    editor.undo()
  } else if (key === ' ') {
    e.preventDefault()
    timeline.toggle()
  } else if (mod && key === 'g') {
    e.preventDefault()
    editor.groupSelection()
  } else if (mod && key === 'd') {
    e.preventDefault()
    if (editor.selectedId) editor.duplicateEntity(editor.selectedId)
  } else if (key === 'k') {
    editor.recordKey()
  } else if (key === 'p') {
    editor.preview()
  } else if (key === 'r' && !mod) {
    editor.record()
  } else if (key === 'h' && editor.selectedId) {
    editor.toggleVisibility(editor.selectedId)
  } else if (key === 'delete' || key === 'backspace') {
    editor.deleteSelection()
  } else if (key === 'f' && editor.selectedId) {
    editor.focus(editor.selectedId)
  } else if (key === 'escape') {
    if (editor.selectedItem || editor.selectedGroup) timeline.select(null)
    else if (editor.selectedId) editor.select(null)
  }
}

let stop: (() => void) | undefined

onMounted(() => {
  stop = onNuiMessage(({ action, data }) => {
    if (action === 'open') editor.show(data as Parameters<typeof editor.show>[0])
    else if (action === 'close') editor.hide()
    else if (action === 'gizmo') editor.onGizmo(data as Parameters<typeof editor.onGizmo>[0])
    else if (action === 'preview') editor.onPreview(data as { active: boolean })
    else if (action === 'perf') editor.perf = data as { ms: number; fps: number; peds: number }
    else if (action === 'recording') editor.onRecording(data as Parameters<typeof editor.onRecording>[0])
    else if (action === 'music') handleMusic(data as MusicMessage)
    else if (action === 'audio3d') handleAudio3D(data as Audio3DMessage)
  })
  document.addEventListener('focusin', onFocusIn)
  document.addEventListener('focusout', onFocusOut)
  window.addEventListener('keydown', onKey)
  if (!inGame) bootMock()
})

onBeforeUnmount(() => {
  stop?.()
  document.removeEventListener('focusin', onFocusIn)
  document.removeEventListener('focusout', onFocusOut)
  window.removeEventListener('keydown', onKey)
})
</script>

<template>
  <!-- Durante la previsualización la UI se oculta (sin desmontarla) para ver la cutscene a pantalla completa -->
  <div v-if="editor.visible" v-show="!editor.previewing && !editor.recording" class="editor" :class="{ 'has-scene': !!editor.scene, 'dev-bg': !inGame }">
    <TopBar @close-scene="closeScene" @exit="exit" />

    <aside class="left">
      <template v-if="editor.scene">
        <button class="back" @click="closeScene">
          <span class="chev">‹</span> {{ t('allScenes') }}
        </button>
        <Outliner />
        <SceneSummary />
      </template>
      <SceneManager v-else />
    </aside>

    <Viewport />

    <template v-if="editor.scene">
      <Inspector />
      <Timeline />
    </template>
  </div>

  <Toasts />
  <ConfirmDialog />
  <HelpDialog />
  <TransferDialog />
  <HistoryDialog />
</template>

<style scoped>
.editor {
  position: fixed;
  inset: 0;
  display: grid;
  grid-template-rows: var(--topbar-h) 1fr;
  grid-template-columns: var(--left-w) 1fr;
  grid-template-areas:
    'top top'
    'left view';
}
.editor.has-scene {
  grid-template-rows: var(--topbar-h) 1fr var(--timeline-h);
  grid-template-columns: var(--left-w) 1fr var(--right-w);
  grid-template-areas:
    'top top top'
    'left view right'
    'timeline timeline timeline';
}
/* Fuera del juego no hay mundo detrás: un degradado ocupa su lugar */
.editor.dev-bg { background: radial-gradient(ellipse at 60% 40%, var(--surface-3), var(--bg)); }

.left { grid-area: left; display: flex; flex-direction: column; min-height: 0; background: var(--surface-1); }
.back {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 10px 14px;
  border: none;
  background: none;
  color: var(--text-2);
  font-size: var(--fs-sm);
  font-weight: 600;
  text-align: left;
  cursor: pointer;
}
.back:hover { color: var(--text); }
.chev { font-size: 16px; line-height: 1; }
</style>
