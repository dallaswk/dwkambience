<script setup lang="ts">
import { onBeforeUnmount, onMounted } from 'vue'
import ConfirmDialog from './components/ConfirmDialog.vue'
import Inspector from './components/Inspector.vue'
import Outliner from './components/Outliner.vue'
import SceneManager from './components/SceneManager.vue'
import SceneSummary from './components/SceneSummary.vue'
import TimelineStub from './components/TimelineStub.vue'
import Toasts from './components/Toasts.vue'
import TopBar from './components/TopBar.vue'
import Viewport from './components/Viewport.vue'
import { bootMock } from './mocks'
import { fetchNui, inGame, onNuiMessage } from './nui'
import { useConfirm } from './stores/confirm'
import { useEditor } from './stores/editor'

const editor = useEditor()
const confirm = useConfirm()

async function confirmDiscard() {
  if (!editor.dirty || editor.readOnly) return true
  return confirm.ask({
    title: 'Discard unsaved changes?',
    body: `“${editor.meta?.name}” has changes that have not been saved.`,
    confirm: 'Discard changes',
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
  if (!editor.visible || confirm.request) return
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
    e.preventDefault()
    editor.save()
    return
  }
  if (isTyping(e.target)) return
  const id = editor.selectedId
  if ((e.key === 'Delete' || e.key === 'Backspace') && id) editor.removeEntity(id)
  else if (e.key.toLowerCase() === 'f' && id) editor.focus(id)
  else if (e.key === 'Escape' && id) editor.select(null)
}

let stop: (() => void) | undefined

onMounted(() => {
  stop = onNuiMessage(({ action, data }) => {
    if (action === 'open') editor.show(data as { studios: unknown })
    else if (action === 'close') editor.hide()
    else if (action === 'gizmo') editor.onGizmo(data as Parameters<typeof editor.onGizmo>[0])
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
  <div v-if="editor.visible" class="editor" :class="{ 'has-scene': !!editor.scene, 'dev-bg': !inGame }">
    <TopBar @close-scene="closeScene" @exit="exit" />

    <aside class="left">
      <template v-if="editor.scene">
        <button class="back" @click="closeScene">
          <span class="chev">‹</span> All scenes
        </button>
        <Outliner />
        <SceneSummary />
      </template>
      <SceneManager v-else />
    </aside>

    <Viewport />

    <template v-if="editor.scene">
      <Inspector />
      <TimelineStub />
    </template>
  </div>

  <Toasts />
  <ConfirmDialog />
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
