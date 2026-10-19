<script setup lang="ts">
import { computed, ref } from 'vue'
import { t } from '../i18n'
import { useConfirm } from '../stores/confirm'
import { useEditor } from '../stores/editor'
import type { SceneRow, SceneType } from '../types'
import Icon from './Icon.vue'

const editor = useEditor()
const confirm = useConfirm()

const name = ref('')
const type = ref<SceneType>('cutscene')
const group = ref('')
const creating = ref(false)

const search = ref('')
const filter = ref<'all' | SceneType>('all')

const groups = computed(() => [...new Set(editor.rows.map((r) => r.group).filter(Boolean))] as string[])

const grouped = computed(() => {
  const q = search.value.trim().toLowerCase()
  const map = new Map<string, SceneRow[]>()
  for (const row of editor.rows) {
    if (filter.value !== 'all' && row.type !== filter.value) continue
    if (q && !row.name.toLowerCase().includes(q) && !(row.group ?? '').toLowerCase().includes(q)) continue
    const key = row.group ?? ''
    if (!map.has(key)) map.set(key, [])
    map.get(key)!.push(row)
  }
  return [...map.entries()].sort(([a], [b]) => (a === '' ? 1 : b === '' ? -1 : a.localeCompare(b)))
})

async function create() {
  if (!name.value.trim() || creating.value) return
  creating.value = true
  await editor.createScene(name.value.trim(), type.value, group.value.trim())
  creating.value = false
  name.value = ''
}

async function remove(row: SceneRow) {
  const ok = await confirm.ask({
    title: t('deleteSceneTitle', { name: row.name }),
    body: t('deleteSceneBody'),
    confirm: t('deleteSceneConfirm'),
    danger: true,
  })
  if (ok) editor.deleteScene(row.id)
}
</script>

<template>
  <div class="manager">
    <section class="create">
      <div class="section-title">{{ t('newScene') }}</div>
      <div class="types">
        <button class="type" :class="{ on: type === 'cutscene' }" @click="type = 'cutscene'">
          <Icon name="film" /> {{ t('cutscene') }}
        </button>
        <button class="type" :class="{ on: type === 'ambience' }" @click="type = 'ambience'">
          <Icon name="waves" /> {{ t('ambience') }}
        </button>
      </div>
      <input v-model="name" maxlength="64" :placeholder="t('sceneName')" @keydown.enter="create" />
      <input v-model="group" maxlength="64" :placeholder="t('groupOptional')" list="scene-groups" @keydown.enter="create" />
      <datalist id="scene-groups">
        <option v-for="g in groups" :key="g" :value="g" />
      </datalist>
      <button class="btn primary" :disabled="!name.trim() || creating" @click="create">
        <Icon name="plus" :size="14" /> {{ t(type === 'cutscene' ? 'createCutscene' : 'createAmbience') }}
      </button>
    </section>

    <section class="list">
      <div class="list-head">
        <button class="btn ghost import" @click="editor.openImport()">{{ t('importScene') }}</button>
        <label class="search">
          <Icon name="search" :size="14" />
          <input v-model="search" :placeholder="t('searchScenes')" />
        </label>
        <div class="filters">
          <button v-for="f in (['all', 'cutscene', 'ambience'] as const)" :key="f" :class="{ on: filter === f }" @click="filter = f">
            {{ t(f === 'all' ? 'filterAll' : f === 'cutscene' ? 'filterCutscenes' : 'filterAmbiences') }}
          </button>
        </div>
      </div>

      <div class="scroll groups">
        <p v-if="editor.loadingList && !editor.rows.length" class="faint empty">{{ t('loading') }}</p>
        <p v-else-if="!grouped.length" class="faint empty">
          {{ editor.rows.length ? t('noScenesMatch') : t('noScenesYet') }}
        </p>
        <div v-for="[groupName, items] in grouped" :key="groupName" class="group">
          <div class="group-title">
            <Icon name="folder" :size="14" />
            {{ groupName || t('ungrouped') }}
            <span class="faint">{{ items.length }}</span>
          </div>
          <div v-for="row in items" :key="row.id" class="row" @click="editor.openScene(row.id)">
            <Icon :name="row.type === 'cutscene' ? 'film' : 'waves'" class="muted" />
            <div class="row-main">
              <div class="row-name">{{ row.name }}</div>
              <div class="row-meta faint">
                {{ t(row.entityCount === 1 ? 'actorCount' : 'actorsCount', { n: row.entityCount }) }} · {{ t('keysCount', { n: row.keyCount }) }}
                <template v-if="row.lockedBy"> · <Icon name="lock" :size="11" /> {{ row.lockedBy }}</template>
              </div>
            </div>
            <button
              v-if="row.type === 'ambience'"
              class="pill"
              :class="{ on: row.active }"
              :title="t('ambienceActive')"
              @click.stop="editor.setActive(row.id, !row.active)"
            >{{ row.active ? t('on') : t('off') }}</button>
            <button class="btn icon ghost del" :title="t('exportScene')" @click.stop="editor.exportScene(row.id)">
              <Icon name="save" :size="14" />
            </button>
            <button class="btn icon ghost danger del" :title="t('delete')" @click.stop="remove(row)">
              <Icon name="trash" :size="14" />
            </button>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
.manager { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.create { display: flex; flex-direction: column; gap: 8px; padding: 14px; background: var(--surface-2); }
.types { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
.type {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 34px;
  border: none;
  border-radius: var(--radius-sm);
  background: var(--surface-3);
  color: var(--text-2);
  font-weight: 600;
  font-size: var(--fs-sm);
  cursor: pointer;
}
.type.on { background: var(--accent-soft); color: var(--accent); }

.list { display: flex; flex-direction: column; flex: 1; min-height: 0; }
.list-head { padding: 12px 14px 8px; display: flex; flex-direction: column; gap: 8px; }
.search {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 8px;
  background: var(--surface-3);
  border-radius: var(--radius-sm);
  color: var(--text-3);
}
.search input { flex: 1; background: none; border: none; padding: 7px 0; }
.filters { display: flex; gap: 4px; }
.import { align-self: flex-start; padding: 0 8px; }
.filters button {
  border: none;
  background: none;
  color: var(--text-3);
  font-size: var(--fs-xs);
  font-weight: 600;
  padding: 4px 8px;
  border-radius: var(--radius-sm);
  cursor: pointer;
}
.filters button.on { background: var(--surface-3); color: var(--text); }

.groups { flex: 1; padding: 0 8px 12px; }
.empty { padding: 12px 6px; font-size: var(--fs-sm); }
.group { margin-top: 6px; }
.group-title {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px;
  font-size: var(--fs-xs);
  font-weight: 600;
  color: var(--text-2);
}
.row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 6px 8px 10px;
  border-radius: var(--radius-sm);
  cursor: pointer;
}
.row:hover { background: var(--surface-2); }
.row-main { flex: 1; min-width: 0; }
.row-name { font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.row-meta { font-size: var(--fs-xs); display: flex; align-items: center; gap: 3px; }
.pill {
  border: none;
  border-radius: 10px;
  padding: 2px 8px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.04em;
  background: var(--surface-3);
  color: var(--text-3);
  cursor: pointer;
}
.pill.on { background: var(--accent-soft); color: var(--accent); }
.del { opacity: 0; }
.row:hover .del { opacity: 1; }
</style>
