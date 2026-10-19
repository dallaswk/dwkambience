# dwkambience

Versión 1.0.0.

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

## Ambiences

Un ambience es una escena viva en el mundo (multitudes, coches, sonido, clima) que aparece para cada
jugador al entrar en su radio y se limpia al salir, en bucle y sin quitarle el control.

- Se crea en el editor con tipo Ambience; su zona nace donde mira la cámara (ajústala en el panel de escena).
- El interruptor **Activo en el servidor** (panel de escena o ON/OFF en la lista) lo enciende para todos al momento.
- Horario opcional con la hora del juego (admite franjas que cruzan medianoche).
- Límites en `config.lua` (`Config.Ambience`): 60 peds por ambience y 100 en total por jugador.
- Presets de multitudes en `Config.CrowdPresets`; la semilla hace que todos vean la misma gente.

## Efectos, grabación y set pieces

- **Texto 3D, luces y partículas**: paletas Texto, Luces y Partículas. Las luces se limitan a 16 a la vez
  (las más cercanas) y las partículas salen del catálogo `Config.PtfxCatalog`. Límites en `Config.Fx`.
- **Visibilidad**: "Ocultar/Mostrar desde aquí" (tecla H) crea keys de visibilidad para que cualquier
  entidad o efecto aparezca o desaparezca en un instante.
- **Grabación en vivo (REC, tecla R)**: con un actor o coche seleccionado, caminas o conduces con tu
  propio personaje (o el coche en el que vas) desde su pose; el timeline avanza a la vez. Retroceso termina,
  la trayectoria se simplifica (RDP, `Config.Recording.epsilon`) y sustituye ese tramo de la pista.
- **Set pieces**: selecciona entidades (Ctrl+clic) y guárdalas desde el botón Set pieces; al insertarlas
  se colocan donde mira la cámara y a partir del instante actual, con ids nuevos.

## Pantallas, red e intercambio de escenas

- **Texto en pantallas**: la paleta Pantallas crea props con pantalla (`Config.ScreenProps`) y pinta en ella
  texto y fondo. Limitación del juego: los props del mismo modelo comparten pantalla (se dibuja la más cercana).
- **Entidades en red** (solo ambiences): marca actores, coches o props como "En red" para que los jugadores
  puedan interactuar. El servidor (OneSync) los crea una vez mientras haya alguien en la zona y se quedan en
  su pose inicial. Límite por estudio en `Config.Studios[n].maxNetworked`; al pasarlo se avisa y quedan locales.
- **Exportar / importar**: Archivo → Exportar escena (copiar o descargar el JSON) y Archivo → Importar escena
  en otro servidor. El servidor migra y valida el JSON y crea una escena nueva; los ambiences llegan apagados.
- **Cutscenes**: también admiten emisores de sonido 3D y multitudes (se crean durante la pantalla en negro).

## Cámara, bloques y rendimiento

- **Roll y profundidad de campo**: en la cámara libre Z/C giran (X endereza); las keys de cámara admiten
  profundidad de campo (intensidad y distancias de enfoque), interpolada entre keys.
- **Set pieces como bloque**: al insertar una set piece (o con Herramientas → Agrupar selección, Ctrl+G)
  sus entidades forman un bloque con fila propia en el timeline; arrastrarlo mueve todas sus keys a la vez.
- **Coste por frame**: la barra superior del editor muestra ms/frame y FPS (aviso por debajo de 50 fps).
- **Bailes** en los presets Discoteca y Público de concierto, y **peds en red animados** (escenario o
  animación aplicados por su dueño de red).

## Música

Copia los `.ogg` a `web/public/sounds/`, compila (`npm run build`) y reinicia el recurso: aparecen en
el botón Música del timeline. El id de cada sonido es el nombre del archivo sin extensión.

## Depuración

`setr dwkambience_debug 1` muestra en pantalla la sesión, el tiempo `t` y cuánto tarde empezó cada
cliente (si la precarga no llegó a tiempo).
