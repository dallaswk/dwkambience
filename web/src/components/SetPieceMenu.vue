<script setup lang="ts">
import { watch } from 'vue'
import { t } from '../i18n'
import { useEditor } from '../stores/editor'
import Icon from './Icon.vue'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: [] }>()
const editor = useEditor()

watch(
  () => props.open,
  (open) => {
    if (open) editor.loadSetPieces()
  },
)

function insert(id: number) {
  emit('close')
  editor.insertSetPiece(id)
}

function save() {
  emit('close')
  editor.saveSetPiece()
}
</script>

<template>
  <div v-if="open" class="palette">
    <ul class="scroll">
      <li v-for="item in editor.setPieces" :key="item.id">
        <button class="item" @click="insert(item.id)">
          <Icon name="setpiece" :size="14" />
          <span>{{ item.name }}</span>
        </button>
        <button class="btn icon ghost danger" :title="t('delete')" @click.stop="editor.deleteSetPiece(item.id, item.name)">
          <Icon name="trash" :size="13" />
        </button>
      </li>
      <li v-if="!editor.setPieces.length" class="empty faint">{{ t('noSetPieces') }}</li>
    </ul>
    <div class="footer">
      <button class="btn primary" :disabled="!editor.selectionIds.length" @click="save">
        <Icon name="save" :size="14" /> {{ t('saveSetPieceCount', { n: editor.selectionIds.length }) }}
      </button>
      <p class="faint hint">{{ t('multiSelectHint') }}</p>
    </div>
  </div>
</template>

<style scoped>
.palette {
  position: absolute;
  top: calc(100% + 6px);
  right: 0;
  width: 300px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  padding: 8px;
  z-index: 20;
}
ul { list-style: none; margin: 0; padding: 0; max-height: 280px; }
li { display: flex; align-items: center; gap: 4px; }
.item {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 8px;
  border: none;
  background: none;
  border-radius: var(--radius-sm);
  text-align: left;
  cursor: pointer;
}
.item:hover { background: var(--surface-hover); }
.empty { padding: 8px; font-size: var(--fs-sm); line-height: 1.5; }
.footer { margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--line); display: flex; flex-direction: column; gap: 6px; }
.hint { margin: 0; font-size: var(--fs-xs); }
.btn.icon { width: 26px; height: 26px; }
</style>
