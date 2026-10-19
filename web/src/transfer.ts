// Formato de intercambio de escenas entre servidores: un JSON con metadatos y el documento de la escena.
// La validación de verdad la hace el servidor al importar (migración + esquema).
import type { SceneData, SceneType } from './types'

export const FORMAT = 'dwkambience-scene'
export const FORMAT_VERSION = 1

export interface ExportFile {
  format: typeof FORMAT
  version: number
  exportedAt: string
  name: string
  type: SceneType
  group: string | null
  data: SceneData
}

export function buildExport(name: string, type: SceneType, group: string | null, data: SceneData): ExportFile {
  return { format: FORMAT, version: FORMAT_VERSION, exportedAt: new Date().toISOString(), name, type, group, data }
}

/** Lee un JSON exportado. Devuelve el archivo o un código de error para la UI. */
export function parseExport(text: string): ExportFile | 'invalid_json' | 'not_a_scene' {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return 'invalid_json'
  }
  const file = parsed as Partial<ExportFile>
  if (!file || file.format !== FORMAT || (file.type !== 'cutscene' && file.type !== 'ambience') || typeof file.data !== 'object') {
    return 'not_a_scene'
  }
  return file as ExportFile
}

export function fileName(name: string) {
  return `${name.toLowerCase().replace(/[^\w-]+/g, '-').replace(/^-|-$/g, '') || 'escena'}.dwk.json`
}
