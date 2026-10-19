import { describe, expect, it } from 'vitest'
import { newScene } from '../scene'
import { FORMAT, buildExport, fileName, parseExport } from '../transfer'

describe('exportar / importar', () => {
  it('lo exportado se vuelve a leer igual', () => {
    const data = newScene('ambience')
    const file = buildExport('Playa', 'ambience', 'Eventos', data)
    const parsed = parseExport(JSON.stringify(file))
    expect(parsed).toMatchObject({ format: FORMAT, name: 'Playa', type: 'ambience', group: 'Eventos' })
    expect(typeof parsed === 'object' && parsed.data).toEqual(data)
  })

  it('distingue JSON roto de JSON que no es una escena', () => {
    expect(parseExport('{nope')).toBe('invalid_json')
    expect(parseExport('{"format":"otra-cosa"}')).toBe('not_a_scene')
    expect(parseExport(JSON.stringify({ format: FORMAT, type: 'video', data: {} }))).toBe('not_a_scene')
  })

  it('el nombre de archivo es seguro', () => {
    expect(fileName('Bienvenida / Intro!')).toBe('bienvenida-intro.dwk.json')
    expect(fileName('***')).toBe('escena.dwk.json')
  })
})
