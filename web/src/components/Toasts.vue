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
/* Abajo a la derecha del viewport: arriba taparían los menús desplegables */
.toasts {
  position: fixed;
  bottom: calc(var(--timeline-h) + 16px);
  right: calc(var(--right-w) + 16px);
  display: flex;
  flex-direction: column-reverse;
  align-items: flex-end;
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
.toast-enter-from, .toast-leave-to { opacity: 0; transform: translateY(6px); }
</style>
