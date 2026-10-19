<script setup lang="ts">
import { computed } from 'vue'
import { WEATHERS } from '../catalog'
import { t } from '../i18n'
import Vec3Field from './Vec3Field.vue'
import type { Vec3 } from '../types'
import { formatDuration, sceneStats } from '../scene'
import { useEditor } from '../stores/editor'

const editor = useEditor()

const stats = computed(() => (editor.scene ? sceneStats(editor.scene) : null))
const settings = computed(() => editor.scene?.settings)

const isAmbience = computed(() => editor.meta?.type === 'ambience')
const trigger = computed(() => editor.scene?.settings.trigger ?? null)
const schedule = computed(() => editor.scene?.settings.schedule ?? null)
const timecycle = computed(() => editor.scene?.settings.timecycle ?? null)
const num = (e: Event) => Number((e.target as HTMLInputElement).value)
const text = (e: Event) => (e.target as HTMLInputElement).value

function onSchedule(field: 'from' | 'to', e: Event) {
  const value = text(e)
  if (!/^\d{2}:\d{2}$/.test(value) || !schedule.value) return
  editor.setSettings({ schedule: { ...schedule.value, [field]: value } })
}

function toggleSchedule(enabled: boolean) {
  editor.setSettings({ schedule: enabled ? { from: '20:00', to: '04:00' } : null })
}

function setTimecycle(name: string, strength?: number) {
  const clean = name.trim().replace(/[^\w-]/g, '')
  editor.setSettings({ timecycle: clean ? { name: clean, strength: strength ?? timecycle.value?.strength ?? 1 } : null })
}

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
      <label>{{ t('timecycle') }}</label>
      <input
        class="mono"
        :value="timecycle?.name ?? ''"
        :placeholder="t('timecycleNone')"
        :disabled="editor.readOnly"
        @change="setTimecycle(text($event))"
      />
      <template v-if="timecycle">
        <label>{{ t('timecycleStrength') }}</label>
        <input type="range" min="0" max="1" step="0.05" :value="timecycle.strength" :disabled="editor.readOnly" @change="setTimecycle(timecycle!.name, num($event))" />
      </template>
    </div>

    <template v-if="isAmbience">
      <div class="section-title ambience-title">{{ t('ambience') }}</div>
      <div class="switch-row">
        <span>{{ t('ambienceActive') }}</span>
        <button
          class="toggle-switch"
          :class="{ on: editor.meta.active }"
          :disabled="editor.readOnly"
          :aria-pressed="editor.meta.active"
          @click="editor.setActive(editor.meta!.id, !editor.meta!.active)"
        />
      </div>
      <p class="note">{{ t('ambienceActiveHint') }}</p>
      <div class="grid">
        <label>{{ t('peds') }}</label>
        <span class="value mono" :class="{ warn: editor.pedCount >= editor.maxPedsPerAmbience }">{{ editor.pedCount }} / {{ editor.maxPedsPerAmbience }}</span>
        <template v-if="trigger">
          <label>{{ t('zoneEnter') }}</label>
          <input type="number" min="5" max="1000" step="5" :value="trigger.enter" :disabled="editor.readOnly" @change="editor.setTrigger({ enter: Math.max(5, num($event)) })" />
          <label>{{ t('zoneExit') }}</label>
          <input type="number" min="5" max="1200" step="5" :value="trigger.exit" :disabled="editor.readOnly" @change="editor.setTrigger({ exit: num($event) })" />
        </template>
        <label>{{ t('schedule') }}</label>
        <div class="toggles">
          <label class="toggle">
            <input type="checkbox" :checked="!!schedule" :disabled="editor.readOnly" @change="toggleSchedule(($event.target as HTMLInputElement).checked)" />
            {{ schedule ? '' : t('scheduleAlways') }}
          </label>
          <template v-if="schedule">
            <input type="time" class="time" :value="schedule.from" :disabled="editor.readOnly" @change="onSchedule('from', $event)" />
            <input type="time" class="time" :value="schedule.to" :disabled="editor.readOnly" @change="onSchedule('to', $event)" />
          </template>
        </div>
      </div>
      <Vec3Field v-if="trigger" :label="t('zoneCenter')" :value="trigger.center" :step="1" :disabled="editor.readOnly" @change="(center: Vec3) => editor.setTrigger({ center })" />
      <button class="btn" :disabled="editor.readOnly" @click="editor.centerZoneOnCamera()">{{ t('zoneCenterCamera') }}</button>
    </template>
  </div>
</template>

<style scoped>
.summary { padding: 14px; background: var(--surface-2); display: flex; flex-direction: column; gap: 10px; max-height: 65%; overflow-y: auto; }
.grid { display: grid; grid-template-columns: 70px 1fr; gap: 6px 10px; align-items: center; }
.grid > label { font-size: var(--fs-xs); color: var(--text-3); }
.grid input, .grid select { font-size: var(--fs-sm); padding: 5px 7px; }
.value { font-size: var(--fs-sm); color: var(--text-2); }
.toggles { display: flex; gap: 12px; }
.toggle { display: flex; align-items: center; gap: 5px; font-size: var(--fs-sm); color: var(--text-2); }
.toggles .time { width: 64px; padding: 4px; font-size: var(--fs-xs); }
.ambience-title { margin-top: 8px; }
.switch-row { display: flex; align-items: center; justify-content: space-between; font-size: var(--fs-sm); }
.toggle-switch { width: 34px; height: 18px; border: none; border-radius: 9px; background: var(--surface-3); position: relative; cursor: pointer; }
.toggle-switch::after { content: ''; position: absolute; top: 3px; left: 3px; width: 12px; height: 12px; border-radius: 50%; background: var(--text-2); transition: left 0.15s; }
.toggle-switch.on { background: var(--accent); }
.toggle-switch.on::after { left: 19px; background: var(--on-accent); }
.note { margin: 0; font-size: var(--fs-xs); color: var(--text-3); line-height: 1.5; }
.value.warn { color: var(--warning); }
</style>
