// Música 2D de la pista "music", por grupos: 'cutscene' o un ambience ('amb_<id>', en bucle).
// El cliente manda t al empezar y cada segundo; entre medias la NUI lleva su propio reloj
// y se corrige si se desvía más de 120 ms.
import { AudioPlayer } from './audio'
import type { AudioClip } from './types'

const MAX_DRIFT = 120

interface Session {
  player: AudioPlayer
  clips: AudioClip[]
  base: number
  loop: number | null
}

const sessions = new Map<string, Session>()
let raf = 0

function sessionTime(s: Session) {
  const t = performance.now() - s.base
  return s.loop ? ((t % s.loop) + s.loop) % s.loop : t
}

function frame() {
  raf = requestAnimationFrame(frame)
  for (const s of sessions.values()) {
    const t = sessionTime(s)
    s.player.update(s.clips, t, t >= 0, s.loop ?? Infinity)
  }
}

function stop(group: string) {
  sessions.get(group)?.player.stop()
  sessions.delete(group)
  if (!sessions.size) cancelAnimationFrame(raf)
}

export interface MusicMessage {
  group: string
  state: 'start' | 'sync' | 'stop'
  t?: number
  clips?: unknown
  loop?: number
}

export function handleMusic(data: MusicMessage) {
  if (data.state === 'start') {
    stop(data.group)
    const session: Session = {
      player: new AudioPlayer(),
      clips: Array.isArray(data.clips) ? (data.clips as AudioClip[]) : [],
      base: performance.now() - (data.t ?? 0),
      loop: data.loop ?? null,
    }
    sessions.set(data.group, session)
    session.player.init().then(() => {
      if (sessions.size === 1) raf = requestAnimationFrame(frame)
    })
  } else if (data.state === 'sync') {
    const s = sessions.get(data.group)
    if (s && typeof data.t === 'number') {
      const drift = sessionTime(s) - data.t
      if (Math.abs(drift) > MAX_DRIFT && (!s.loop || Math.abs(Math.abs(drift) - s.loop) > MAX_DRIFT)) {
        s.base = performance.now() - data.t
      }
    }
  } else {
    stop(data.group)
  }
}
