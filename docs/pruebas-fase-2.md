# Gate de la fase 2: pruebas in-game

Objetivo: un ambience con 10 jugadores dentro sin caída notable de FPS.

Preparación: `setr dwkambience_debug 1` (overlay con ambiences, peds y ms/frame) y al menos un `.ogg`
en `web/public/sounds/` (compilar).

## 1. Montaje en el editor

- [ ] Crear un ambience: la zona aparece dibujada donde mira la cámara; ajustar radios y centro.
- [ ] Añadir una multitud (preset Playa), colocar 3-4 puntos con "Colocar con clic": la gente aparece repartida.
- [ ] Regenerar la semilla cambia la colocación; deshacer la devuelve.
- [ ] Orientación "Hacia un punto": todos miran a donde apuntaba la cámara.
- [ ] Multitud personalizada con modelos y escenario propios.
- [ ] Emisor de sonido: al mover la cámara alrededor se oye posicional (izquierda/derecha, distancia).
- [ ] Timecycle (p. ej. `MP_Bull_tost`) con "Previsualizar clima y hora" del menú Mundo.
- [ ] El contador de peds no deja pasar de 60; el servidor rechaza guardar por encima.
- [ ] Guardar y activar con el interruptor.

## 2. En vivo con 10 jugadores

- [ ] Al entrar en el radio de entrada aparece todo; al salir del radio de salida se limpia (sin parpadeo en el borde).
- [ ] Todos ven la misma gente en los mismos sitios y los coches con pistas en el mismo punto del bucle.
- [ ] Clima, hora y timecycle solo para quien está dentro; al salir vuelven los del servidor.
- [ ] El sonido 3D se oye desde dentro y se apaga al salir.
- [ ] Con el overlay: anotar ms/frame fuera y dentro del ambience (criterio: sin caída notable) y que peds ≤ 100.
- [ ] Apagar el interruptor con gente dentro: desaparece para todos en unos segundos.
- [ ] Horario: con una franja que excluya la hora actual no aparece; al cambiar la hora del servidor, aparece/desaparece.
- [ ] Guardar cambios en el editor mientras hay gente dentro: se recarga con la versión nueva.
- [ ] Abrir el editor dentro de un ambience: el ambience en vivo se aparta y vuelve al cerrar.
- [ ] Lanzar una cutscene dentro del ambience: manda el clima de la cutscene y al acabar vuelve el del ambience.
- [ ] `ensure dwkambience` con gente dentro: no quedan peds, sonido ni timecycle colgados.
