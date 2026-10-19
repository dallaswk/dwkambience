# Plan: editor de cutscenes y ambiente (dwkambience)

Exportado del plan de diseño (19/10/2026). Este archivo es la fuente de verdad del alcance; `CLAUDE.md` resume las reglas de trabajo.

## 1. Referencia

Editor in-game para FiveM (build b3751) que monta escenas en el propio mundo con free cam, un timeline estilo NLE y un inspector por entidad. Dos tipos de escena:

- **Cutscene**: toma la cámara del jugador, se reproduce una vez, letterbox, saltable.
- **Ambience**: escena viva en el mundo (multitudes, coches, sonido, texto 3D), en bucle, sin quitar el control.

| Zona de la UI | Qué tiene | Qué replicar |
| --- | --- | --- |
| Barra superior | Menús File/Edit/View/Tools/World/Settings/Help; paletas Peds, Cars, Props, Text, Lights, Crowds, Sounds, Set Pieces; breadcrumb `Grupo / Escena`, "Saved 21:46", contador `Studio 1 // 115/300`; Free cam y Preview | Todo; el contador de entidades por estudio es clave |
| Panel izquierdo (sin escena) | Crear Cutscene o Ambience con nombre y grupo opcional; lista agrupada por carpetas con filtros y buscador; cada fila muestra tipo, nº de actores y keys | Gestor de escenas con grupos |
| Panel izquierdo ("In the scene") | Árbol de entidades: actores, vehículos, props, emisores de sonido, crowd; resumen de escena (tipo, grupo, duración, tracks/keys, clima y hora, salida letterbox/HUD) | Outliner + ficha de escena |
| Viewport | Entidad seleccionada con contorno, gizmo flotante Move/Rotate/Scale/Settings, iconos de altavoz en emisores, etiquetas de nombre, texto 3D | Selección por raycast, gizmo, overlays |
| Inspector derecho | Vehículo: transform, Move/Rotate/Scale/Ground/Look, motor, luces, sirena, puertas, capó, maletero, suciedad, tuning, frozen/visible/collision, opacidad. Texto: contenido, color, visible desde detrás, estilo | Inspector por tipo de entidad |
| Timeline | Play, rec, saltos, tiempo actual y duración, Key, Camera view, Auto key, loop, Snap, Labels, undo/redo, zoom, Preview; pistas de set pieces y de audio con loop, volumen y fade in | Timeline multipista con keyframes y clips |
| Avisos | "Loaded …"; "Network limit reached: more peds are only visible to you" | Toasts y límites de entidades en red |

Presets de Crowds: Custom, Club goers, Street, Business, Beach, bandas, Paparazzi, Concert audience.

## 2. Alcance del MVP

Editor para staff que crea, guarda y reproduce escenas de los dos tipos en el servidor, con un estudio y un límite de entidades.

**Entra en el MVP**

- Free cam con gizmo (mover, rotar, pegar al suelo) y selección por raycast
- Paletas Peds, Cars, Props, Sounds y Crowds básico (un preset, franja por puntos)
- Inspector con transform + propiedades clave por tipo (anim/escenario en peds; motor, luces y puertas en coches)
- Timeline con pistas de transform, cámara y audio; keyframes con interpolación lineal y ease
- Clima y hora por escena
- Guardado en base de datos, gestor de escenas con grupos
- Reproducción: cutscene para un jugador o un grupo; ambience activado por zona
- Permisos por ACE / grupo de QB-Core

**Fuera del MVP (fase 2+)**

- Texto 3D, luces dinámicas, partículas y set pieces compuestos
- Grabación en vivo (REC)
- Varios estudios en paralelo, colaboración en tiempo real
- Exportar/importar escenas entre servidores

**Criterio de éxito:** un miembro del staff monta la cutscene de bienvenida (cámara + 3 actores + 1 coche + música) en menos de 1 h sin tocar Lua, y se reproduce sin desincronización para 10 jugadores a la vez.

