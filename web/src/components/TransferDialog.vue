<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { t } from '../i18n'
import { fileName, parseExport } from '../transfer'
import { useEditor } from '../stores/editor'
import Icon from './Icon.vue'

const editor = useEditor()
const area = ref<HTMLTextAreaElement | null>(null)

const pasted = ref('')
const name = ref('')
const group = ref('')
const error = ref<string | null>(null)
const copied = ref(false)

const transfer = computed(() => editor.transfer)
const parsed = computed(() => (pasted.value.trim() ? parseExport(pasted.value) : null))

watch(transfer, (value) => {
  pasted.value = ''
  name.value = ''
  group.value = ''
  error.value = null
  copied.value = false
  if (value?.mode === 'export') setTimeout(() => area.value?.select(), 0)
})

// Al pegar un archivo válido se rellenan nombre y grupo con los suyos
watch(parsed, (file) => {
  error.value = file === 'invalid_json' ? t('errInvalidJson') : file === 'not_a_scene' ? t('errNotAScene') : null
  if (file && typeof file === 'object') {
    name.value = file.name
    group.value = file.group ?? ''
  }
})

function copy() {
  area.value?.select()
  // En el navegador de FiveM navigator.clipboard puede no estar disponible; execCommand sí funciona
  copied.value = document.execCommand('copy')
}

function download() {
  if (transfer.value?.mode !== 'export') return
  const blob = new Blob([transfer.value.json], { type: 'application/json' })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = fileName(transfer.value.name)
  link.click()
  URL.revokeObjectURL(link.href)
}

async function loadFile(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (file) pasted.value = await file.text()
}

function submit() {
  const file = parsed.value
  if (!file || typeof file !== 'object' || !name.value.trim()) return
  editor.importScene(file, name.value.trim(), group.value.trim())
}
</script>

<template>
  <div v-if="transfer" class="scrim" @mousedown.self="editor.transfer = null">
    <div class="dialog" role="dialog">
      <template v-if="transfer.mode === 'export'">
        <h2>{{ t('exportTitle', { name: transfer.name }) }}</h2>
        <p class="muted">{{ t('exportBody') }}</p>
        <textarea ref="area" class="mono" readonly :value="transfer.json" />
        <div class="actions">
          <span v-if="copied" class="ok">{{ t('copied') }}</span>
          <button class="btn ghost" @click="download"><Icon name="save" :size="14" /> {{ t('download') }}</button>
          <button class="btn primary" @click="copy">{{ t('copy') }}</button>
        </div>
      </template>

      <template v-else>
        <h2>{{ t('importTitle') }}</h2>
        <p class="muted">{{ t('importBody') }}</p>
        <textarea v-model="pasted" class="mono" :placeholder="t('importPlaceholder')" />
        <label class="file btn ghost">
          <input type="file" accept=".json,application/json" @change="loadFile" />
          {{ t('importFile') }}
        </label>
        <p v-if="error" class="error">{{ error }}</p>
        <template v-if="parsed && typeof parsed === 'object'">
          <p class="faint summary">{{ t(parsed.type) }} · {{ t('importSummary', { entities: parsed.data.entities?.length ?? 0, tracks: parsed.data.tracks?.length ?? 0 }) }}</p>
          <div class="fields">
            <input v-model="name" maxlength="64" :placeholder="t('sceneName')" />
            <input v-model="group" maxlength="64" :placeholder="t('groupOptional')" />
          </div>
        </template>
        <div class="actions">
          <button class="btn ghost" @click="editor.transfer = null">{{ t('cancel') }}</button>
          <button class="btn primary" :disabled="!parsed || typeof parsed !== 'object' || !name.trim()" @click="submit">{{ t('importAction') }}</button>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.scrim { position: fixed; inset: 0; background: var(--scrim); display: grid; place-items: center; z-index: 60; }
.dialog { width: 560px; padding: 20px; background: var(--surface-2); border-radius: var(--radius); box-shadow: var(--shadow); display: flex; flex-direction: column; gap: 12px; }
h2 { margin: 0; font-size: var(--fs-lg); font-weight: 600; }
p { margin: 0; font-size: var(--fs-sm); line-height: 1.5; }
textarea {
  height: 220px;
  resize: none;
  background: var(--surface-3);
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  padding: 8px;
  font-size: var(--fs-xs);
  color: var(--text);
  outline: none;
  user-select: text;
}
textarea:focus { border-color: var(--accent); }
.file { align-self: flex-start; position: relative; overflow: hidden; }
.file input { position: absolute; inset: 0; opacity: 0; cursor: pointer; }
.fields { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.summary { font-size: var(--fs-xs); }
.error { color: var(--danger); }
.ok { color: var(--accent); font-size: var(--fs-sm); margin-right: auto; }
.actions { display: flex; justify-content: flex-end; align-items: center; gap: 8px; }
</style>
