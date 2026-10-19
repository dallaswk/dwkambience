import type { MessageKey } from '../../i18n'
import { CAMERA, EVENTS, MUSIC, findTrack } from '../../scene'
import type { Channel, SceneData, SceneType } from '../../types'

export interface Row {
  id: string
  target: string
  channel: Channel
  icon: string
  /** Nombre propio (etiqueta de entidad) o clave de traducción */
  label: string | null
  labelKey: MessageKey | null
  subKey: MessageKey | null
  entityId: string | null
  /** Fila de un bloque de set piece (no es una pista) */
  groupId?: string
}

export const ROW_H = 26
export const RULER_H = 24
export const HEADER_W = 200

/** Filas del timeline: cámara (solo cutscene), eventos, música y, por entidad, transform y anim (peds). */
export function buildRows(scene: SceneData | null, type: SceneType | undefined): Row[] {
  if (!scene) return []
  const rows: Row[] = []
  if (type === 'cutscene') {
    rows.push({ id: CAMERA, target: CAMERA, channel: 'camera', icon: 'camera', label: null, labelKey: 'rowCamera', subKey: null, entityId: null })
  }
  rows.push({ id: EVENTS, target: EVENTS, channel: 'event', icon: 'flag', label: null, labelKey: 'rowEvents', subKey: null, entityId: null })
  rows.push({ id: MUSIC, target: MUSIC, channel: 'audio', icon: 'music', label: null, labelKey: 'rowMusic', subKey: null, entityId: null })
  for (const g of scene.groups ?? []) {
    rows.push({ id: `group:${g.id}`, target: g.id, channel: 'event', icon: 'setpiece', label: g.label, labelKey: null, subKey: 'rowSetPiece', entityId: null, groupId: g.id })
  }

  for (const e of scene.entities) {
    if (e.kind === 'crowd') {
      if (findTrack(scene, e.id, 'visibility')) {
        rows.push({ id: `${e.id}:visibility`, target: e.id, channel: 'visibility', icon: 'eye', label: e.label, labelKey: null, subKey: 'rowVisibility', entityId: e.id })
      }
      continue
    }
    rows.push({ id: `${e.id}:transform`, target: e.id, channel: 'transform', icon: e.kind, label: e.label, labelKey: null, subKey: 'rowTransform', entityId: e.id })
    if (e.kind === 'ped') {
      rows.push({ id: `${e.id}:anim`, target: e.id, channel: 'anim', icon: 'ped', label: e.label, labelKey: null, subKey: 'rowAnim', entityId: e.id })
    }
    if (findTrack(scene, e.id, 'visibility')) {
      rows.push({ id: `${e.id}:visibility`, target: e.id, channel: 'visibility', icon: 'eye', label: e.label, labelKey: null, subKey: 'rowVisibility', entityId: e.id })
    }
  }
  return rows
}
