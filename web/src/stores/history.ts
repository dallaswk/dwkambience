import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { SceneData } from '../types'

const LIMIT = 100

const clone = (scene: SceneData) => JSON.parse(JSON.stringify(scene)) as SceneData

/**
 * Undo/redo por instantáneas de la escena. Cada edición guarda el estado anterior antes de aplicarse
 * (una escena pesa como mucho ~512 KB y el límite es de 100 pasos).
 */
export const useHistory = defineStore('history', () => {
  const past = ref<SceneData[]>([])
  const future = ref<SceneData[]>([])

  const canUndo = computed(() => past.value.length > 0)
  const canRedo = computed(() => future.value.length > 0)

  function checkpoint(scene: SceneData) {
    past.value = [...past.value.slice(-(LIMIT - 1)), clone(scene)]
    future.value = []
  }

  function undo(current: SceneData): SceneData | null {
    const previous = past.value[past.value.length - 1]
    if (!previous) return null
    past.value = past.value.slice(0, -1)
    future.value = [...future.value, clone(current)]
    return clone(previous)
  }

  function redo(current: SceneData): SceneData | null {
    const next = future.value[future.value.length - 1]
    if (!next) return null
    future.value = future.value.slice(0, -1)
    past.value = [...past.value, clone(current)]
    return clone(next)
  }

  function reset() {
    past.value = []
    future.value = []
  }

  return { canUndo, canRedo, checkpoint, undo, redo, reset }
})
