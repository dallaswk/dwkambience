import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { newScene } from '../scene'
import { useHistory } from '../stores/history'

describe('deshacer / rehacer', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('vuelve atrás y adelante con copias independientes', () => {
    const history = useHistory()
    const v1 = newScene('cutscene')
    history.checkpoint(v1)
    const v2 = { ...v1, settings: { ...v1.settings, time: '20:00' } }

    const undone = history.undo(v2)!
    expect(undone.settings.time).toBe('12:00')
    expect(undone).not.toBe(v1)
    expect(history.canRedo).toBe(true)

    const redone = history.redo(undone)!
    expect(redone.settings.time).toBe('20:00')
  })

  it('una edición nueva borra el rehacer y el límite es de 100 pasos', () => {
    const history = useHistory()
    const s = newScene('cutscene')
    for (let i = 0; i < 120; i++) history.checkpoint(s)
    let steps = 0
    let current = s
    while (history.canUndo) {
      current = history.undo(current)!
      steps++
    }
    expect(steps).toBe(100)
    history.checkpoint(current)
    expect(history.canRedo).toBe(false)
  })
})
