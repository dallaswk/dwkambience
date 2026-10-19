<script setup lang="ts">
import { useToasts } from '../stores/toasts'

const toasts = useToasts()
</script>

<template>
  <div class="toasts">
    <TransitionGroup name="toast">
      <div v-for="t in toasts.items" :key="t.id" class="toast" :class="t.kind" @click="toasts.dismiss(t.id)">
        <span class="dot" />
        {{ t.text }}
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
.toasts {
  position: fixed;
  top: calc(var(--topbar-h) + 12px);
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  z-index: 50;
}
.toast {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  background: var(--surface-2);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
  font-size: var(--fs-sm);
  cursor: pointer;
}
.dot { width: 6px; height: 6px; border-radius: 50%; background: var(--text-3); }
.success .dot { background: var(--accent); }
.warning .dot { background: var(--warning); }
.error .dot { background: var(--danger); }
.toast-enter-active, .toast-leave-active { transition: opacity 0.18s, transform 0.18s; }
.toast-enter-from, .toast-leave-to { opacity: 0; transform: translateY(-6px); }
</style>
