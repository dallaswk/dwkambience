import { defineConfig } from 'vitest/config'

// jsdom: los stores usan window, localStorage y postMessage (los mocks responden a fetchNui fuera del juego)
export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.ts'],
  },
})