## 3. Arquitectura

Un solo recurso, `dwkambience`, con tres capas:

```
┌──────────────────────┐  SendNUIMessage /   ┌──────────────────────┐  lib.callback /   ┌──────────────────────┐
│ NUI (Vue 3+Vite+Pinia)│ ◀──────────────────▶│ Cliente Lua (ox_lib) │ ◀────────────────▶│ Servidor Lua (QB-Core)│
│ Timeline, inspector,  │  RegisterNUICallback│ Free cam y gizmo     │  eventos de red   │ Permisos ACE, validar │
│ outliner, paletas,    │                     │ Spawn local          │                   │ CRUD escenas/revisión │
│ audio 3D (Web Audio), │                     │ Evalúa pistas en t   │                   │ Dispara cutscenes     │
│ undo/redo             │                     │ Precarga y limpieza  │                   │ Reloj de red, locks   │
└──────────────────────┘                     └──────────┬───────────┘                   └──────────┬───────────┘
                                                        │ natives                                  │ oxmysql
                                             ┌──────────▼───────────┐                   ┌──────────▼───────────┐
                                             │ Motor GTA V          │                   │ MySQL                │
                                             │ cams, peds, ptfx,    │                   │ scenes, revisions,   │
                                             │ clima, luces, tcycle │                   │ assets               │
                                             └──────────────────────┘                   └──────────────────────┘
```

El cliente es la pieza crítica: recibe un tiempo `t` (del scrub del editor o del reloj de red en reproducción) y coloca cada entidad, cámara y luz en su estado para ese instante.

- **NUI en Vue 3 + Vite + Pinia.** El playhead y las pistas del timeline se dibujan en canvas con `requestAnimationFrame`, fuera del sistema reactivo; los datos grandes de la escena van en `shallowRef` / `markRaw`.
- **Estructura:** `client/`, `server/`, `shared/` (esquema y utilidades de interpolación), `web/` (Vite, build a `web/dist`).
- **NUI ↔ cliente:** `SendNUIMessage` / `RegisterNUICallback`; el scrub se limita a 60 mensajes/s.
- **Cliente ↔ servidor:** `lib.callback` para guardar y cargar; eventos para iniciar o parar reproducciones.
- **Gizmo:** native de gizmo de CFX (`DrawGizmo`); alternativa propia con flechas dibujadas y raycast.
- **API para otros scripts:** `exports.dwkambience:PlayCutscene(id, targets)` y `StopCutscene`; evento `dwkambience:finished`.

## 4. Módulo Cutscene Editor

Timeline determinista: el tiempo `t` manda y cada pista sabe calcular su estado en `t`, así que pausar, hacer scrub o saltar da siempre el mismo resultado. Nada se "reproduce" con tareas de IA del juego sin estar anclado a una key.

**Timeline**

1. Pistas por entidad, con sub-pistas: transform, animación, propiedades (luces, puertas), visibilidad.
2. Pista de cámara: keys con posición, rotación, FOV y DOF; interpolación lineal, ease in/out y spline Catmull-Rom.
3. Pistas de audio y de eventos (fade a negro, subtítulo, disparar un trigger de otro script).
4. Controles: Key, Auto key (graba key al mover el gizmo), Snap a 0,1 s, Labels, loop de región, undo/redo con pila de comandos.
5. Scrub a 60 fps: el NUI envía `t` al cliente, el cliente aplica el estado sin física (entidades congeladas).

**Cámara**

- Free cam propia: `CreateCamWithParams` + `RenderScriptCams`, WASD/ratón con velocidad variable y roll.
- "Camera view" pasa el viewport a la cámara de la cutscene para encuadrar y pulsar Key.
- Reproducción: letterbox, HUD oculto (`DisplayRadar`, `HideHudAndRadarThisFrame`), saltable con una tecla, fundido de salida a la cámara del jugador.

