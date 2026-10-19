<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { loadSounds, type SoundAsset } from '../audio'
import { t } from '../i18n'
import type { MessageKey } from '../i18n'
import { useEditor } from '../stores/editor'
import type { AnimClip, AudioClip, Ease, EventKey, Key, Vec3, VisibilityKey } from '../types'
import Icon from './Icon.vue'
import Vec3Field from './Vec3Field.vue'

const editor = useEditor()
const sel = computed(() => editor.selectedItem)
const disabled = computed(() => !editor.canEdit)

const EASES: { value: Ease; label: MessageKey }[] = [
  { value: 'linear', label: 'easeLinear' },
  { value: 'in', label: 'easeIn' },
  { value: 'out', label: 'easeOut' },
  { value: 'inOut', label: 'easeInOut' },
  { value: 'spline', label: 'easeSpline' },
]

const channel = computed(() => sel.value?.track.channel)
const poseKey = computed(() => (channel.value === 'transform' || channel.value === 'camera' ? (sel.value!.item as Key) : null))
const eventKey = computed(() => (channel.value === 'event' ? (sel.value!.item as EventKey) : null))
const audioClip = computed(() => (channel.value === 'audio' ? (sel.value!.item as AudioClip) : null))
const animClip = computed(() => (channel.value === 'anim' ? (sel.value!.item as AnimClip) : null))
const visKey = computed(() => (channel.value === 'visibility' ? (sel.value!.item as VisibilityKey) : null))

const sounds = ref<SoundAsset[]>([])
onMounted(() => loadSounds().then((list) => (sounds.value = list)))

const seconds = (ms: number) => +(ms / 1000).toFixed(2)
const ms = (e: Event) => Math.max(0, Math.round(Number((e.target as HTMLInputElement).value) * 1000))
const value = (e: Event) => (e.target as HTMLInputElement).value

function setTime(e: Event) {
  const ok = editor.updateSelected(sel.value?.kind === 'key' ? { t: ms(e) } : { start: ms(e) })
  if (!ok) (e.target as HTMLInputElement).value = String(seconds(poseKey.value?.t ?? 0))
}

const title = computed(() => (sel.value?.kind === 'clip' ? t('clipTitle') : t('keyTitle')))
const start = computed(() => {
  const item = sel.value?.item
  return item ? ('t' in item ? item.t : item.start) : 0
})
</script>

