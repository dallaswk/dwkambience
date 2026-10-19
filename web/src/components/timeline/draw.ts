// Dibujo del timeline en canvas. Fuera de Vue: se llama en cada frame con requestAnimationFrame.
import { clipEnd, findTrack, groupSpan } from '../../scene'
import type { AnyClip, AudioClip, EventKey, SceneData, VisibilityKey } from '../../types'
import type { ItemRef } from '../../stores/timeline'
import { ROW_H, type Row } from './rows'

export interface Palette {
  surface1: string
  surface2: string
  surface3: string
  line: string
  text: string
  text2: string
  text3: string
  accent: string
  accentSoft: string
  warning: string
  font: string
}

/** Colores del design system, leídos de las variables CSS de tokens.css. */
export function readPalette(): Palette {
  const css = getComputedStyle(document.documentElement)
  const v = (name: string) => css.getPropertyValue(name).trim()
  return {
    surface1: v('--surface-1'),
    surface2: v('--surface-2'),
    surface3: v('--surface-3'),
    line: v('--line'),
    text: v('--text'),
    text2: v('--text-2'),
    text3: v('--text-3'),
    accent: v('--accent'),
    accentSoft: v('--accent-soft'),
    warning: v('--warning'),
    font: v('--font'),
  }
}

export interface View {
  width: number
  pxPerMs: number
  scrollMs: number
  duration: number
}

// Ancho mínimo de un bloque de set piece para poder agarrarlo aunque dure poco
const MIN_BLOCK_PX = 24

// Margen a la izquierda para que las keys en t = 0 se vean enteras
export const PAD = 10

export const xOf = (view: View, t: number) => (t - view.scrollMs) * view.pxPerMs + PAD
export const tOf = (view: View, x: number) => (x - PAD) / view.pxPerMs + view.scrollMs

const STEPS = [100, 200, 500, 1000, 2000, 5000, 10000, 15000, 30000, 60000]

function label(ms: number, withTenths: boolean) {
  const total = ms / 1000
  const m = Math.floor(total / 60)
  const s = total - m * 60
  return withTenths ? `${m}:${s.toFixed(1).padStart(4, '0')}` : `${m}:${String(Math.round(s)).padStart(2, '0')}`
}

export function drawRuler(ctx: CanvasRenderingContext2D, view: View, height: number, pal: Palette, time: number, region: { start: number; end: number } | null) {
  ctx.clearRect(0, 0, view.width, height)
  ctx.fillStyle = pal.surface2
  ctx.fillRect(0, 0, view.width, height)

  const endX = xOf(view, view.duration)
  if (endX < view.width) {
    ctx.fillStyle = pal.surface1
    ctx.fillRect(Math.max(0, endX), 0, view.width - endX, height)
  }

  if (region) {
    ctx.fillStyle = pal.accentSoft
    ctx.fillRect(xOf(view, region.start), 0, (region.end - region.start) * view.pxPerMs, height)
  }

  const step = STEPS.find((s) => s * view.pxPerMs >= 70) ?? STEPS[STEPS.length - 1]
  const minor = step / (step >= 1000 ? 4 : 2)
  const first = Math.floor(view.scrollMs / minor) * minor
  ctx.font = `500 10px ${pal.font}`
  ctx.textBaseline = 'middle'
  for (let t = first; xOf(view, t) < view.width; t += minor) {
    const x = Math.round(xOf(view, t)) + 0.5
    const major = Math.abs(t % step) < 1e-6
    ctx.strokeStyle = major ? pal.text3 : pal.line
    ctx.beginPath()
    ctx.moveTo(x, major ? height - 9 : height - 5)
    ctx.lineTo(x, height)
    ctx.stroke()
    if (major) {
      ctx.fillStyle = pal.text3
      ctx.fillText(label(t, step < 1000), x + 4, height / 2 - 2)
    }
  }

  drawPlayhead(ctx, view, height, pal, time, true)
}

