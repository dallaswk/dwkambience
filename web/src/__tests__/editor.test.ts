// Recorrido del editor contra los mocks de la NUI (los mismos que usa `npm run dev`)
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { normalizeScene } from '../scene'
import { useEditor } from '../stores/editor'
import { useTimeline } from '../stores/timeline'

describe('editor (con mocks)', () => {
  beforeEach(() => {
    localStorage.clear()
    setActivePinia(createPinia())
  })

  it('crear, añadir, deshacer, guardar y reabrir deja la escena igual', async () => {
    const editor = useEditor()
    editor.show({ studios: { 1: { label: 'Studio 1', maxEntities: 300 } }, locale: 'es' })
    await editor.createScene('Prueba', 'cutscene', 'Tests')
    expect(editor.meta?.name).toBe('Prueba')

    await editor.spawn('ped', 'a_m_y_hipster_01')
    await editor.spawn('vehicle', 'elegy')
    expect(editor.scene!.entities).toHaveLength(2)

    editor.undo()
    expect(editor.scene!.entities).toHaveLength(1)
    editor.redo()
    expect(editor.scene!.entities).toHaveLength(2)

    // Auto key: mover en otro instante crea una segunda key
    useTimeline().setTime(3000)
    editor.setPose('veh_1', [10, 20, 30], [0, 0, 90], true)
    const keys = editor.scene!.tracks.find((tr) => tr.target === 'veh_1')!.keys!
    expect(keys.map((k) => k.t)).toEqual([0, 3000])

    await editor.save()
    expect(editor.dirty).toBe(false)
    const saved = JSON.parse(JSON.stringify(editor.scene))
    const id = editor.meta!.id

    await editor.closeScene()
    expect(editor.scene).toBeNull()
    await editor.openScene(id)
    // Mismo resultado tras el viaje por "Lua" (nulls perdidos, arrays vacíos como objetos)
    expect(editor.scene).toEqual(normalizeScene(saved, 'cutscene'))
  })

  it('no deja pasar del límite de entidades del estudio', async () => {
    const editor = useEditor()
    editor.show({ studios: { 1: { label: 'Studio 1', maxEntities: 1 } }, locale: 'es' })
    await editor.createScene('Límite', 'cutscene', '')
    await editor.spawn('ped', 'a_m_y_hipster_01')
    await editor.spawn('ped', 'a_m_y_hipster_01')
    expect(editor.scene!.entities).toHaveLength(1)
  })
})