**Actores**

- Peds: modelo, ropa (o clon del jugador), animación con diccionario + clip y blend, escenarios, mirar a un punto.
- Vehículos: modelo, tuning, motor, luces, sirena, puertas; trayectoria por keys de transform o grabación REC.
- Props: modelo, attach a hueso de un ped o a un vehículo.
- Todas las entidades de cutscene son **locales** (no en red) y las crea cada cliente que la ve.

**Grabación REC (fase 3)**: el editor conduce o camina en vivo, se muestrea transform y velocidad cada 50 ms, se simplifica la curva (Ramer–Douglas–Peucker) y se convierte en keys editables.

## 5. Módulo Ambience Editor

Escena que vive en el mundo mientras un jugador está dentro de su radio, en bucle, sin quitarle el control. Mismo timeline que la cutscene, sin pista de cámara y con loop por defecto.

| Elemento | Cómo se implementa | Notas |
| --- | --- | --- |
| Crowds | Spawn local de N peds a lo largo de una polilínea o un área; preset = modelos + escenarios/anims (`TaskStartScenarioInPlace`, `TaskPlayAnim`) con desfase aleatorio con semilla | Semilla fija para que todos vean la misma multitud; LOD por distancia |
| Clima y hora | `SetWeatherTypeNowPersist`, `NetworkOverrideClockTime`, `SetTimecycleModifier` + intensidad | Solo para el jugador dentro de la zona; al salir se restaura (qb-weathersync) |
| Luces | `DrawLightWithRangeAndShadow` / `DrawSpotLightWithShadow` cada frame | Limitar a ~16 activas y apagar por distancia |
| Partículas | `UseParticleFxAsset` + `StartParticleFxLoopedAtCoord` | Catálogo curado de assets |
| Sonido | Emisores 3D en el NUI con Web Audio (`PannerNode`), posición relativa a la cámara actualizada cada frame; volumen, loop, fade in | Audios .ogg dentro del recurso |
| Texto 3D | `SetDrawOrigin` + texto escalado, o render target en un prop (fase 3) | Color, tamaño, visible desde detrás |
| Set pieces | Grupo guardado de entidades + pistas reutilizable | Se arrastra al timeline como un clip |

**Activación:** interruptor activo/inactivo, franja horaria opcional, centro, radio de entrada y radio de salida (histéresis ~20 m). `lib.points` de ox_lib, comprobación cada 500 ms; crea al entrar y limpia todo al salir.

**Red:** todo local por defecto. Solo se ponen en red las entidades con las que el jugador interactúa, y cuentan contra el límite del estudio.

## 6. Modelo de datos

Cada escena es un documento JSON versionado en MySQL (oxmysql), con columnas de índice para listar sin cargar el JSON.

| Tabla | Columnas | Uso |
| --- | --- | --- |
| `scenes` | id, name, type (`cutscene`/`ambience`), group_name, studio, duration_ms, active, schedule, data (JSON), schema_version, updated_by, updated_at | Escena completa |
| `scene_revisions` | scene_id, rev, data, created_by, created_at | Historial; guardar las últimas 20 |
| `scene_assets` | id, kind (`sound`/`set_piece`/`crowd_preset`), name, data | Bibliotecas reutilizables |

```json
{
  "schema": 1,
  "settings": {
    "weather": "CLEAR", "time": "04:35",
    "output": { "letterbox": true, "hud": false },
    "loop": true, "active": true, "schedule": null,
    "trigger": { "center": [292.9, -847.1, 28.8], "enter": 80, "exit": 100 }
  },
  "entities": [
    { "id": "veh_1", "kind": "vehicle", "model": "elegy", "label": "Vehicle 1",
      "props": { "engine": true, "headlights": true, "dirt": 5.2 }, "networked": false }
  ],
  "tracks": [
    { "id": "t1", "target": "veh_1", "channel": "transform",
      "keys": [ { "t": 0, "pos": [292.9, -847.1, 28.8], "rot": [0.05, 1.42, 86.48], "ease": "inOut" } ] },
    { "id": "cam", "target": "camera", "channel": "camera",
      "keys": [ { "t": 0, "pos": [0, 0, 0], "rot": [0, 0, 0], "fov": 45 } ] },
    { "id": "a1", "target": "snd_1", "channel": "audio",
      "clips": [ { "start": 0, "asset": "crowd_cheering", "volume": 0.22, "loop": true, "fadeIn": 1500 } ] }
  ]
}
```