function drawPlayhead(ctx: CanvasRenderingContext2D, view: View, height: number, pal: Palette, time: number, head: boolean) {
  const x = Math.round(xOf(view, time)) + 0.5
  if (x < 0 || x > view.width) return
  ctx.strokeStyle = pal.accent
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.moveTo(x, 0)
  ctx.lineTo(x, height)
  ctx.stroke()
  if (head) {
    ctx.fillStyle = pal.accent
    ctx.beginPath()
    ctx.moveTo(x - 5, 0)
    ctx.lineTo(x + 5, 0)
    ctx.lineTo(x, 7)
    ctx.closePath()
    ctx.fill()
  }
}

function diamond(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, fill: string, stroke?: string) {
  ctx.beginPath()
  ctx.moveTo(x, y - r)
  ctx.lineTo(x + r, y)
  ctx.lineTo(x, y + r)
  ctx.lineTo(x - r, y)
  ctx.closePath()
  ctx.fillStyle = fill
  ctx.fill()
  if (stroke) {
    ctx.strokeStyle = stroke
    ctx.lineWidth = 1.5
    ctx.stroke()
  }
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.roundRect(x, y, Math.max(w, 2), h, r)
}

const EVENT_LETTER: Record<EventKey['type'], string> = { fade: 'F', subtitle: 'S', trigger: 'T' }

function clipLabel(clip: AnyClip) {
  return 'dict' in clip ? clip.clip : (clip as AudioClip).asset
}

