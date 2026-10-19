<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { t } from '../i18n'
import type { MessageKey } from '../i18n'
import { useEditor } from '../stores/editor'
import type { EntityKind } from '../types'
import Icon from './Icon.vue'
import PaletteMenu from './PaletteMenu.vue'

const editor = useEditor()
const emit = defineEmits<{ closeScene: []; exit: [] }>()

const menu = ref<string | null>(null)

const PALETTES: { kind: EntityKind; label: MessageKey }[] = [
  { kind: 'ped', label: 'palettePed' },
  { kind: 'vehicle', label: 'paletteVehicle' },
  { kind: 'prop', label: 'paletteProp' },
]

const savedLabel = computed(() => {
  if (editor.saving) return t('saving')
  if (editor.readOnly) return t('readOnly')
  if (editor.dirty) return t('unsaved')
  if (!editor.savedAt) return ''
  const d = new Date(editor.savedAt)
  return t('savedAt', { time: `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` })
})

const nearLimit = computed(() => !!editor.studio && editor.entityCount >= editor.studio.maxEntities * 0.9)

function toggle(name: string) {
  menu.value = menu.value === name ? null : name
}

function run(action: () => void) {
  menu.value = null
  action()
}

function onDocClick(e: MouseEvent) {
  if (!(e.target as HTMLElement).closest('.menu-root')) menu.value = null
}
onMounted(() => document.addEventListener('mousedown', onDocClick))
onBeforeUnmount(() => document.removeEventListener('mousedown', onDocClick))
</script>

<template>
  <header class="topbar">
    <div class="left">
      <span class="brand">dwkambience</span>

      <div class="menu-root">
        <button class="btn ghost" :class="{ active: menu === 'file' }" @click="toggle('file')">{{ t('file') }}</button>
        <div v-if="menu === 'file'" class="dropdown">
          <button :disabled="!editor.scene" @click="run(() => emit('closeScene'))">{{ t('newOpenScene') }}</button>
          <button :disabled="!editor.canEdit || !editor.dirty" @click="run(editor.save)">
            {{ t('save') }} <span class="faint">Ctrl+S</span>
          </button>
          <button :disabled="!editor.scene" @click="run(() => emit('closeScene'))">{{ t('closeScene') }}</button>
          <div class="sep" />
          <button @click="run(() => emit('exit'))">{{ t('exitEditor') }}</button>
        </div>
      </div>

      <div class="menu-root">
        <button class="btn ghost" :class="{ active: menu === 'view' }" @click="toggle('view')">{{ t('view') }}</button>
        <div v-if="menu === 'view'" class="dropdown">
          <button @click="run(editor.toggleLabels)">
            <span>{{ t('entityLabels') }}</span>
            <span class="check" :class="{ on: editor.showLabels }" />
          </button>
        </div>
      </div>

      <div class="divider" />

      <div v-for="p in PALETTES" :key="p.kind" class="menu-root">
        <button
          class="btn ghost"
          :class="{ active: menu === p.kind }"
          :disabled="!editor.canEdit"
          @click="toggle(p.kind)"
        >
          <Icon :name="p.kind" :size="15" />
          {{ t(p.label) }}
        </button>
        <PaletteMenu
          :kind="p.kind"
          :open="menu === p.kind"
          @spawn="(model) => editor.spawn(p.kind, model)"
          @close="menu = null"
        />
      </div>
    </div>

    <div v-if="editor.meta" class="center">
      <span class="faint">{{ editor.meta.group || t('ungrouped') }}</span>
      <span class="faint">/</span>
      <span class="name">{{ editor.meta.name }}</span>
      <Icon v-if="editor.readOnly" name="lock" :size="13" class="faint" />
      <span class="saved" :class="{ dirty: editor.dirty && !editor.readOnly }">{{ savedLabel }}</span>
    </div>

    <div class="right">
      <span v-if="editor.studio" class="counter mono" :class="{ warn: nearLimit }">
        {{ editor.studio.label }} // {{ editor.entityCount }}/{{ editor.studio.maxEntities }}
      </span>
      <button v-if="editor.scene" class="btn primary" :disabled="!editor.canEdit || !editor.dirty || editor.saving" @click="editor.save">
        <Icon name="save" :size="14" /> {{ t('save') }}
      </button>
      <button class="btn icon ghost" :title="t('exitEditor')" @click="emit('exit')">
        <Icon name="exit" />
      </button>
    </div>
  </header>
</template>

<style scoped>
.topbar {
  grid-area: top;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 0 8px 0 14px;
  background: var(--surface-1);
}
.left, .right, .center { display: flex; align-items: center; gap: 4px; }
.center { gap: 6px; min-width: 0; font-size: var(--fs-sm); }
.right { gap: 10px; }
.brand { font-weight: 700; letter-spacing: 0.02em; margin-right: 10px; }
.divider { width: 1px; height: 20px; background: var(--line); margin: 0 6px; }
.name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 260px; }
.saved { color: var(--text-3); margin-left: 6px; }
.saved.dirty { color: var(--warning); }
.counter { font-size: var(--fs-xs); color: var(--text-2); }
.counter.warn { color: var(--warning); }

.menu-root { position: relative; }
.dropdown {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  min-width: 210px;
  padding: 6px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  z-index: 20;
}
.dropdown button {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  padding: 7px 10px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  text-align: left;
  font-size: var(--fs-sm);
  cursor: pointer;
}
.dropdown button:hover:not(:disabled) { background: var(--surface-hover); }
.dropdown button:disabled { color: var(--text-3); cursor: default; }
.sep { height: 1px; background: var(--line); margin: 6px 4px; }
.check { width: 8px; height: 8px; border-radius: 50%; background: var(--surface-3); }
.check.on { background: var(--accent); }
</style>
