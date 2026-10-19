<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { VEHICLE_DOORS } from '../catalog'
import { loadSounds, type SoundAsset } from '../audio'
import { t, tOr } from '../i18n'
import { KIND_LABEL, baseTransform, formatTime, visibleAt } from '../scene'
import { useEditor } from '../stores/editor'
import type { Color, Facing, Vec3 } from '../types'
import { useTimeline } from '../stores/timeline'
import Icon from './Icon.vue'
import KeyPanel from './KeyPanel.vue'
import Vec3Field from './Vec3Field.vue'

const editor = useEditor()
const timeline = useTimeline()

const entity = computed(() => editor.selected)
// Pose en el instante actual (la lee el cliente); mientras llega, la primera key
const transform = computed(() => editor.pose ?? (editor.scene && entity.value ? baseTransform(editor.scene, entity.value.id) : undefined))
const disabled = computed(() => !editor.canEdit || editor.gizmoActive)
const props = computed(() => entity.value?.props ?? {})
const isGameEntity = computed(() => !!entity.value?.model)
const crowd = computed(() => entity.value?.crowd)
const sound = computed(() => entity.value?.sound)
const sounds = ref<SoundAsset[]>([])
onMounted(() => loadSounds().then((list) => (sounds.value = list)))

// Máximo de personas para esta multitud sin pasar el límite del ambience
const crowdMax = computed(() => {
  if (!crowd.value) return 0
  // En ambiences manda el límite de peds; en cutscenes, el de entidades del estudio
  const limit = editor.meta?.type === 'ambience'
    ? editor.maxPedsPerAmbience - (editor.pedCount - crowd.value.count)
    : (editor.studio?.maxEntities ?? 60) - (editor.entityCount - crowd.value.count)
  return Math.max(1, Math.min(60, limit))
})

const FACINGS: Facing[] = ['random', 'along', 'point']

const text3d = computed(() => entity.value?.text)
const light = computed(() => entity.value?.light)
const ptfx = computed(() => entity.value?.ptfx)
const screen = computed(() => entity.value?.screen)
const visibleNow = computed(() => (editor.scene && entity.value ? visibleAt(editor.scene, entity.value.id, timeline.time) : true))

const toHex = (c: Color) => `#${c.map((v) => v.toString(16).padStart(2, '0')).join('')}`
const fromHex = (hex: string): Color => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)) as Color
const FONTS = [0, 1, 2, 4, 6, 7]
const num = (e: Event) => Number((e.target as HTMLInputElement).value)
const text = (e: Event) => (e.target as HTMLInputElement).value

// Animación de ped: se edita en local y se aplica con el botón para no lanzar una anim por tecla
const animDict = ref('')
const animClip = ref('')
watch(
  () => [entity.value?.id, props.value.anim],
  () => {
    const anim = props.value.anim as { dict?: string; clip?: string } | undefined
    animDict.value = anim?.dict ?? ''
    animClip.value = anim?.clip ?? ''
  },
  { immediate: true },
)

const doors = computed(() => (Array.isArray(props.value.doors) ? (props.value.doors as number[]) : []))

function setPos(pos: Vec3) {
  if (entity.value && transform.value) editor.setPose(entity.value.id, pos, transform.value.rot)
}
function setRot(rot: Vec3) {
  if (entity.value && transform.value) editor.setPose(entity.value.id, transform.value.pos, rot)
}
function setProp(key: string, value: Parameters<typeof editor.setProp>[2]) {
  if (entity.value) editor.setProp(entity.value.id, key, value)
}
function applyAnim() {
  const dict = animDict.value.trim()
  const clip = animClip.value.trim()
  if (!entity.value) return
  editor.updateEntity(entity.value.id, {
    props: { ...withoutKeys(props.value, ['anim', 'scenario']), ...(dict && clip ? { anim: { dict, clip } } : {}) },
  })
}
function addAnimToTimeline() {
  const dict = animDict.value.trim()
  const clip = animClip.value.trim()
  if (entity.value && dict && clip) editor.addAnimClip(entity.value.id, dict, clip)
}
function setScenario(value: string) {
  if (!entity.value) return
  const scenario = value.trim()
  editor.updateEntity(entity.value.id, {
    props: { ...withoutKeys(props.value, ['anim', 'scenario']), ...(scenario ? { scenario } : {}) },
  })
}
function withoutKeys<T extends Record<string, unknown>>(obj: T, keys: string[]) {
  return Object.fromEntries(Object.entries(obj).filter(([k]) => !keys.includes(k))) as T
}
function toggleDoor(door: number) {
  const next = doors.value.includes(door) ? doors.value.filter((d) => d !== door) : [...doors.value, door].sort()
  setProp('doors', next.length ? next : undefined)
}
</script>

