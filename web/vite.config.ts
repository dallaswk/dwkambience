import { mkdirSync, readdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig, type Plugin } from 'vite'
import vue from '@vitejs/plugin-vue'

const SOUNDS_DIR = fileURLToPath(new URL('./public/sounds', import.meta.url))

/** Genera public/sounds/manifest.json con los .ogg/.mp3 de la carpeta: la paleta Sounds lo lee. */
function soundManifest(): Plugin {
  const write = () => {
    mkdirSync(SOUNDS_DIR, { recursive: true })
    const sounds = readdirSync(SOUNDS_DIR)
      .filter((f) => /\.(ogg|mp3)$/i.test(f))
      .sort()
      // El id tiene que cumplir el patrón de assets del esquema: letras, números, _ y -
      .map((file) => ({ id: file.replace(/\.[^.]+$/, '').replace(/[^\w-]/g, '_').slice(0, 64), file }))
    writeFileSync(join(SOUNDS_DIR, 'manifest.json'), JSON.stringify(sounds, null, 2) + '\n')
  }
  return {
    name: 'dwkambience-sound-manifest',
    buildStart: write,
    configureServer(server) {
      write()
      server.watcher.add(SOUNDS_DIR)
      server.watcher.on('all', (_event, path) => {
        if (path.startsWith(SOUNDS_DIR) && !path.endsWith('manifest.json')) write()
      })
    },
  }
}

// base relativa: FiveM sirve la NUI desde nui://dwkambience/web/dist/
export default defineConfig({
  plugins: [vue(), soundManifest()],
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
