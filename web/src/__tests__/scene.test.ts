import { describe, expect, it } from 'vitest'
import {
  EVENTS, addEventKey, entityWeight, formatTime, keyTimes, newScene, nextEntityId, normalizeScene, removeEntity,
  removeItem, sceneDuration, scenePeds, sceneWeight, setTrackKeys, transformTrack, updateKey, upsertPoseKey,
  upsertVisibilityKey, visibleAt,
} from '../scene'
import type { Key, SceneData, SceneEntity } from '../types'

const ped = (id = 'ped_1'): SceneEntity => ({ id, kind: 'ped', model: 'a_m_y_hipster_01', label: 'Ped', props: {}, networked: false })

function sceneWith(...entities: SceneEntity[]): SceneData {
  const s = newScene('cutscene')
  s.entities = entities
  return s
}

describe('normalizeScene', () => {
  it('repara lo que Lua deja: arrays vacíos como objetos y nulls ausentes', () => {
    const fromLua = {
      schema: 5,
      settings: { weather: 'RAIN', time: '20:00', duration: 5000, output: { letterbox: true, hud: false }, loop: false, active: false },
      entities: [{ id: 'ped_1', kind: 'ped', model: 'm', label: 'P', props: [], networked: false }],
      tracks: [
        { id: 'tr_ped_1', target: 'ped_1', channel: 'transform', keys: {} },
        { id: 'au', target: 'music', channel: 'audio', clips: {} },
      ],
    }
    const s = normalizeScene(fromLua, 'cutscene')
    expect(s.settings.schedule).toBeNull()
    expect(s.settings.trigger).toBeNull()
    expect(s.settings.timecycle).toBeNull()
    expect(s.entities[0].props).toEqual({})
    expect(s.tracks[0].keys).toEqual([])
    expect(s.tracks[1].clips).toEqual([])
  })

  it('con datos inválidos devuelve una escena vacía del tipo pedido', () => {
    expect(normalizeScene(null, 'ambience').settings.loop).toBe(true)
  })
})

describe('ids de entidad', () => {
  it('siguen la numeración más alta de su tipo', () => {
    const s = sceneWith(ped('ped_1'), ped('ped_4'))
    expect(nextEntityId(s, 'ped').id).toBe('ped_5')
    expect(nextEntityId(s, 'vehicle').id).toBe('veh_1')
  })
})

