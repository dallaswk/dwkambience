<script setup lang="ts">
import { t } from '../i18n'
import { useConfirm } from '../stores/confirm'

const confirm = useConfirm()
</script>

<template>
  <div v-if="confirm.request" class="scrim confirm" @mousedown.self="confirm.answer(false)">
    <div class="dialog" role="dialog" @keydown.esc="confirm.answer(false)">
      <h2>{{ confirm.request.title }}</h2>
      <p class="muted">{{ confirm.request.body }}</p>
      <input
        v-if="confirm.request.placeholder !== undefined"
        v-model="confirm.text"
        class="text-input"
        maxlength="64"
        :placeholder="confirm.request.placeholder"
        autofocus
        @keydown.enter="confirm.answer(true)"
      />
      <div class="actions">
        <button class="btn ghost" @click="confirm.answer(false)">{{ t('cancel') }}</button>
        <button class="btn" :class="confirm.request.danger ? 'danger solid' : 'primary'" @click="confirm.answer(true)">
          {{ confirm.request.confirm }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Por encima de cualquier otro diálogo: confirma acciones lanzadas desde ellos */
.scrim { position: fixed; inset: 0; background: var(--scrim); display: grid; place-items: center; z-index: 70; }
.dialog { width: 380px; padding: 20px; background: var(--surface-2); border-radius: var(--radius); box-shadow: var(--shadow); }
h2 { margin: 0 0 8px; font-size: var(--fs-lg); font-weight: 600; }
p { margin: 0 0 18px; font-size: var(--fs-sm); line-height: 1.5; }
.actions { display: flex; justify-content: flex-end; gap: 8px; }
.text-input { width: 100%; margin-bottom: 16px; }
.btn.danger.solid { background: var(--danger); color: var(--on-accent); }
</style>
