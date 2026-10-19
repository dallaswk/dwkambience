<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
import { fetchNui } from '../nui'
import { useEditor } from '../stores/editor'

// Zona transparente sobre el juego: clic izquierdo selecciona, botón derecho mantenido vuela la cámara
const editor = useEditor()
const looking = ref(false)
let downAt: { x: number; y: number } | null = null

function onDown(e: MouseEvent) {
  if (e.button === 2) {
    looking.value = true
    fetchNui('camLook', { active: true })
  } else if (e.button === 0) {
    downAt = { x: e.clientX, y: e.clientY }
  }
}

function onUp(e: MouseEvent) {
  if (e.button === 2 && looking.value) {
    looking.value = false
    fetchNui('camLook', { active: false })
  } else if (e.button === 0 && downAt && editor.scene) {
    const moved = Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y)
    if (moved < 4) editor.pick(e.clientX / window.innerWidth, e.clientY / window.innerHeight)
  }
  downAt = null
}

window.addEventListener('mouseup', onUp)
onBeforeUnmount(() => window.removeEventListener('mouseup', onUp))
</script>

<template>
  <div class="viewport" :class="{ looking }" @mousedown="onDown" @contextmenu.prevent>
    <div v-if="editor.scene && !editor.gizmoActive" class="hint">
      Hold <b>right mouse</b> + WASD to fly · <b>Q/E</b> down/up · <b>Shift</b> fast · <b>Click</b> to select
    </div>
    <div v-if="editor.gizmoActive" class="gizmo-banner">
      Gizmo active · <b>W</b> move · <b>R</b> rotate · <b>Enter</b> confirm · <b>Esc</b> cancel
    </div>
  </div>
</template>

<style scoped>
.viewport { grid-area: view; position: relative; cursor: default; }
.viewport.looking { cursor: none; }
.hint, .gizmo-banner {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 12px;
  border-radius: var(--radius);
  font-size: var(--fs-xs);
  white-space: nowrap;
  pointer-events: none;
}
.hint { bottom: 12px; background: var(--scrim); color: var(--text-2); }
.gizmo-banner { top: 12px; background: var(--accent); color: var(--on-accent); }
</style>
