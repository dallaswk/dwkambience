<script setup lang="ts">
import type { Vec3 } from '../types'

const props = defineProps<{ label: string; value: Vec3; step: number; disabled?: boolean }>()
const emit = defineEmits<{ change: [value: Vec3] }>()

const AXES = ['X', 'Y', 'Z'] as const

function onChange(index: number, e: Event) {
  const n = Number((e.target as HTMLInputElement).value)
  if (!Number.isFinite(n)) return
  const next = [...props.value] as Vec3
  next[index] = n
  emit('change', next)
}
</script>

<template>
  <div class="vec3">
    <span class="label">{{ label }}</span>
    <label v-for="(axis, i) in AXES" :key="axis" class="axis">
      <span>{{ axis }}</span>
      <input type="number" :step="step" :value="value[i]" :disabled="disabled" @change="onChange(i, $event)" />
    </label>
  </div>
</template>

<style scoped>
.vec3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; align-items: center; }
.label { grid-column: 1 / -1; font-size: var(--fs-xs); color: var(--text-3); }
.axis { position: relative; }
.axis span {
  position: absolute;
  left: 6px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 10px;
  font-weight: 700;
  color: var(--text-3);
  pointer-events: none;
}
.axis input { width: 100%; padding: 5px 4px 5px 18px; }
</style>
