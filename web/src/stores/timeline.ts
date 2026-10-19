import { defineStore } from 'pinia'
import { ref } from 'vue'
import { AudioPlayer } from '../audio'
import { fetchNui } from '../nui'
import { MUSIC, findTrack, keyTimes, sceneDuration } from '../scene'
import type { AudioClip } from '../types'
import { useEditor } from './editor'

export interface ItemRef {
  trackId: string
  index: number
  kind: 'key' | 'clip'
}

const SEND_INTERVAL = 1000 / 60 // scrub NUI -> cliente: como mucho 60 mensajes/s
const SNAP_MS = 100

export const useTimeline = defineStore('timeline', () => {
  const time = ref(0)
  const playing = ref(false)
  const autoKey = ref(true)
  const snap = ref(true)
  const loop = ref(false)
  const region = ref<{ start: number; end: number } | null>(null)
  const cameraView = ref(false)
  const pxPerSec = ref(80)
  const scrollMs = ref(0) // ms en el borde izquierdo de las pistas
  const selectedRow = ref<string | null>(null)
  const selected = ref<ItemRef | null>(null)

  const audio = new AudioPlayer()
  audio.init()

  // --- Envío de t al cliente con límite de frecuencia ------------------------
  let lastSent = 0
  let pendingT: number | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  function flush() {
    timer = null
    if (pendingT === null) return
    lastSent = performance.now()
    fetchNui('time', { t: pendingT })
    pendingT = null
  }

  function sendTime(t: number) {
    pendingT = t
    if (performance.now() - lastSent >= SEND_INTERVAL) flush()
    else timer ??= setTimeout(flush, SEND_INTERVAL)
  }

  // ---------------------------------------------------------------------------

  function duration() {
    const scene = useEditor().scene
    return scene ? sceneDuration(scene) : 0
  }

  function snapTime(t: number) {
    return snap.value ? Math.round(t / SNAP_MS) * SNAP_MS : Math.round(t)
  }

  function setTime(t: number) {
    time.value = Math.max(0, Math.min(duration(), Math.round(t)))
    sendTime(time.value)
    useEditor().schedulePoseRefresh()
  }

  function musicClips(): AudioClip[] {
    const scene = useEditor().scene
    return scene ? ((findTrack(scene, MUSIC, 'audio')?.clips ?? []) as AudioClip[]) : []
  }

  // --- Reproducción en el editor (preview) -------------------------------------
  let raf = 0
  let lastFrame = 0

  function frame(now: number) {
    if (!playing.value) return
    const end = duration()
    let t = time.value + (now - lastFrame)
    lastFrame = now

    if (region.value && loop.value && t >= region.value.end) {
      t = region.value.start
    } else if (t >= end) {
      const scene = useEditor().scene
      if (loop.value || scene?.settings.loop) {
        t = 0
      } else {
        setTime(end)
        pause()
        return
      }
    }

    setTime(t)
    audio.update(musicClips(), time.value, true, end)
    raf = requestAnimationFrame(frame)
  }

  function play() {
    if (playing.value || !useEditor().scene) return
    if (time.value >= duration()) setTime(region.value?.start ?? 0)
    playing.value = true
    lastFrame = performance.now()
    raf = requestAnimationFrame(frame)
  }

  function pause() {
    playing.value = false
    cancelAnimationFrame(raf)
    audio.update([], 0, false, 0)
  }

  function toggle() {
    if (playing.value) pause()
    else play()
  }

  function jump(to: 'start' | 'end' | 'prev' | 'next') {
    const scene = useEditor().scene
    if (!scene) return
    if (to === 'start') return setTime(0)
    if (to === 'end') return setTime(duration())
    const times = keyTimes(scene)
    const target = to === 'prev'
      ? [...times].reverse().find((k) => k < time.value)
      : times.find((k) => k > time.value)
    if (target !== undefined) setTime(target)
  }

  function setCameraView(active: boolean) {
    cameraView.value = active
    fetchNui('cameraView', { active })
  }

  function select(item: ItemRef | null) {
    selected.value = item
  }

  function reset() {
    pause()
    audio.stop()
    time.value = 0
    region.value = null
    selected.value = null
    selectedRow.value = null
    scrollMs.value = 0
    if (cameraView.value) setCameraView(false)
  }

  return {
    time, playing, autoKey, snap, loop, region, cameraView, pxPerSec, scrollMs, selectedRow, selected,
    snapTime, setTime, play, pause, toggle, jump, setCameraView, select, reset, duration,
  }
})
