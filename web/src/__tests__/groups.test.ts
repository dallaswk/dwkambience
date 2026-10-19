import { describe, expect, it } from 'vitest'
import { groupSpan, newScene, nextGroupId, normalizeScene, removeEntity, shiftGroup, transformTrack, upsertPoseKey } from '../scene'
import type { Key, SceneData, SceneEntity } from '../types'

const ped = (id: string): SceneEntity => ({ id, kind: 'ped', model: 'm', label: id, props: {}, networked: false })

function scene(): SceneData {
  const s = newScene('cutscene')
  s.entities = [ped('ped_1'), ped('ped_2'), ped('ped_3')]
  upsertPoseKey(s, 'ped_1', 'transform', { t: 1000, pos: [0, 0, 0], rot: [0, 0, 0] })
  upsertPoseKey(s, 'ped_1', 'transform', { t: 4000, pos: [1, 0, 0], rot: [0, 0, 0] })
  upsertPoseKey(s, 'ped_2', 'transform', { t: 2000, pos: [0, 0, 0], rot: [0, 0, 0] })
  upsertPoseKey(s, 'ped_3', 'transform', { t: 500, pos: [0, 0, 0], rot: [0, 0, 0] })
  s.groups = [{ id: 'grp_1', label: 'Pareja', members: ['ped_1', 'ped_2'] }]
  return s
}

describe('grupos (set pieces como bloque)', () => {
  it('el bloque abarca de la primera a la última key de sus miembros', () => {
    const s = scene()
    expect(groupSpan(s, s.groups[0])).toEqual({ start: 1000, end: 4000 })
  })

  it('moverlo desplaza solo las pistas de sus miembros', () => {
    const s = scene()
    expect(shiftGroup(s, 'grp_1', 1500)).toBe(1500)
    expect((transformTrack(s, 'ped_1')!.keys as Key[]).map((k) => k.t)).toEqual([2500, 5500])
    expect((transformTrack(s, 'ped_2')!.keys as Key[])[0].t).toBe(3500)
    expect((transformTrack(s, 'ped_3')!.keys as Key[])[0].t).toBe(500)
  })

  it('no se puede llevar antes de t = 0', () => {
    const s = scene()
    expect(shiftGroup(s, 'grp_1', -5000)).toBe(-1000)
    expect(groupSpan(s, s.groups[0])!.start).toBe(0)
  })

  it('borrar un miembro lo saca del grupo y un grupo vacío desaparece', () => {
    const s = scene()
    removeEntity(s, 'ped_1')
    expect(s.groups[0].members).toEqual(['ped_2'])
    removeEntity(s, 'ped_2')
    expect(s.groups).toHaveLength(0)
  })

  it('ids nuevos y normalización desde Lua', () => {
    const s = scene()
    expect(nextGroupId(s)).toBe('grp_2')
    const fromLua = normalizeScene({ ...JSON.parse(JSON.stringify(s)), groups: {} }, 'cutscene')
    expect(fromLua.groups).toEqual([])
  })
})