<template>
  <div v-if="sel" class="panel">
    <header class="head">
      <div class="kind faint"><Icon name="key" :size="13" /> {{ title }} · <span class="mono">{{ sel.track.id }}</span></div>
    </header>

    <div class="scroll body">
      <section>
        <label class="field">
          <span>{{ sel.kind === 'clip' ? t('clipStart') : t('keyTime') }}</span>
          <input type="number" step="0.1" min="0" :value="seconds(start)" :disabled="disabled" @change="setTime" />
        </label>

        <template v-if="poseKey">
          <label class="field">
            <span>{{ t('keyEase') }}</span>
            <select :value="poseKey.ease ?? 'linear'" :disabled="disabled" @change="editor.updateSelected({ ease: value($event) as Ease })">
              <option v-for="e in EASES" :key="e.value" :value="e.value">{{ t(e.label) }}</option>
            </select>
          </label>
          <label v-if="channel === 'camera'" class="field">
            <span>{{ t('keyFov') }}</span>
            <input type="number" min="1" max="130" step="1" :value="poseKey.fov ?? 50" :disabled="disabled" @change="editor.updateSelected({ fov: Number(value($event)) })" />
          </label>
          <template v-if="channel === 'camera'">
            <label class="switch">
              <input
                type="checkbox"
                :checked="poseKey.dofStrength !== undefined"
                :disabled="disabled"
                @change="($event.target as HTMLInputElement).checked
                  ? editor.updateSelected({ dofStrength: 0.8, dofNear: 2, dofFar: 15 })
                  : editor.updateSelected({ dofStrength: undefined, dofNear: undefined, dofFar: undefined })"
              />
              {{ t('dof') }}
            </label>
            <template v-if="poseKey.dofStrength !== undefined">
              <label class="field">
                <span>{{ t('dofStrength') }} <span class="mono faint">{{ Math.round(poseKey.dofStrength * 100) }}%</span></span>
                <input type="range" min="0" max="1" step="0.05" :value="poseKey.dofStrength" :disabled="disabled" @change="editor.updateSelected({ dofStrength: Number(value($event)) })" />
              </label>
              <label class="field">
                <span>{{ t('dofNear') }}</span>
                <input type="number" min="0" step="0.5" :value="poseKey.dofNear" :disabled="disabled" @change="editor.updateSelected({ dofNear: Math.max(0, Number(value($event))) })" />
              </label>
              <label class="field">
                <span>{{ t('dofFar') }}</span>
                <input type="number" min="0.5" step="0.5" :value="poseKey.dofFar" :disabled="disabled" @change="editor.updateSelected({ dofFar: Math.max((poseKey!.dofNear ?? 0) + 0.5, Number(value($event))) })" />
              </label>
            </template>
          </template>
          <Vec3Field :label="t('position')" :value="poseKey.pos" :step="0.05" :disabled="disabled" @change="(pos: Vec3) => editor.updateSelected({ pos })" />
          <Vec3Field :label="t('rotation')" :value="poseKey.rot" :step="1" :disabled="disabled" @change="(rot: Vec3) => editor.updateSelected({ rot })" />
        </template>

        <template v-if="eventKey">
          <template v-if="eventKey.type === 'fade'">
            <label class="field">
              <span>{{ t('fadeTo') }}</span>
              <select :value="eventKey.to" :disabled="disabled" @change="editor.updateSelected({ to: Number(value($event)) as 0 | 1 })">
                <option :value="1">{{ t('fadeToBlack') }}</option>
                <option :value="0">{{ t('fadeToClear') }}</option>
              </select>
            </label>
            <label class="field">
              <span>{{ t('eventDuration') }}</span>
              <input type="number" min="0" step="0.1" :value="seconds(eventKey.duration)" :disabled="disabled" @change="editor.updateSelected({ duration: ms($event) })" />
            </label>
          </template>
          <template v-else-if="eventKey.type === 'subtitle'">
            <label class="field column">
              <span>{{ t('subtitleText') }}</span>
              <input :value="eventKey.text" maxlength="200" :disabled="disabled" @change="editor.updateSelected({ text: value($event).trim() || eventKey.text })" />
            </label>
            <label class="field">
              <span>{{ t('eventDuration') }}</span>
              <input type="number" min="0.1" step="0.1" :value="seconds(eventKey.duration)" :disabled="disabled" @change="editor.updateSelected({ duration: Math.max(100, ms($event)) })" />
            </label>
          </template>
          <label v-else class="field column">
            <span>{{ t('triggerName') }}</span>
            <input
              class="mono"
              :value="eventKey.name"
              maxlength="64"
              :disabled="disabled"
              @change="editor.updateSelected({ name: value($event).replace(/[^\w-]/g, '_') || eventKey.name })"
            />
            <span class="hint faint">{{ t('triggerHint') }}</span>
          </label>
        </template>

        <label v-if="visKey" class="switch">
          <input type="checkbox" :checked="visKey.visible" :disabled="disabled" @change="editor.updateSelected({ visible: ($event.target as HTMLInputElement).checked })" />
          {{ t('visibleFromHere') }}
        </label>

        <template v-if="audioClip">
          <label class="field">
            <span>{{ t('clipAsset') }}</span>
            <select :value="audioClip.asset" :disabled="disabled" @change="editor.updateSelected({ asset: value($event) })">
              <option v-if="!sounds.some((s) => s.id === audioClip!.asset)" :value="audioClip.asset">{{ audioClip.asset }}</option>
              <option v-for="s in sounds" :key="s.id" :value="s.id">{{ s.id }}</option>
            </select>
          </label>
          <label class="field">
            <span>{{ t('clipVolume') }} <span class="mono faint">{{ Math.round(audioClip.volume * 100) }}%</span></span>
            <input type="range" min="0" max="1" step="0.01" :value="audioClip.volume" :disabled="disabled" @change="editor.updateSelected({ volume: Number(value($event)) })" />
          </label>
          <label class="field">
            <span>{{ t('clipFadeIn') }}</span>
            <input type="number" min="0" step="0.1" :value="seconds(audioClip.fadeIn)" :disabled="disabled" @change="editor.updateSelected({ fadeIn: ms($event) })" />
          </label>
          <label class="field">
            <span>{{ t('clipDuration') }}</span>
            <input
              type="number"
              min="0"
              step="0.1"
              :placeholder="t('clipDurationFull')"
              :value="audioClip.duration ? seconds(audioClip.duration) : ''"
              :disabled="disabled"
              @change="editor.updateSelected({ duration: ms($event) || undefined })"
            />
          </label>
          <label class="switch"><input type="checkbox" :checked="audioClip.loop" :disabled="disabled" @change="editor.updateSelected({ loop: ($event.target as HTMLInputElement).checked })" /> {{ t('clipLoop') }}</label>
        </template>

        <template v-if="animClip">
          <div class="mono anim-name">{{ animClip.dict }} · {{ animClip.clip }}</div>
          <p class="hint faint">{{ t('animLength', { s: seconds(animClip.length) }) }}</p>
          <label class="field">
            <span>{{ t('clipDuration') }}</span>
            <input type="number" min="0.1" step="0.1" :value="seconds(animClip.duration)" :disabled="disabled" @change="editor.updateSelected({ duration: Math.max(100, ms($event)) })" />
          </label>
          <label class="switch"><input type="checkbox" :checked="animClip.loop" :disabled="disabled" @change="editor.updateSelected({ loop: ($event.target as HTMLInputElement).checked })" /> {{ t('clipLoop') }}</label>
        </template>
      </section>

      <section>
        <button class="btn danger" :disabled="disabled" @click="editor.deleteSelected()"><Icon name="trash" :size="14" /> {{ t('deleteKey') }}</button>
      </section>
    </div>
  </div>
</template>

<style scoped>
.panel { display: flex; flex-direction: column; min-height: 0; flex: 1; }
.head { padding: 14px; background: var(--surface-2); }
.kind { display: flex; align-items: center; gap: 6px; font-size: var(--fs-xs); }
.body { flex: 1; }
section { padding: 14px; display: flex; flex-direction: column; gap: 10px; }
section + section { border-top: 1px solid var(--line); }
.field { display: grid; grid-template-columns: 1fr 120px; align-items: center; gap: 8px; font-size: var(--fs-sm); color: var(--text-2); }
.field.column { grid-template-columns: 1fr; }
.field input, .field select { font-size: var(--fs-sm); padding: 5px 7px; }
.switch { display: flex; align-items: center; gap: 8px; font-size: var(--fs-sm); color: var(--text-2); }
.hint { margin: 0; font-size: var(--fs-xs); line-height: 1.5; }
.anim-name { font-size: var(--fs-xs); color: var(--text-2); word-break: break-all; }
</style>
