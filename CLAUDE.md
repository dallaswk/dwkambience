# dwkambience

Editor in-game de cutscenes y ambiences para FiveM. El alcance completo, la arquitectura, el modelo de datos y el roadmap están en `docs/PLAN.md`: léelo antes de empezar cualquier fase.

## Stack

- FiveM (FXServer, build b3751+), Lua 5.4 (`lua54 'yes'` en el fxmanifest)
- QB-Core, ox_lib (`lib.callback`, `lib.points`, `lib.notify`), oxmysql, ox_inventory en el servidor
- NUI: Vue 3 + Vite + Pinia, TypeScript, en `web/`; el build sale a `web/dist` y el fxmanifest apunta ahí (`ui_page 'web/dist/index.html'`)

## Estructura

```
dwkambience/
  fxmanifest.lua
  config.lua            -- límites por estudio, radios, permisos, presets
  shared/               -- esquema de escena, interpolación (lineal, ease, Catmull-Rom), utilidades puras
  client/               -- free cam, gizmo, pool de entidades, efectos, grabación, reproducción, ambiences
  server/               -- CRUD, validación, permisos ACE, locks, disparo de cutscenes, exports
  sql/                  -- migraciones NNN_nombre.sql, aplicadas una vez al arrancar (server/migrations.lua)
  web/                  -- app Vue (src/, public/sounds/*.ogg)
  docs/PLAN.md
```

## Reglas de diseño (no negociables)

1. **Timeline determinista.** El estado de la escena es una función pura de `t`. El evaluador de `shared/` no toca natives; el cliente solo aplica su resultado. Nada se anima con tareas de IA sin estar anclado a keys.
2. **Entidades locales por defecto.** Spawn con `isNetwork = false`. Solo se ponen en red las que lo necesiten y cuentan contra el límite del estudio.
3. **Ids estables.** Las pistas referencian ids de entidad de la escena, nunca handles del juego.
4. **El timeline va en canvas** con `requestAnimationFrame`, fuera de la reactividad de Vue. Los datos grandes de la escena en `shallowRef`/`markRaw`. El scrub NUI → cliente se limita a 60 mensajes/s.
5. **El servidor valida todo guardado** contra el esquema y comprueba el ACE `cutscene.editor`. Nunca confiar en datos del cliente.
6. **Limpieza garantizada.** Todo lo que se crea (entidades, cámaras, timecycle, clima, ptfx, audio) se registra y se destruye al parar, al salir de zona y en `onResourceStop`.
7. **Schema versionado.** Cualquier cambio en el formato de `data` sube `schema` y añade una migración en `shared/`.
8. **Migraciones SQL inmutables.** Un cambio de tablas es un fichero nuevo `sql/NNN_*.sql` añadido al final de `FILES` en `server/migrations.lua`; nunca se edita una migración ya publicada.

## UI (design system v2.0)

- Fuente Montserrat; acento teal `#019685`; fondo casi negro `#070809`; radios 6/4 px.
- Pocos bordes visibles, separación por superficies; el verde solo para selección, acción principal y progreso.
- Iconos SVG monocromos, sin emojis. Un elemento visual dominante por pantalla.
- Define los tokens como variables CSS en `web/src/styles/tokens.css` y no uses colores sueltos.
- Idioma configurable con `Config.Locale` (`es` por defecto, `en`). Ningún texto de UI va en el código: todo sale de `web/src/i18n.ts` con `t('clave')`, y cada clave existe en los dos idiomas.
- Los datos de la escena viven en un `shallowRef`: al editar, sustituye el objeto que cambia (entidad, key, settings) en vez de mutarlo en sitio, o los `computed` no se enteran.

## Comandos

- `cd web && npm install && npm run dev`: NUI en el navegador con mocks de los callbacks (`web/src/mocks/`), para iterar la UI sin el juego.
- `cd web && npm run build`: genera `web/dist` (hay que hacerlo antes de reiniciar el recurso).
- `lua tests/run.lua` (desde la raíz): tests de `shared/` sin el juego.
- En el servidor: `refresh` + `ensure dwkambience` desde la consola de txAdmin.

## Cómo trabajar

- Ve **fase por fase** según `docs/PLAN.md` §7. Al terminar una fase, comprueba su gate y resume qué falta antes de pasar a la siguiente.
- Antes de cada fase, propón un plan corto (archivos que vas a crear o tocar y orden) y espera confirmación.
- Natives: usa los nombres de la documentación de natives de FiveM. Si dudas de la firma de un native, dilo en vez de inventarla.
- Las funciones de `shared/` deben poder probarse fuera del juego.
- Commits pequeños y por funcionalidad.
- No menciones "Reset" ni "Reset RP" en código, docs ni UI: el proyecto se llama dwkambience.
