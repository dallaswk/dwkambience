import type { AudioClip } from './types'

export interface SoundAsset {
  id: string
  file: string
}

let manifest: Promise<SoundAsset[]> | null = null

/** Sonidos disponibles (web/public/sounds/manifest.json, generado en el build). */
export function loadSounds(): Promise<SoundAsset[]> {
  manifest ??= fetch('sounds/manifest.json')
    .then((r) => (r.ok ? (r.json() as Promise<SoundAsset[]>) : []))
    .catch(() => [])
  return manifest
}

const DRIFT_S = 0.15

/**
 * Reproduce los clips de audio de una pista en sincronía con t. Se llama en cada frame:
 * arranca, corrige la posición si se desvía más de 150 ms, aplica fade in y para lo que ya no toca.
 */
export class AudioPlayer {
  private elements = new Map<string, HTMLAudioElement>()
  private files = new Map<string, string>()

  async init() {
    for (const s of await loadSounds()) this.files.set(s.id, s.file)
  }

  update(clips: AudioClip[], t: number, playing: boolean, sceneEnd: number) {
    const live = new Set<string>()

    if (playing) {
      for (const clip of clips) {
        const end = clip.duration ? clip.start + clip.duration : clip.loop ? sceneEnd : Infinity
        if (t < clip.start || t >= end) continue

        const key = `${clip.asset}@${clip.start}`
        let el = this.elements.get(key)
        if (!el) {
          const file = this.files.get(clip.asset)
          if (!file) continue
          el = new Audio(`sounds/${file}`)
          el.preload = 'auto'
          this.elements.set(key, el)
        }
        el.loop = clip.loop

        const local = (t - clip.start) / 1000
        if (!clip.loop && el.duration && local >= el.duration) continue
        const target = clip.loop && el.duration ? local % el.duration : local

        live.add(key)
        if (Math.abs(el.currentTime - target) > DRIFT_S) el.currentTime = target
        const fade = clip.fadeIn > 0 ? Math.min(1, (t - clip.start) / clip.fadeIn) : 1
        el.volume = Math.max(0, Math.min(1, clip.volume * fade))
        if (el.paused) el.play().catch(() => {})
      }
    }

    for (const [key, el] of this.elements) {
      if (!live.has(key) && !el.paused) el.pause()
    }
  }

  stop() {
    for (const el of this.elements.values()) el.pause()
    this.elements.clear()
  }
}
