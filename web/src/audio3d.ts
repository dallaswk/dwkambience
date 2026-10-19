// Emisores de sonido 3D con Web Audio. El cliente manda los emisores por grupos y la posición/orientación
// de la cámara 20 veces por segundo. Coordenadas de GTA (z arriba) -> Web Audio (y arriba): (x, z, -y).
import { loadSounds } from './audio'
import type { Vec3 } from './types'

interface Emitter {
  id: string
  asset: string
  volume: number
  range: number
  loop: boolean
  pos: Vec3
}

interface Voice {
  key: string
  el: HTMLAudioElement
  panner: PannerNode
  gain: GainNode
}

let ctx: AudioContext | null = null
const files = new Map<string, string>()
const groups = new Map<string, Map<string, Voice>>()

const toWeb = (v: Vec3): [number, number, number] => [v[0], v[2], -v[1]]

async function context() {
  if (!ctx) {
    ctx = new AudioContext()
    for (const s of await loadSounds()) files.set(s.id, s.file)
  }
  if (ctx.state === 'suspended') await ctx.resume().catch(() => {})
  return ctx
}

function createVoice(audio: AudioContext, e: Emitter): Voice | null {
  const file = files.get(e.asset)
  if (!file) return null
  const el = new Audio(`sounds/${file}`)
  el.loop = e.loop
  el.crossOrigin = 'anonymous'
  const source = audio.createMediaElementSource(el)
  const panner = audio.createPanner()
  panner.panningModel = 'HRTF'
  panner.distanceModel = 'linear'
  panner.refDistance = 1
  panner.rolloffFactor = 1
  const gain = audio.createGain()
  source.connect(panner).connect(gain).connect(audio.destination)
  el.play().catch(() => {})
  return { key: `${e.asset}|${e.loop}`, el, panner, gain }
}

function stopVoice(v: Voice) {
  v.el.pause()
  v.el.src = ''
  v.gain.disconnect()
}

async function setGroup(group: string, emitters: Emitter[]) {
  const audio = await context()
  const voices = groups.get(group) ?? new Map<string, Voice>()
  groups.set(group, voices)
  const seen = new Set<string>()

  for (const e of emitters) {
    seen.add(e.id)
    let voice = voices.get(e.id)
    if (voice && voice.key !== `${e.asset}|${e.loop}`) {
      stopVoice(voice)
      voice = undefined
    }
    if (!voice) {
      const created = createVoice(audio, e)
      if (!created) continue
      voice = created
      voices.set(e.id, voice)
    }
    const [x, y, z] = toWeb(e.pos)
    voice.panner.positionX.value = x
    voice.panner.positionY.value = y
    voice.panner.positionZ.value = z
    voice.panner.maxDistance = e.range
    voice.gain.gain.value = e.volume
  }

  for (const [id, voice] of voices) {
    if (!seen.has(id)) {
      stopVoice(voice)
      voices.delete(id)
    }
  }
}

function clearGroup(group: string) {
  for (const voice of groups.get(group)?.values() ?? []) stopVoice(voice)
  groups.delete(group)
}

function setListener(pos: Vec3, forward: Vec3, up: Vec3) {
  if (!ctx) return
  const l = ctx.listener
  const [px, py, pz] = toWeb(pos)
  const [fx, fy, fz] = toWeb(forward)
  const [ux, uy, uz] = toWeb(up)
  l.positionX.value = px
  l.positionY.value = py
  l.positionZ.value = pz
  l.forwardX.value = fx
  l.forwardY.value = fy
  l.forwardZ.value = fz
  l.upX.value = ux
  l.upY.value = uy
  l.upZ.value = uz
}

export type Audio3DMessage =
  | { op: 'set'; group: string; emitters: unknown }
  | { op: 'clear'; group: string }
  | { op: 'listener'; pos: Vec3; forward: Vec3; up: Vec3 }

export function handleAudio3D(data: Audio3DMessage) {
  if (data.op === 'set') setGroup(data.group, Array.isArray(data.emitters) ? (data.emitters as Emitter[]) : [])
  else if (data.op === 'clear') clearGroup(data.group)
  else setListener(data.pos, data.forward, data.up)
}
