<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { VEHICLE_DOORS } from '../catalog'
import { KIND_LABEL, baseTransform } from '../scene'
import { useEditor } from '../stores/editor'
import type { Vec3 } from '../types'
import Icon from './Icon.vue'
import Vec3Field from './Vec3Field.vue'

const editor = useEditor()

const entity = computed(() => editor.selected)
const transform = computed(() => (editor.scene && entity.value ? baseTransform(editor.scene, entity.value.id) : undefined))
const disabled = computed(() => !editor.canEdit || editor.gizmoActive)
const props = computed(() => entity.value?.props ?? {})

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
  if (entity.value && transform.value) editor.setTransform(entity.value.id, pos, transform.value.rot)
}
function setRot(rot: Vec3) {
  if (entity.value && transform.value) editor.setTransform(entity.value.id, transform.value.pos, rot)
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
    <div v-if="!entity" class="empty">
      <p class="faint">Select an entity in the viewport or in the outliner to edit it.</p>
    </div>

    <template v-else>
      <header class="head">
        <div class="kind faint"><Icon :name="entity.kind" :size="14" /> {{ KIND_LABEL[entity.kind] }} · <span class="mono">{{ entity.id }}</span></div>
        <input
          class="title"
          :value="entity.label"
          maxlength="64"
          :disabled="disabled"
          @change="editor.updateEntity(entity.id, { label: ($event.target as HTMLInputElement).value.trim() || entity.label })"
        />
        <label class="model">
          <span class="faint">Model</span>
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
        <section>
          <div class="section-title">Transform</div>
          <template v-if="transform">
            <Vec3Field label="Position" :value="transform.pos" :step="0.05" :disabled="disabled" @change="setPos" />
            <Vec3Field label="Rotation" :value="transform.rot" :step="1" :disabled="disabled" @change="setRot" />
          </template>
          <div class="tools">
            <button class="btn" :disabled="disabled" @click="editor.startGizmo(entity.id, 'translate')"><Icon name="move" :size="14" /> Move</button>
            <button class="btn" :disabled="disabled" @click="editor.startGizmo(entity.id, 'rotate')"><Icon name="rotate" :size="14" /> Rotate</button>
            <button class="btn" :disabled="disabled" @click="editor.ground(entity.id)"><Icon name="ground" :size="14" /> Ground</button>
            <button class="btn icon" title="Focus camera (F)" @click="editor.focus(entity.id)"><Icon name="focus" :size="14" /></button>
          </div>
          <p v-if="editor.gizmoActive" class="hint">Drag the gizmo. <b>W</b> move · <b>R</b> rotate · <b>Enter</b> confirm · <b>Esc</b> cancel</p>
        </section>

        <section v-if="entity.kind === 'ped'">
          <div class="section-title">Animation</div>
          <input v-model="animDict" class="mono" placeholder="Dictionary" :disabled="disabled" />
          <input v-model="animClip" class="mono" placeholder="Clip" :disabled="disabled" @keydown.enter="applyAnim" />
          <button class="btn" :disabled="disabled" @click="applyAnim">Apply animation</button>
          <div class="section-title sub">Scenario</div>
          <input
            class="mono"
            :value="(props.scenario as string) ?? ''"
            placeholder="WORLD_HUMAN_SMOKING"
            :disabled="disabled"
            @change="setScenario(($event.target as HTMLInputElement).value)"
          />
        </section>

        <section v-if="entity.kind === 'vehicle'">
          <div class="section-title">Vehicle</div>
          <label class="switch"><input type="checkbox" :checked="props.engine === true" :disabled="disabled" @change="setProp('engine', ($event.target as HTMLInputElement).checked || undefined)" /> Engine on</label>
          <label class="switch"><input type="checkbox" :checked="props.headlights === true" :disabled="disabled" @change="setProp('headlights', ($event.target as HTMLInputElement).checked || undefined)" /> Headlights</label>
          <label class="switch"><input type="checkbox" :checked="props.siren === true" :disabled="disabled" @change="setProp('siren', ($event.target as HTMLInputElement).checked || undefined)" /> Siren</label>
          <label class="range">
            <span>Dirt <span class="mono faint">{{ Number(props.dirt ?? 0).toFixed(1) }}</span></span>
            <input type="range" min="0" max="15" step="0.5" :value="props.dirt ?? 0" :disabled="disabled" @change="setProp('dirt', Number(($event.target as HTMLInputElement).value) || undefined)" />
          </label>
          <div class="section-title sub">Doors open</div>
          <div class="doors">
            <button v-for="(door, i) in VEHICLE_DOORS" :key="door" class="btn" :class="{ active: doors.includes(i) }" :disabled="disabled" @click="toggleDoor(i)">
              {{ door }}
            </button>
          </div>
        </section>

        <section>
          <button class="btn danger" :disabled="disabled" @click="editor.removeEntity(entity.id)"><Icon name="trash" :size="14" /> Delete entity</button>
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
.tools { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 4px; }
.hint { margin: 0; font-size: var(--fs-xs); color: var(--accent); line-height: 1.5; }
.switch { display: flex; align-items: center; gap: 8px; font-size: var(--fs-sm); color: var(--text-2); }
.range { display: flex; flex-direction: column; gap: 6px; font-size: var(--fs-sm); color: var(--text-2); }
.doors { display: grid; grid-template-columns: 1fr 1fr; gap: 4px; }
.doors .btn { font-weight: 500; }
</style>
