<script setup lang="ts">
import { t } from '../i18n'
import { formatDuration } from '../scene'
import { useEditor } from '../stores/editor'

// Reserva el hueco del timeline; el componente en canvas llega en la fase 1
const editor = useEditor()
</script>

<template>
  <footer class="timeline">
    <div class="bar">
      <span class="section-title">{{ t('timeline') }}</span>
      <span class="mono faint">0:00 / {{ formatDuration(editor.scene?.settings.duration ?? 0) }}</span>
    </div>
    <div class="lane">
      <span class="faint">{{ t('timelineSoon') }}</span>
    </div>
  </footer>
</template>

<style scoped>
.timeline { grid-area: timeline; display: flex; flex-direction: column; background: var(--surface-1); }
.bar { display: flex; align-items: center; justify-content: space-between; height: 36px; padding: 0 14px; background: var(--surface-2); }
.lane { flex: 1; display: flex; align-items: center; justify-content: center; font-size: var(--fs-sm); }
</style>
