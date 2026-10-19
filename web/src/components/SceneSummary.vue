<script setup lang="ts">
import { computed } from 'vue'
import { WEATHERS } from '../catalog'
import { t } from '../i18n'
import { formatDuration, sceneStats } from '../scene'
import { useEditor } from '../stores/editor'

const editor = useEditor()

const stats = computed(() => (editor.scene ? sceneStats(editor.scene) : null))
const settings = computed(() => editor.scene?.settings)

function onTime(e: Event) {
  const value = (e.target as HTMLInputElement).value
  if (/^\d{2}:\d{2}$/.test(value)) editor.setSettings({ time: value })
}
</script>

<template>
  <div v-if="editor.meta && settings && stats" class="summary">
    <div class="section-title">{{ t('scene') }}</div>
    <div class="grid">
      <label>{{ t('name') }}</label>
      <input
        :value="editor.meta.name"
        maxlength="64"
        :disabled="editor.readOnly"
        @change="editor.setMeta({ name: ($event.target as HTMLInputElement).value.trim() || editor.meta!.name })"
      />
      <label>{{ t('group') }}</label>
      <input
        :value="editor.meta.group ?? ''"
        maxlength="64"
        :placeholder="t('ungrouped')"
        :disabled="editor.readOnly"
        @change="editor.setMeta({ group: ($event.target as HTMLInputElement).value.trim() || null })"
      />
      <label>{{ t('type') }}</label>
      <span class="value">{{ t(editor.meta.type) }}</span>
      <label>{{ t('duration') }}</label>
      <span class="value mono">{{ formatDuration(settings.duration) }}</span>
      <label>{{ t('tracks') }}</label>
      <span class="value">{{ t('tracksKeys', { tracks: stats.tracks, keys: stats.keys }) }}</span>
      <label>{{ t('weather') }}</label>
      <select :value="settings.weather" :disabled="editor.readOnly" @change="editor.setSettings({ weather: ($event.target as HTMLSelectElement).value })">
        <option v-for="w in WEATHERS" :key="w" :value="w">{{ w }}</option>
      </select>
      <label>{{ t('time') }}</label>
      <input type="time" :value="settings.time" :disabled="editor.readOnly" @change="onTime" />
      <label>{{ t('output') }}</label>
      <div class="toggles">
        <label class="toggle">
          <input
            type="checkbox"
            :checked="settings.output.letterbox"
            :disabled="editor.readOnly"
            @change="editor.setSettings({ output: { ...settings.output, letterbox: ($event.target as HTMLInputElement).checked } })"
          />
          {{ t('letterbox') }}
        </label>
        <label class="toggle">
          <input
            type="checkbox"
            :checked="settings.output.hud"
            :disabled="editor.readOnly"
            @change="editor.setSettings({ output: { ...settings.output, hud: ($event.target as HTMLInputElement).checked } })"
          />
          {{ t('hud') }}
        </label>
      </div>
    </div>
  </div>
</template>

<style scoped>
.summary { padding: 14px; background: var(--surface-2); display: flex; flex-direction: column; gap: 10px; }
.grid { display: grid; grid-template-columns: 70px 1fr; gap: 6px 10px; align-items: center; }
.grid > label { font-size: var(--fs-xs); color: var(--text-3); }
.grid input, .grid select { font-size: var(--fs-sm); padding: 5px 7px; }
.value { font-size: var(--fs-sm); color: var(--text-2); }
.toggles { display: flex; gap: 12px; }
.toggle { display: flex; align-items: center; gap: 5px; font-size: var(--fs-sm); color: var(--text-2); }
</style>