- `schema` permite migrar escenas viejas cuando cambie el formato.
- Los ids de entidad son estables: las pistas apuntan a ellos, nunca a handles del juego.
- Exportar = descargar este JSON; importar = validarlo contra el esquema antes de guardar.

## 7. Roadmap

Estimación orientativa con una persona a ~15 h/semana. No se pasa de fase sin cumplir su gate.

| Fase | Semanas | Entregables | Gate de salida |
| --- | --- | --- | --- |
| 0 · Base | 1–2 | Recurso y NUI base, free cam y gizmo, spawn y outliner, guardado en MySQL, permisos ACE, bloqueo por escena | Una escena se guarda, se cierra y se recarga igual |
| 1 · Cutscenes | 3–5 | Timeline multipista, keys y easing, pista de cámara, reproducción con letterbox, sync con reloj de red, exports `PlayCutscene`/`StopCutscene` | **MVP:** la cutscene de bienvenida se reproduce bien para 10 jugadores |
| 2 · Ambience | 6–8 | Crowds con presets, clima/hora/timecycle, audio 3D, activación por zona con interruptor y horario, LOD y límites | Un ambience con 10 jugadores dentro sin caída notable de FPS |
| 3 · Pulido | 9–11 | Texto 3D y luces, partículas, grabación REC, set pieces | Versión 1.0 |

## 8. Riesgos

| Riesgo | Impacto | Mitigación |
| --- | --- | --- |
| Multitudes de 100+ peds bajan los FPS | Alto | LOD por distancia, límite por estudio, peds locales congelados + anim, presupuesto en ms por frame visible en el editor |
| Desincronización entre jugadores | Medio | El servidor envía `startAt` en tiempo de red (`GetNetworkTimeAccurate`) y cada cliente calcula `t` |
| Streaming de modelos lento | Medio | Precarga (`RequestModel`, anims, ptfx) con pantalla en negro antes de `t = 0` |
| Conflicto con qb-weathersync | Medio | Pausar la sincronización del jugador dentro de la escena y restaurar al salir |
| Abuso del editor | Alto | ACE `cutscene.editor`, validación en servidor de todo guardado, log a Discord |
| La UI se come el tiempo | Medio | Reutilizar el design system existente (v2.0); timeline + inspector primero |

## 9. Decisiones tomadas

| Decisión | Elección | Qué implica |
| --- | --- | --- |
| Framework NUI | Vue 3 + Vite + Pinia | Stack que ya domina el equipo |
| Timeline | Componente propio en canvas; Vue solo para cabecera y lista de pistas | Control total sobre scrub, snap, keys y clips de audio |
| Disparo de cutscenes | Staff y scripts | `/cutscene` con ACE + exports `PlayCutscene(id, targets)`, `StopCutscene`; evento `dwkambience:finished` |
| Ambiences | Permanentes y de evento, con interruptor | Campos `active` y `schedule`; botón on/off en el gestor; presupuesto más estricto para los permanentes |
| Audio | Archivos dentro del recurso | `web/public/sounds/*.ogg` + manifiesto generado en el build para la paleta Sounds; añadir audio = reiniciar el recurso |
| Edición simultánea | Bloqueo por escena | El servidor guarda en memoria quién edita cada escena; el resto en solo lectura; se libera al cerrar o al desconectarse |