<template>
  <aside class="inspector">
    <KeyPanel v-if="editor.selectedItem" />

    <div v-else-if="!entity" class="empty">
      <p class="faint">{{ t('inspectorEmpty') }}</p>
    </div>

    <template v-else>
      <header class="head">
        <div class="kind faint"><Icon :name="entity.kind" :size="14" /> {{ t(KIND_LABEL[entity.kind]) }} · <span class="mono">{{ entity.id }}</span></div>
        <input
          class="title"
          :value="entity.label"
          maxlength="64"
          :disabled="disabled"
          @change="editor.updateEntity(entity.id, { label: ($event.target as HTMLInputElement).value.trim() || entity.label })"
        />
        <label v-if="isGameEntity" class="model">
          <span class="faint">{{ t('model') }}</span>
          <input
            class="mono"
            :value="entity.model"
            maxlength="64"
            :disabled="disabled"
            @change="editor.updateEntity(entity.id, { model: ($event.target as HTMLInputElement).value.trim().toLowerCase() || entity.model })"
          />
        </label>
      </header>

      <div class="scroll body">
        <section v-if="entity.kind !== 'crowd'">
          <div class="section-title">{{ t('transform') }}</div>
          <template v-if="transform">
            <Vec3Field :label="t('position')" :value="transform.pos" :step="0.05" :disabled="disabled" @change="setPos" />
            <Vec3Field v-if="entity.kind !== 'sound'" :label="t('rotation')" :value="transform.rot" :step="1" :disabled="disabled" @change="setRot" />
          </template>
          <div v-if="!isGameEntity" class="tools single">
            <button class="btn" :disabled="disabled" @click="editor.moveToCamera(entity.id)"><Icon name="focus" :size="14" /> {{ t('moveToCamera') }}</button>
          </div>
          <div v-else class="tools">
            <button class="btn" :disabled="disabled" @click="editor.startGizmo(entity.id, 'translate')"><Icon name="move" :size="14" /> {{ t('move') }}</button>
            <button class="btn" :disabled="disabled" @click="editor.startGizmo(entity.id, 'rotate')"><Icon name="rotate" :size="14" /> {{ t('rotate') }}</button>
            <button class="btn" :disabled="disabled" @click="editor.ground(entity.id)"><Icon name="ground" :size="14" /> {{ t('ground') }}</button>
            <button class="btn icon" :title="t('focusCamera')" @click="editor.focus(entity.id)"><Icon name="focus" :size="14" /></button>
          </div>
          <p v-if="editor.gizmoActive" class="hint">{{ t('gizmoHint') }}</p>
        </section>

        <section v-if="entity.kind === 'ped'">
          <div class="section-title">{{ t('animation') }}</div>
          <input v-model="animDict" class="mono" :placeholder="t('animDict')" :disabled="disabled" />
          <input v-model="animClip" class="mono" :placeholder="t('animClip')" :disabled="disabled" @keydown.enter="applyAnim" />
          <button class="btn" :disabled="disabled" @click="applyAnim">{{ t('applyAnimation') }}</button>
          <button class="btn" :disabled="disabled || !animDict.trim() || !animClip.trim()" @click="addAnimToTimeline">
            <Icon name="plus" :size="14" /> {{ t('addAnimToTimeline', { time: formatTime(timeline.time) }) }}
          </button>
          <div class="section-title sub">{{ t('scenario') }}</div>
          <input
            class="mono"
            :value="(props.scenario as string) ?? ''"
            placeholder="WORLD_HUMAN_SMOKING"
            :disabled="disabled"
            @change="setScenario(($event.target as HTMLInputElement).value)"
          />
        </section>

        <section v-if="isGameEntity && editor.meta?.type === 'ambience'">
          <div class="section-title">{{ t('network') }}</div>
          <label class="switch">
            <input type="checkbox" :checked="entity.networked" :disabled="disabled" @change="editor.setNetworked(entity.id, ($event.target as HTMLInputElement).checked)" />
            {{ t('networked') }}
          </label>
          <p class="note">{{ t('networkedHint', { n: editor.networkedCount, max: editor.maxNetworked }) }}</p>
        </section>

        <section v-if="screen || editor.isScreenModel(entity.model)">
          <div class="section-title">{{ t('screen') }}</div>
          <template v-if="screen">
            <label class="field column">
              <span>{{ t('textContent') }}</span>
              <input :value="screen.content" maxlength="200" :disabled="disabled" @change="editor.updateScreen(entity.id, { content: text($event).trim() || screen!.content })" />
            </label>
            <label class="field">
              <span>{{ t('color') }}</span>
              <input type="color" :value="toHex(screen.color)" :disabled="disabled" @change="editor.updateScreen(entity.id, { color: fromHex(text($event)) })" />
            </label>
            <label class="field">
              <span>{{ t('screenBackground') }}</span>
              <input type="color" :value="toHex(screen.background)" :disabled="disabled" @change="editor.updateScreen(entity.id, { background: fromHex(text($event)) })" />
            </label>
            <label class="range">
              <span>{{ t('textScale') }} <span class="mono faint">{{ screen.scale.toFixed(1) }}</span></span>
              <input type="range" min="0.1" max="5" step="0.1" :value="screen.scale" :disabled="disabled" @change="editor.updateScreen(entity.id, { scale: num($event) })" />
            </label>
            <label class="field">
              <span>{{ t('textFont') }}</span>
              <select :value="screen.font" :disabled="disabled" @change="editor.updateScreen(entity.id, { font: num($event) })">
                <option v-for="f in FONTS" :key="f" :value="f">{{ f }}</option>
              </select>
            </label>
            <p class="note">{{ t('screenHint') }}</p>
            <button class="btn" :disabled="disabled" @click="editor.setScreen(entity.id, undefined)">{{ t('screenRemove') }}</button>
          </template>
          <button v-else class="btn" :disabled="disabled" @click="editor.updateScreen(entity.id, {})"><Icon name="screen" :size="14" /> {{ t('screenAdd') }}</button>
        </section>

        <section v-if="text3d">
          <div class="section-title">{{ t('kindText') }}</div>
          <label class="field column">
            <span>{{ t('textContent') }}</span>
            <input :value="text3d.content" maxlength="200" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { content: text($event).trim() || text3d!.content })" />
          </label>
          <label class="field">
            <span>{{ t('color') }}</span>
            <input type="color" :value="toHex(text3d.color)" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { color: fromHex(text($event)) })" />
          </label>
          <label class="range">
            <span>{{ t('textScale') }} <span class="mono faint">{{ text3d.scale.toFixed(1) }}</span></span>
            <input type="range" min="0.1" max="5" step="0.1" :value="text3d.scale" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { scale: num($event) })" />
          </label>
          <label class="field">
            <span>{{ t('textFont') }}</span>
            <select :value="text3d.font" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { font: num($event) })">
              <option v-for="f in FONTS" :key="f" :value="f">{{ f }}</option>
            </select>
          </label>
          <label class="switch"><input type="checkbox" :checked="text3d.outline" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { outline: ($event.target as HTMLInputElement).checked })" /> {{ t('textOutline') }}</label>
          <label class="switch"><input type="checkbox" :checked="text3d.backface" :disabled="disabled" @change="editor.updateDef(entity.id, 'text', { backface: ($event.target as HTMLInputElement).checked })" /> {{ t('textBackface') }}</label>
        </section>

        <section v-if="light">
          <div class="section-title">{{ t('kindLight') }}</div>
          <label class="field">
            <span>{{ t('lightType') }}</span>
            <select :value="light.type" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { type: text($event) as 'point' | 'spot' })">
              <option value="point">{{ t('lightPoint') }}</option>
              <option value="spot">{{ t('lightSpot') }}</option>
            </select>
          </label>
          <label class="field">
            <span>{{ t('color') }}</span>
            <input type="color" :value="toHex(light.color)" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { color: fromHex(text($event)) })" />
          </label>
          <label class="range">
            <span>{{ t('lightRange') }} <span class="mono faint">{{ light.range }} m</span></span>
            <input type="range" min="0.5" max="100" step="0.5" :value="light.range" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { range: num($event) })" />
          </label>
          <label class="range">
            <span>{{ t('lightIntensity') }} <span class="mono faint">{{ light.intensity }}</span></span>
            <input type="range" min="0" max="50" step="0.5" :value="light.intensity" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { intensity: num($event) })" />
          </label>
          <template v-if="light.type === 'spot'">
            <label class="range">
              <span>{{ t('lightAngle') }} <span class="mono faint">{{ light.angle }}°</span></span>
              <input type="range" min="1" max="90" step="1" :value="light.angle" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { angle: num($event) })" />
            </label>
            <label class="range">
              <span>{{ t('lightFalloff') }} <span class="mono faint">{{ light.falloff }}</span></span>
              <input type="range" min="0" max="50" step="0.5" :value="light.falloff" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { falloff: num($event) })" />
            </label>
          </template>
          <label class="switch"><input type="checkbox" :checked="light.shadow" :disabled="disabled" @change="editor.updateDef(entity.id, 'light', { shadow: ($event.target as HTMLInputElement).checked })" /> {{ t('lightShadow') }}</label>
          <p class="note">{{ t('lightHint') }}</p>
        </section>

        <section v-if="ptfx">
          <div class="section-title">{{ t('kindPtfx') }}</div>
          <label class="field column">
            <span>{{ t('ptfxEffect') }}</span>
            <select
              class="mono"
              :value="`${ptfx.asset}/${ptfx.effect}`"
              :disabled="disabled"
              @change="editor.updateDef(entity.id, 'ptfx', { asset: text($event).split('/')[0], effect: text($event).split('/')[1] })"
            >
              <option v-if="!editor.ptfxCatalog.some((p) => p.asset === ptfx!.asset && p.effect === ptfx!.effect)" :value="`${ptfx.asset}/${ptfx.effect}`">{{ ptfx.asset }}/{{ ptfx.effect }}</option>
              <option v-for="p in editor.ptfxCatalog" :key="`${p.asset}/${p.effect}`" :value="`${p.asset}/${p.effect}`">{{ p.asset }}/{{ p.effect }}</option>
            </select>
          </label>
          <label class="range">
            <span>{{ t('textScale') }} <span class="mono faint">{{ ptfx.scale.toFixed(1) }}</span></span>
            <input type="range" min="0.1" max="10" step="0.1" :value="ptfx.scale" :disabled="disabled" @change="editor.updateDef(entity.id, 'ptfx', { scale: num($event) })" />
          </label>
          <label class="switch">
            <input type="checkbox" :checked="!!ptfx.color" :disabled="disabled" @change="editor.updateDef(entity.id, 'ptfx', { color: ($event.target as HTMLInputElement).checked ? [255, 255, 255] : undefined })" />
            {{ t('ptfxTint') }}
          </label>
          <label v-if="ptfx.color" class="field">
            <span>{{ t('color') }}</span>
            <input type="color" :value="toHex(ptfx.color)" :disabled="disabled" @change="editor.updateDef(entity.id, 'ptfx', { color: fromHex(text($event)) })" />
          </label>
        </section>

        <section v-if="sound">
          <div class="section-title">{{ t('soundEmitter') }}</div>
          <label class="field">
            <span>{{ t('clipAsset') }}</span>
            <select :value="sound.asset" :disabled="disabled" @change="editor.updateSound(entity.id, { asset: text($event) })">
              <option v-if="!sounds.some((s) => s.id === sound!.asset)" :value="sound.asset">{{ sound.asset }}</option>
              <option v-for="s in sounds" :key="s.id" :value="s.id">{{ s.id }}</option>
            </select>
          </label>
          <label class="range">
            <span>{{ t('clipVolume') }} <span class="mono faint">{{ Math.round(sound.volume * 100) }}%</span></span>
            <input type="range" min="0" max="1" step="0.01" :value="sound.volume" :disabled="disabled" @change="editor.updateSound(entity.id, { volume: num($event) })" />
          </label>
          <label class="range">
            <span>{{ t('soundRange') }} <span class="mono faint">{{ sound.range }} m</span></span>
            <input type="range" min="1" max="200" step="1" :value="sound.range" :disabled="disabled" @change="editor.updateSound(entity.id, { range: num($event) })" />
          </label>
          <label class="switch"><input type="checkbox" :checked="sound.loop" :disabled="disabled" @change="editor.updateSound(entity.id, { loop: ($event.target as HTMLInputElement).checked })" /> {{ t('clipLoop') }}</label>
        </section>

        <section v-if="crowd">
          <div class="section-title">{{ t('crowd') }}</div>
          <label class="field">
            <span>{{ t('crowdPreset') }}</span>
            <select :value="crowd.preset" :disabled="disabled" @change="editor.updateCrowd(entity.id, { preset: text($event) })">
              <option v-for="p in editor.crowdPresets" :key="p" :value="p">{{ tOr(`preset_${p}`, p) }}</option>
            </select>
          </label>
          <template v-if="crowd.preset === 'custom'">
            <label class="field column">
              <span>{{ t('crowdModels') }}</span>
              <input
                class="mono"
                :value="(crowd.models ?? []).join(', ')"
                placeholder="a_m_y_hipster_01, a_f_y_hipster_01"
                :disabled="disabled"
                @change="editor.updateCrowd(entity.id, { models: text($event).split(',').map((m) => m.trim().toLowerCase()).filter((m) => /^[\w-]+$/.test(m)).slice(0, 16) })"
              />
            </label>
            <label class="field column">
              <span>{{ t('scenario') }}</span>
              <input
                class="mono"
                :value="crowd.scenario ?? ''"
                placeholder="WORLD_HUMAN_STAND_IMPATIENT"
                :disabled="disabled"
                @change="editor.updateCrowd(entity.id, { scenario: text($event).trim().toUpperCase().replace(/[^\w-]/g, '') || undefined })"
              />
            </label>
          </template>
          <label class="range">
            <span>{{ t('crowdCount') }} <span class="mono faint">{{ crowd.count }} / {{ crowdMax }}</span></span>
            <input type="range" min="1" :max="crowdMax" step="1" :value="crowd.count" :disabled="disabled" @change="editor.updateCrowd(entity.id, { count: num($event) })" />
          </label>
          <label class="range">
            <span>{{ t('crowdSpread') }} <span class="mono faint">{{ crowd.spread }} m</span></span>
            <input type="range" min="0" max="30" step="0.5" :value="crowd.spread" :disabled="disabled" @change="editor.updateCrowd(entity.id, { spread: num($event) })" />
          </label>
          <label class="field">
            <span>{{ t('crowdFacing') }}</span>
            <select :value="crowd.facing" :disabled="disabled" @change="text($event) === 'point' ? editor.crowdLookAtCamera(entity.id) : editor.updateCrowd(entity.id, { facing: text($event) as Facing })">
              <option v-for="f in FACINGS" :key="f" :value="f">{{ t(f === 'random' ? 'facingRandom' : f === 'along' ? 'facingAlong' : 'facingPoint') }}</option>
            </select>
          </label>
          <button v-if="crowd.facing === 'point'" class="btn" :disabled="disabled" @click="editor.crowdLookAtCamera(entity.id)">{{ t('crowdLookAtCamera') }}</button>
          <button class="btn" :disabled="disabled" @click="editor.regenerateCrowd(entity.id)"><Icon name="loop" :size="14" /> {{ t('crowdRegenerate') }}</button>

          <div class="section-title sub">{{ t('crowdPoints') }} <span class="faint">{{ crowd.points.length }}/32</span></div>
          <p class="note">{{ crowd.points.length === 1 ? t('crowdAreaHint') : t('crowdLineHint') }}</p>
          <ol class="points">
            <li v-for="(p, i) in crowd.points" :key="i">
              <span class="mono">{{ p.map((v) => v.toFixed(1)).join(', ') }}</span>
              <button class="btn icon ghost" :disabled="disabled || crowd.points.length <= 1" :title="t('delete')" @click="editor.removeCrowdPoint(entity.id, i)"><Icon name="close" :size="12" /></button>
            </li>
          </ol>
          <div class="tools two">
            <button class="btn" :disabled="disabled || crowd.points.length >= 32" @click="editor.addCrowdPoint(entity.id)"><Icon name="plus" :size="14" /> {{ t('crowdAddPoint') }}</button>
            <button class="btn" :class="{ active: editor.placingPoints }" :disabled="disabled" @click="editor.placingPoints = !editor.placingPoints">{{ t('crowdPlaceMode') }}</button>
          </div>
        </section>

        <section v-if="entity.kind === 'vehicle'">
          <div class="section-title">{{ t('vehicle') }}</div>
          <label class="switch"><input type="checkbox" :checked="props.engine === true" :disabled="disabled" @change="setProp('engine', ($event.target as HTMLInputElement).checked || undefined)" /> {{ t('engineOn') }}</label>
          <label class="switch"><input type="checkbox" :checked="props.headlights === true" :disabled="disabled" @change="setProp('headlights', ($event.target as HTMLInputElement).checked || undefined)" /> {{ t('headlights') }}</label>
          <label class="switch"><input type="checkbox" :checked="props.siren === true" :disabled="disabled" @change="setProp('siren', ($event.target as HTMLInputElement).checked || undefined)" /> {{ t('siren') }}</label>
          <label class="range">
            <span>{{ t('dirt') }} <span class="mono faint">{{ Number(props.dirt ?? 0).toFixed(1) }}</span></span>
            <input type="range" min="0" max="15" step="0.5" :value="props.dirt ?? 0" :disabled="disabled" @change="setProp('dirt', Number(($event.target as HTMLInputElement).value) || undefined)" />
          </label>
          <div class="section-title sub">{{ t('doorsOpen') }}</div>
          <div class="doors">
            <button v-for="(door, i) in VEHICLE_DOORS" :key="door" class="btn" :class="{ active: doors.includes(i) }" :disabled="disabled" @click="toggleDoor(i)">
              {{ t(door) }}
            </button>
          </div>
        </section>

        <section>
          <div class="section-title">{{ t('visibility') }}</div>
          <p class="note">{{ visibleNow ? t('visibleNow') : t('hiddenNow') }} · {{ formatTime(timeline.time) }}</p>
          <button class="btn" :disabled="disabled" @click="editor.toggleVisibility(entity.id)">
            <Icon name="eye" :size="14" /> {{ visibleNow ? t('hideFromHere') : t('showFromHere') }}
          </button>
        </section>

        <section>
          <button class="btn danger" :disabled="disabled" @click="editor.removeEntity(entity.id)"><Icon name="trash" :size="14" /> {{ t('deleteEntity') }}</button>
        </section>
      </div>
    </template>
  </aside>
