import { describe, expect, it } from 'vitest'
import * as i18n from '../i18n'

describe('textos', () => {
  it('sustituye parámetros', () => {
    i18n.setLocale('es')
    expect(i18n.t('loaded', { name: 'Intro' })).toBe('Cargada Intro')
  })

  it('cada clave tiene texto en los dos idiomas', () => {
    // t() cae al inglés si falta una clave en español: se compara contra el diccionario inglés
    i18n.chooseLocale('en')
    const keys = ['save', 'historyRestore', 'networkLimit', 'screenHint', 'preset_beach'] as const
    const english = keys.map((k) => i18n.t(k))
    i18n.chooseLocale('es')
    keys.forEach((k, i) => expect(i18n.t(k)).not.toBe(english[i]))
  })

  it('tOr devuelve el texto de reserva para claves que no existen', () => {
    expect(i18n.tOr('preset_inventado', 'inventado')).toBe('inventado')
    expect(i18n.tOr('preset_beach', 'x')).toBe('Playa')
  })
})