describe('keys de pose', () => {
  it('upsert sustituye la key del mismo instante, conserva su easing y ordena', () => {
    const s = sceneWith(ped())
    upsertPoseKey(s, 'ped_1', 'transform', { t: 2000, pos: [1, 0, 0], rot: [0, 0, 0] })
    upsertPoseKey(s, 'ped_1', 'transform', { t: 0, pos: [0, 0, 0], rot: [0, 0, 0], ease: 'inOut' })
    upsertPoseKey(s, 'ped_1', 'transform', { t: 0, pos: [5, 5, 5], rot: [0, 0, 0] })
    const keys = transformTrack(s, 'ped_1')!.keys as Key[]
    expect(keys.map((k) => k.t)).toEqual([0, 2000])
    expect(keys[0].pos).toEqual([5, 5, 5])
    expect(keys[0].ease).toBe('inOut')
  })

  it('no sustituye objetos en sitio (los computed de Vue comparan por referencia)', () => {
    const s = sceneWith(ped())
    upsertPoseKey(s, 'ped_1', 'transform', { t: 0, pos: [0, 0, 0], rot: [0, 0, 0] })
    const before = s.tracks
    const track = s.tracks[0]
    upsertPoseKey(s, 'ped_1', 'transform', { t: 1000, pos: [1, 0, 0], rot: [0, 0, 0] })
    expect(s.tracks).not.toBe(before)
    expect(s.tracks[0]).not.toBe(track)
  })

  it('mover una key encima de otra se rechaza; si no, devuelve su nuevo índice', () => {
    const s = sceneWith(ped())
    setTrackKeys(s, 'ped_1', 'transform', [
      { t: 0, pos: [0, 0, 0], rot: [0, 0, 0] },
      { t: 1000, pos: [1, 0, 0], rot: [0, 0, 0] },
    ])
    const id = transformTrack(s, 'ped_1')!.id
    expect(updateKey(s, id, 1, { t: 0 })).toBe(-1)
    expect(updateKey(s, id, 0, { t: 3000 })).toBe(1)
  })

  it('los eventos sí pueden coincidir en el tiempo', () => {
    const s = sceneWith()
    addEventKey(s, { t: 0, type: 'trigger', name: 'a' })
    addEventKey(s, { t: 0, type: 'trigger', name: 'b' })
    expect(s.tracks.find((tr) => tr.target === EVENTS)!.keys).toHaveLength(2)
  })

  it('borrar la última key elimina la pista', () => {
    const s = sceneWith(ped())
    upsertPoseKey(s, 'ped_1', 'transform', { t: 0, pos: [0, 0, 0], rot: [0, 0, 0] })
    removeItem(s, transformTrack(s, 'ped_1')!.id, 0)
    expect(s.tracks).toHaveLength(0)
  })

  it('borrar una entidad borra sus pistas', () => {
    const s = sceneWith(ped(), ped('ped_2'))
    upsertPoseKey(s, 'ped_1', 'transform', { t: 0, pos: [0, 0, 0], rot: [0, 0, 0] })
    upsertPoseKey(s, 'ped_2', 'transform', { t: 0, pos: [0, 0, 0], rot: [0, 0, 0] })
    removeEntity(s, 'ped_1')
    expect(s.entities.map((e) => e.id)).toEqual(['ped_2'])
    expect(s.tracks.map((tr) => tr.target)).toEqual(['ped_2'])
  })
})

describe('visibilidad (igual que Evaluate.visible en Lua)', () => {
  it('sin keys es visible; manda la más reciente; antes de la primera vale la primera', () => {
    const s = sceneWith(ped())
    expect(visibleAt(s, 'ped_1', 500)).toBe(true)
    upsertVisibilityKey(s, 'ped_1', 0, true)
    upsertVisibilityKey(s, 'ped_1', 3000, false)
    expect(visibleAt(s, 'ped_1', 2999)).toBe(true)
    expect(visibleAt(s, 'ped_1', 3000)).toBe(false)
    expect(visibleAt(s, 'ped_1', 9000)).toBe(false)
  })
})

describe('pesos y duración', () => {
  it('una multitud cuenta tantas entidades como personas; sonidos y efectos no cuentan', () => {
    const crowd: SceneEntity = { id: 'crowd_1', kind: 'crowd', label: 'C', props: {}, networked: false,
      crowd: { preset: 'beach', count: 12, seed: 1, points: [[0, 0, 0]], spread: 2, facing: 'random' } }
    const sound: SceneEntity = { id: 'snd_1', kind: 'sound', label: 'S', props: {}, networked: false,
      sound: { asset: 'a', volume: 1, range: 10, loop: true } }
    const s = sceneWith(ped(), crowd, sound)
    expect(entityWeight(crowd)).toBe(12)
    expect(entityWeight(sound)).toBe(0)
    expect(sceneWeight(s)).toBe(13)
    expect(scenePeds(s)).toBe(13)
  })

  it('la duración es la mayor entre settings y la última key', () => {
    const s = sceneWith(ped())
    s.settings.duration = 5000
    upsertPoseKey(s, 'ped_1', 'transform', { t: 8000, pos: [0, 0, 0], rot: [0, 0, 0] })
    expect(sceneDuration(s)).toBe(8000)
    expect(keyTimes(s)).toEqual([8000])
  })

  it('formatTime usa m:ss.d', () => {
    expect(formatTime(0)).toBe('0:00.0')
    expect(formatTime(65432)).toBe('1:05.4')
  })
})
