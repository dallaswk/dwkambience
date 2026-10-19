// Música de una cutscene en reproducción (fuera del editor). El cliente manda t al empezar y
// cada segundo; entre medias la NUI lleva su propio reloj y se corrige si se desvía más de 120 ms.
import { AudioPlayer } from './audio'
import type { AudioClip } from './types'

const MAX_DRIFT = 120

let player: AudioPlayer | null = null
let clips: AudioClip[] = []
let base = 0
let raf = 0

function frame() {
  raf = requestAnimationFrame(frame)
  const t = performance.now() - base
  player?.update(clips, t, t >= 0, Infinity)
}

function stop() {
  cancelAnimationFrame(raf)
  player?.stop()
  player = null
  clips = []
}

export function handlePlayback(data: { state: 'start' | 'sync' | 'stop'; t?: number; clips?: unknown }) {
  if (data.state === 'start') {
    stop()
    clips = Array.isArray(data.clips) ? (data.clips as AudioClip[]) : []
    base = performance.now() - (data.t ?? 0)
    player = new AudioPlayer()
    player.init().then(() => {
      raf = requestAnimationFrame(frame)
    })
  } else if (data.state === 'sync' && player && typeof data.t === 'number') {
    if (Math.abs(performance.now() - base - data.t) > MAX_DRIFT) base = performance.now() - data.t
  } else if (data.state === 'stop') {
    stop()
  }
}