export function drawLanes(
  ctx: CanvasRenderingContext2D,
  view: View,
  pal: Palette,
  rows: Row[],
  scene: SceneData,
  time: number,
  selected: ItemRef | null,
  selectedRow: string | null,
  region: { start: number; end: number } | null,
) {
  const height = rows.length * ROW_H
  ctx.clearRect(0, 0, view.width, height)

  const endX = xOf(view, view.duration)
  ctx.font = `500 10px ${pal.font}`
  ctx.textBaseline = 'middle'

  rows.forEach((row, i) => {
    const top = i * ROW_H
    const mid = top + ROW_H / 2

    ctx.fillStyle = row.id === selectedRow ? pal.surface3 : i % 2 ? pal.surface1 : pal.surface2
    ctx.fillRect(0, top, view.width, ROW_H)
    if (endX < view.width) {
      ctx.fillStyle = pal.surface1
      ctx.fillRect(Math.max(0, endX), top, view.width - endX, ROW_H)
    }

    if (row.groupId) {
      const group = scene.groups?.find((g) => g.id === row.groupId)
      const span = group && groupSpan(scene, group)
      if (!span) return
      const isSel = selected?.kind === 'group' && selected.trackId === row.groupId
      const x1 = xOf(view, span.start)
      const x2 = Math.max(xOf(view, span.end), x1 + MIN_BLOCK_PX)
      roundRect(ctx, x1, top + 3, x2 - x1, ROW_H - 6, 4)
      ctx.fillStyle = isSel ? pal.accent : pal.accentSoft
      ctx.fill()
      ctx.save()
      ctx.clip()
      ctx.fillStyle = isSel ? pal.text : pal.text2
      ctx.fillText(group!.label, x1 + 6, mid)
      ctx.restore()
      return
    }

    const track = findTrack(scene, row.target, row.channel)
    if (!track) return

    if (track.clips) {
      track.clips.forEach((clip, index) => {
        const isSel = selected?.trackId === track.id && selected.index === index && selected.kind === 'clip'
        const x1 = xOf(view, clip.start)
        const x2 = xOf(view, clipEnd(clip, view.duration))
        if (x2 < 0 || x1 > view.width) return
        roundRect(ctx, x1, top + 4, x2 - x1, ROW_H - 8, 3)
        ctx.fillStyle = isSel ? pal.accent : pal.surface3
        ctx.fill()
        ctx.save()
        ctx.clip()
        ctx.fillStyle = isSel ? pal.text : pal.text2
        ctx.fillText(clipLabel(clip), x1 + 6, mid)
        ctx.restore()
      })
      return
    }

    const keys = track.keys ?? []

    if (track.channel === 'event') {
      keys.forEach((key, index) => {
        const k = key as EventKey
        const x = xOf(view, k.t)
        if ('duration' in k && k.duration > 0) {
          ctx.fillStyle = pal.accentSoft
          ctx.fillRect(x, top + 8, k.duration * view.pxPerMs, ROW_H - 16)
        }
        const isSel = selected?.trackId === track.id && selected.index === index
        diamond(ctx, x, mid, 6, isSel ? pal.accent : pal.text3)
        ctx.fillStyle = pal.text2
        ctx.fillText(EVENT_LETTER[k.type], x + 9, mid)
      })
      return
    }

    if (track.channel === 'visibility') {
      const vis = keys as VisibilityKey[]
      vis.forEach((k, index) => {
        const next = vis[index + 1]
        const start = index === 0 ? 0 : k.t
        if (k.visible || (index === 0 && vis[0].visible)) {
          const x1 = xOf(view, start)
          const x2 = next ? xOf(view, next.t) : xOf(view, view.duration)
          ctx.fillStyle = pal.accentSoft
          ctx.fillRect(x1, top + 7, Math.max(2, x2 - x1), ROW_H - 14)
        }
        const isSel = selected?.trackId === track.id && selected.index === index
        diamond(ctx, xOf(view, k.t), mid, 5, isSel ? pal.accent : pal.text2, isSel ? pal.text : undefined)
      })
      return
    }

    // Transform / cámara: línea entre keys y rombos
    if (keys.length > 1) {
      ctx.strokeStyle = pal.text3
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(xOf(view, keys[0].t), mid)
      ctx.lineTo(xOf(view, keys[keys.length - 1].t), mid)
      ctx.stroke()
    }
    keys.forEach((key, index) => {
      const x = xOf(view, key.t)
      if (x < -8 || x > view.width + 8) return
      const isSel = selected?.trackId === track.id && selected.index === index && selected.kind === 'key'
      diamond(ctx, x, mid, 5, isSel ? pal.accent : pal.text2, isSel ? pal.text : undefined)
    })
  })

  if (region) {
    ctx.fillStyle = pal.accentSoft
    ctx.fillRect(xOf(view, region.start), 0, (region.end - region.start) * view.pxPerMs, height)
  }

  // Línea de 1 px entre filas para separar sin bordes marcados
  ctx.fillStyle = pal.line
  for (let i = 1; i < rows.length; i++) ctx.fillRect(0, i * ROW_H, view.width, 1)

  drawPlayhead(ctx, view, height, pal, time, false)
}

/** Key o clip bajo el puntero en una fila, o null. */
export function hitItem(scene: SceneData, row: Row, view: View, x: number): ItemRef | null {
  if (row.groupId) {
    const group = scene.groups?.find((g) => g.id === row.groupId)
    const span = group && groupSpan(scene, group)
    if (!span) return null
    const x1 = xOf(view, span.start)
    const x2 = Math.max(xOf(view, span.end), x1 + MIN_BLOCK_PX)
    return x >= x1 && x <= x2 ? { trackId: row.groupId!, index: 0, kind: 'group' } : null
  }
  const track = findTrack(scene, row.target, row.channel)
  if (!track) return null
  if (track.keys) {
    let best: ItemRef | null = null
    let bestDist = 7
    track.keys.forEach((k, index) => {
      const d = Math.abs(xOf(view, k.t) - x)
      if (d <= bestDist) {
        best = { trackId: track.id, index, kind: 'key' }
        bestDist = d
      }
    })
    return best
  }
  const clips = track.clips ?? []
  for (let index = clips.length - 1; index >= 0; index--) {
    const c = clips[index]
    if (x >= xOf(view, c.start) && x <= xOf(view, clipEnd(c, view.duration))) return { trackId: track.id, index, kind: 'clip' }
  }
  return null
}
