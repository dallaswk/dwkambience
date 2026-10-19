<script setup lang="ts">
import { t } from '../i18n'
import type { MessageKey } from '../i18n'
import { useEditor } from '../stores/editor'

const editor = useEditor()

const VERSION = '1.0.0'

// keys: texto literal (nombres de tecla universales) o clave de traducción
const SHORTCUTS: { keys: string | MessageKey; label: MessageKey }[] = [
  { keys: 'kbRmbWasd', label: 'scFly' },
  { keys: 'Q / E', label: 'scUpDown' },
  { keys: 'Shift / Ctrl', label: 'scSpeed' },
  { keys: 'Z / C · X', label: 'scRoll' },
  { keys: 'Ctrl+G', label: 'scGroup' },
  { keys: 'kbClick', label: 'scSelect' },
  { keys: 'F', label: 'scFocus' },
  { keys: 'W / R · Enter · Esc', label: 'scGizmo' },
  { keys: 'kbSpace', label: 'scPlay' },
  { keys: 'K', label: 'scKey' },
  { keys: 'P', label: 'scPreview' },
  { keys: 'R', label: 'scRec' },
  { keys: 'H', label: 'scVisibility' },
  { keys: 'Ctrl+Z / Ctrl+Y', label: 'scUndoRedo' },
  { keys: 'Ctrl+D', label: 'scDuplicate' },
  { keys: 'kbDelete', label: 'scDelete' },
  { keys: 'Ctrl+S', label: 'scSave' },
  { keys: 'kbCtrlWheel', label: 'scZoom' },
  { keys: 'kbShiftRuler', label: 'scRegion' },
  { keys: 'kbBackspace', label: 'scSkip' },
]
</script>

<template>
  <div v-if="editor.dialog" class="scrim" @mousedown.self="editor.dialog = null">
    <div class="dialog" role="dialog">
      <template v-if="editor.dialog === 'shortcuts'">
        <h2>{{ t('shortcutsTitle') }}</h2>
        <dl class="scroll">
          <template v-for="s in SHORTCUTS" :key="s.label">
            <dt class="mono">{{ s.keys.startsWith('kb') ? t(s.keys as MessageKey) : s.keys }}</dt>
            <dd>{{ t(s.label) }}</dd>
          </template>
        </dl>
      </template>
      <template v-else>
        <h2>dwkambience</h2>
        <p class="muted">{{ t('aboutBody', { version: VERSION }) }}</p>
      </template>
      <div class="actions">
        <button class="btn primary" @click="editor.dialog = null">{{ t('close') }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.scrim { position: fixed; inset: 0; background: var(--scrim); display: grid; place-items: center; z-index: 60; }
.dialog { width: 460px; max-height: 80vh; display: flex; flex-direction: column; padding: 20px; background: var(--surface-2); border-radius: var(--radius); box-shadow: var(--shadow); }
h2 { margin: 0 0 14px; font-size: var(--fs-lg); font-weight: 600; }
p { margin: 0 0 18px; font-size: var(--fs-sm); line-height: 1.6; }
dl { display: grid; grid-template-columns: auto 1fr; gap: 8px 16px; margin: 0 0 18px; font-size: var(--fs-sm); }
dt { color: var(--text); font-size: var(--fs-xs); white-space: nowrap; }
dd { margin: 0; color: var(--text-2); }
.actions { display: flex; justify-content: flex-end; }
</style>
