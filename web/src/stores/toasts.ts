import { defineStore } from 'pinia'
import { ref } from 'vue'

export type ToastKind = 'info' | 'success' | 'warning' | 'error'

export interface Toast {
  id: number
  text: string
  kind: ToastKind
}

export const useToasts = defineStore('toasts', () => {
  const items = ref<Toast[]>([])
  let seq = 0

  function push(text: string, kind: ToastKind = 'info', ms = 3500) {
    const id = ++seq
    items.value.push({ id, text, kind })
    setTimeout(() => dismiss(id), ms)
  }

  function dismiss(id: number) {
    items.value = items.value.filter((t) => t.id !== id)
  }

  return { items, push, dismiss }
})