</template>

<style scoped>
.inspector { grid-area: right; display: flex; flex-direction: column; min-height: 0; background: var(--surface-1); }
.empty { padding: 20px 16px; font-size: var(--fs-sm); line-height: 1.5; }
.head { padding: 14px; background: var(--surface-2); display: flex; flex-direction: column; gap: 8px; }
.kind { display: flex; align-items: center; gap: 6px; font-size: var(--fs-xs); }
.title { font-size: var(--fs-lg); font-weight: 600; background: transparent; padding: 4px 0; border-radius: 0; }
.title:focus { border-color: transparent; border-bottom-color: var(--accent); }
.model { display: grid; grid-template-columns: 54px 1fr; align-items: center; gap: 4px; font-size: var(--fs-xs); }
.model input { font-size: var(--fs-sm); }
.body { flex: 1; }
section { padding: 14px; display: flex; flex-direction: column; gap: 8px; }
section + section { border-top: 1px solid var(--line); }
.sub { margin-top: 6px; }
.tools { display: grid; grid-template-columns: 1fr 1fr 1fr auto; gap: 6px; margin-top: 4px; }
.tools.single { grid-template-columns: 1fr; }
.note { margin: 0; font-size: var(--fs-xs); color: var(--text-3); line-height: 1.5; }
.tools.two { grid-template-columns: 1fr 1fr; }
.field { display: grid; grid-template-columns: 1fr 150px; align-items: center; gap: 8px; font-size: var(--fs-sm); color: var(--text-2); }
.field.column { grid-template-columns: 1fr; }
.field input, .field select { font-size: var(--fs-sm); padding: 5px 7px; }
.field input[type='color'] { padding: 2px; height: 28px; }
.points { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; max-height: 140px; overflow-y: auto; }
.points li { display: flex; align-items: center; justify-content: space-between; font-size: var(--fs-xs); color: var(--text-2); padding-left: 4px; }
.points .btn.icon { width: 24px; height: 24px; }
.tools .btn { padding: 0 8px; }
.hint { margin: 0; font-size: var(--fs-xs); color: var(--accent); line-height: 1.5; }
.switch { display: flex; align-items: center; gap: 8px; font-size: var(--fs-sm); color: var(--text-2); }
.range { display: flex; flex-direction: column; gap: 6px; font-size: var(--fs-sm); color: var(--text-2); }
.doors { display: grid; grid-template-columns: 1fr 1fr; gap: 4px; }
.doors .btn { font-weight: 500; }
</style>
