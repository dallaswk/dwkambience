import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// base relativa: FiveM sirve la NUI desde nui://dwkambience/web/dist/
export default defineConfig({
  plugins: [vue()],
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
