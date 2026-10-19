<script setup lang="ts">
import { computed } from 'vue'
import { useEditor } from '../stores/editor'
import type { EntityKind, SceneEntity } from '../types'
import Icon from './Icon.vue'

const editor = useEditor()

const SECTIONS: { kind: EntityKind; label: string }[] = [
  { kind: 'ped', label: 'Actors' },
  { kind: 'vehicle', label: 'Vehicles' },
  { kind: 'prop', label: 'Props' },
  { kind: 'sound', label: 'Sound emitters' },
  { kind: 'crowd', label: 'Crowds' },
]

const sections = computed(() => {
  const entities = editor.scene?.entities ?? []
  return SECTIONS.map((s) => ({ ...s, items: entities.filter((e) => e.kind === s.kind) })).filter((s) => s.items.length)
})

function onClick(entity: SceneEntity) {
  editor.select(entity.id)
}
</script>

<template>
  <div class="outliner">
    <div class="head">
      <span class="section-title">In the scene</span>
      <span class="faint count">{{ editor.entityCount }}</span>
    </div>
    <div class="scroll tree">
      <p v-if="!sections.length" class="faint empty">
        Empty scene. Add peds, cars or props from the palettes in the top bar.
      </p>
      <div v-for="section in sections" :key="section.kind" class="section">
        <div class="section-label faint">{{ section.label }}</div>
        <button
          v-for="entity in section.items"
          :key="entity.id"
          class="item"
          :class="{ selected: entity.id === editor.selectedId }"
          @click="onClick(entity)"
          @dblclick="editor.focus(entity.id)"
        >
          <Icon :name="entity.kind" :size="14" />
          <span class="label">{{ entity.label }}</span>
          <span class="model mono faint">{{ entity.model }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.outliner { display: flex; flex-direction: column; min-height: 0; flex: 1; }
.head { display: flex; justify-content: space-between; align-items: center; padding: 14px 14px 8px; }
.count { font-size: var(--fs-xs); }
.tree { flex: 1; padding: 0 8px 8px; }
.empty { padding: 4px 6px; font-size: var(--fs-sm); line-height: 1.5; }
.section { margin-bottom: 8px; }
.section-label { font-size: var(--fs-xs); padding: 4px 6px; }
.item {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 6px 8px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  color: var(--text-2);
  text-align: left;
  cursor: pointer;
}
.item:hover { background: var(--surface-2); color: var(--text); }
.item.selected { background: var(--accent-soft); color: var(--accent); }
.label { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-size: var(--fs-sm); }
.model { font-size: var(--fs-xs); max-width: 100px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
