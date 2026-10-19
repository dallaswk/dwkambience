# Gate de la fase 1: pruebas in-game

Objetivo: la cutscene de bienvenida (cámara + 3 actores + 1 coche + música) se monta sin tocar Lua
y se reproduce bien para 10 jugadores a la vez.

Preparación: `setr dwkambience_debug 1` en el servidor y un `.ogg` en `web/public/sounds/` (compilar).

## 1. Montaje en el editor (una persona)

- [ ] Crear la cutscene, añadir 3 peds y 1 coche, colocarlos con el gizmo.
- [ ] Mover el playhead y recolocar con Auto key: aparecen keys nuevas; al hacer scrub las entidades se mueven entre ellas.
- [ ] Añadir una animación a un ped con "Añadir a la pista"; al hacer scrub la animación avanza y retrocede con el playhead.
- [ ] Camera view: encuadrar con la free cam, pulsar Key en 3-4 instantes; Play recorre el plano.
- [ ] Probar Spline en las keys de cámara: el movimiento es suave al pasar por las keys.
- [ ] Añadir fundido desde negro al inicio, un subtítulo y la música.
- [ ] Deshacer/rehacer varias ediciones; guardar, cerrar y reabrir: todo igual.
- [ ] Anotar el tiempo total de montaje (criterio: menos de 1 h).

## 2. Reproducción con 10 jugadores

- [ ] `/cutscene <id> all`: todos ven negro, luego la escena; nadie ve modelos cargando.
- [ ] En el overlay de depuración, `late` es 0 o pequeño en todos; si alguien llega tarde, entra en el mismo `t` que los demás.
- [ ] Comparar capturas/vídeos de 2-3 jugadores en el mismo instante (p. ej. el subtítulo): el desfase es imperceptible.
- [ ] La música va en sincronía con la imagen en todos.
- [ ] Clima y hora de la escena durante la cutscene; al acabar vuelven los del servidor (qb-weathersync).
- [ ] Un jugador salta con Retroceso: solo él sale; los demás siguen. `/cutscene <id> all noskip`: no se puede saltar.
- [ ] `/cutscene stop all` a mitad: todos vuelven al juego con su HUD y control.
- [ ] Un jugador se desconecta a mitad: el resto termina bien y el servidor emite `dwkambience:finished` para cada uno.
- [ ] `ensure dwkambience` a mitad de una reproducción: nadie se queda con la cámara o entidades colgadas.
