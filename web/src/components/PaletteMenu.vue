<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { CATALOG } from '../catalog'
import type { EntityKind } from '../types'
import Icon from './Icon.vue'

const props = defineProps<{ kind: EntityKind; open: boolean }>()
const emit = defineEmits<{ spawn: [model: string]; close: [] }>()

const query = ref('')
const input = ref<HTMLInputElement | null>(null)

const items = computed(() => {
  const q = query.value.trim().toLowerCase()
  const list = CATALOG[props.kind] ?? []
  return q ? list.filter((i) => i.model.includes(q) || i.label.toLowerCase().includes(q)) : list
})

const custom = computed(() => {
  const q = query.value.trim().toLowerCase()
  return /^[\w-]+$/.test(q) && !items.value.some((i) => i.model === q) ? q : null
})

watch(
  () => props.open,
  async (open) => {
    if (!open) return
    query.value = ''
    await nextTick()
    input.value?.focus()
  },
)

function choose(model: string) {
  emit('spawn', model)
  emit('close')
}
</script>

<template>
  <div v-if="open" class="palette">
    <label class="search">
      <Icon name="search" :size="14" />
      <input
        ref="input"
        v-model="query"
        placeholder="Search or type a model name"
        @keydown.enter="custom ? choose(custom) : items[0] && choose(items[0].model)"
        @keydown.esc="emit('close')"
      />
    </label>
    <ul class="scroll">
      <li v-if="custom">
        <button @click="choose(custom)">
          <Icon name="plus" :size="14" />
          <span>Spawn <b class="mono">{{ custom }}</b></span>
        </button>
      </li>
      <li v-for="item in items" :key="item.model">
        <button @click="choose(item.model)">
          <span>{{ item.label }}</span>
          <span class="mono faint">{{ item.model }}</span>
        </button>
      </li>
      <li v-if="!items.length && !custom" class="empty faint">No matches</li>
    </ul>
  </div>
</template>

<style scoped>
.palette {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  width: 300px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 8px;
  z-index: 20;
}
.search {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 8px;
  background: var(--surface-3);
  border-radius: var(--radius-sm);
  color: var(--text-3);
}
.search input { flex: 1; background: none; border: none; padding: 8px 0; }
ul { list-style: none; margin: 8px 0 0; padding: 0; max-height: 320px; }
li button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
  padding: 7px 8px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  text-align: left;
  cursor: pointer;
}
li button:hover { background: var(--surface-hover); }
li button .mono { font-size: var(--fs-xs); }
.empty { padding: 8px; }
</style>
