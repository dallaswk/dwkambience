<script setup lang="ts">
import { t } from '../i18n'
import { useEditor } from '../stores/editor'

const editor = useEditor()

function when(value: number | string | null) {
  if (value === null) return ''
  const d = new Date(typeof value === 'number' ? value : Date.parse(value))
  return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString()
}

function size(bytes: number | null) {
  return bytes ? `${Math.max(1, Math.round(bytes / 1024))} KB` : ''
}
</script>

<template>
  <div v-if="editor.revisions !== null" class="scrim" @mousedown.self="editor.revisions = null">
    <div class="dialog" role="dialog">
      <h2>{{ t('historyTitle') }}</h2>
      <p class="muted">{{ t('historyBody') }}</p>
      <ol class="scroll">
        <li v-for="(r, i) in editor.revisions" :key="r.rev">
          <div class="main">
            <span class="rev mono">#{{ r.rev }}</span>
            <span>{{ when(r.createdAt) }}</span>
            <span v-if="i === 0" class="latest">{{ t('historyLatest') }}</span>
          </div>
          <span class="faint meta">{{ r.createdBy ?? '?' }} · {{ size(r.size) }}</span>
          <button class="btn" :disabled="editor.readOnly" @click="editor.restoreRevision(r.rev)">{{ t('historyRestore') }}</button>
        </li>
        <li v-if="!editor.revisions.length" class="faint empty">{{ t('historyEmpty') }}</li>
      </ol>
      <div class="actions">
        <button class="btn primary" @click="editor.revisions = null">{{ t('close') }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.scrim { position: fixed; inset: 0; background: var(--scrim); display: grid; place-items: center; z-index: 60; }
.dialog { width: 520px; max-height: 80vh; display: flex; flex-direction: column; gap: 12px; padding: 20px; background: var(--surface-2); border-radius: var(--radius); box-shadow: var(--shadow); }
h2 { margin: 0; font-size: var(--fs-lg); font-weight: 600; }
p { margin: 0; font-size: var(--fs-sm); line-height: 1.5; }
ol { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; min-height: 0; }
li { display: grid; grid-template-columns: 1fr auto auto; align-items: center; gap: 12px; padding: 8px 10px; border-radius: var(--radius-sm); background: var(--surface-1); }
.main { display: flex; align-items: center; gap: 10px; font-size: var(--fs-sm); }
.rev { color: var(--text-3); }
.latest { font-size: 10px; font-weight: 700; color: var(--accent); background: var(--accent-soft); padding: 2px 6px; border-radius: 8px; }
.meta { font-size: var(--fs-xs); }
.empty { display: block; font-size: var(--fs-sm); }
.actions { display: flex; justify-content: flex-end; }
</style>
