# dwkambience

Editor in-game de cutscenes y ambiences para FiveM. Alcance y roadmap en [`docs/PLAN.md`](docs/PLAN.md).

## Instalación

1. Dependencias: `ox_lib`, `oxmysql` (QB-Core opcional, para permisos por grupo).
2. Compila la NUI: `cd web && npm install && npm run build`.
3. Permisos en `server.cfg`:
   ```
   add_ace group.admin cutscene.editor allow
   ensure dwkambience
   ```
4. In-game: `/scenes`.

Las tablas se crean solas al arrancar el recurso por primera vez: las migraciones de `sql/` se aplican una vez y quedan registradas en `dwkambience_migrations`.

El idioma de la UI se elige en `config.lua` (`Config.Locale = 'es'` o `'en'`). Los textos están en `web/src/i18n.ts`.

## Controles del editor

| Acción | Control |
| --- | --- |
| Volar la cámara | Mantener botón derecho sobre el viewport + WASD, Q/E bajar/subir, Shift rápido, Ctrl lento |
| Seleccionar | Clic izquierdo sobre la entidad o en el outliner |
| Mover / rotar | Botones Move / Rotate del inspector; W/R cambian de modo, Enter o Esc para terminar |
| Guardar | Ctrl+S |
| Borrar selección | Supr |
| Encuadrar selección | F |

## Reproducir cutscenes

`/cutscene <id> [me|all|1,2,3] [noskip]` reproduce una cutscene (por defecto, para quien lo escribe).
`/cutscene stop [me|all|1,2,3]` la para. Requiere el mismo permiso que el editor. El jugador puede
saltarla con Retroceso salvo con `noskip`.

Desde otros recursos (servidor):

```lua
local session, err = exports.dwkambience:PlayCutscene(sceneId, targets, { skippable = true })
exports.dwkambience:StopCutscene(targets) -- targets: id, lista de ids o 'all'

AddEventHandler('dwkambience:finished', function(sceneId, playerId, skipped) end)
```

En el cliente se emiten `dwkambience:finished (sceneId, skipped)` y, por cada key de tipo trigger,
`dwkambience:trigger (sceneId, name)`.

## Música

Copia los `.ogg` a `web/public/sounds/`, compila (`npm run build`) y reinicia el recurso: aparecen en
el botón Música del timeline. El id de cada sonido es el nombre del archivo sin extensión.

## Depuración

`setr dwkambience_debug 1` muestra en pantalla la sesión, el tiempo `t` y cuánto tarde empezó cada
cliente (si la precarga no llegó a tiempo).
