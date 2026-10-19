<script setup lang="ts">
// Iconos SVG monocromos (trazo de 1.75 px, heredan currentColor)
const props = withDefaults(defineProps<{ name: string; size?: number }>(), { size: 16 })

const PATHS: Record<string, string> = {
  plus: 'M12 5v14M5 12h14',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  film: 'M4 5h16v14H4zM8 5v14M16 5v14M4 9h4M4 15h4M16 9h4M16 15h4',
  waves: 'M3 9c3-3 6 3 9 0s6 3 9 0M3 15c3-3 6 3 9 0s6 3 9 0',
  ped: 'M12 4a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM6 20v-2a6 6 0 0 1 12 0v2',
  vehicle: 'M5 16l1.5-5.5A2 2 0 0 1 8.4 9h7.2a2 2 0 0 1 1.9 1.5L19 16M4 16h16v3H4zM7 19v1.5M17 19v1.5',
  prop: 'M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12L4 7.5',
  sound: 'M4 10v4h4l5 4V6L8 10zM16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11',
  crowd: 'M9 5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM3 19v-1a6 6 0 0 1 12 0v1M16 5.5a2.5 2.5 0 0 1 0 4.5M18 13a6 6 0 0 1 3 5v1',
  trash: 'M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3',
  close: 'M6 6l12 12M18 6L6 18',
  save: 'M5 4h11l4 4v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM8 4v5h7V4M8 20v-6h8v6',
  move: 'M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3',
  rotate: 'M20 12a8 8 0 1 1-2.3-5.6M20 4v5h-5',
  ground: 'M12 4v10M8 10l4 4 4-4M4 19h16',
  focus: 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5M12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4z',
  lock: 'M6 11h12v9H6zM8 11V8a4 4 0 0 1 8 0v3',
  chevron: 'M9 6l6 6-6 6',
  back: 'M15 6l-6 6 6 6',
  tag: 'M3 12V4h8l9 9-8 8zM7.5 7.5h.01',
  exit: 'M14 4h5v16h-5M10 8l-4 4 4 4M6 12h10',
  play: 'M7 5l12 7-12 7z',
  pause: 'M8 5v14M16 5v14',
  skipStart: 'M6 5v14M18 6l-9 6 9 6z',
  skipEnd: 'M18 5v14M6 6l9 6-9 6z',
  prevKey: 'M14 7l-5 5 5 5M5 12h0',
  nextKey: 'M10 7l5 5-5 5M19 12h0',
  key: 'M12 4l8 8-8 8-8-8z',
  camera: 'M4 8h11v9H4zM15 11l5-3v9l-5-3',
  undo: 'M9 7L4 12l5 5M4 12h11a5 5 0 0 1 0 10h-2',
  redo: 'M15 7l5 5-5 5M20 12H9a5 5 0 0 0 0 10h2',
  loop: 'M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4',
  magnet: 'M6 4v7a6 6 0 0 0 12 0V4M6 8h4M14 8h4M10 4v7a2 2 0 0 0 4 0V4',
  zoomIn: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4M11 8v6M8 11h6',
  zoomOut: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4M8 11h6',
  music: 'M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM20 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
  flag: 'M5 21V4M5 4h11l-2 4 2 4H5',
}
</script>

<template>
  <svg
    :width="props.size"
    :height="props.size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.75"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path :d="PATHS[props.name] ?? ''" />
  </svg>
</template>
