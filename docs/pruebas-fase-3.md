# Gate de la fase 3 (versión 1.0): pruebas in-game

Objetivo: las funciones de pulido funcionan en editor, cutscenes y ambiences, y las checklists de las
fases 0, 1 y 2 se repiten sin regresiones.

## 1. Texto 3D, luces y partículas

- [ ] Texto: cambia contenido, color, tamaño y fuente en vivo; sin "visible desde detrás" desaparece al rodearlo.
- [ ] El texto mantiene un tamaño coherente al acercarse y alejarse.
- [ ] Luz puntual y foco: el foco apunta hacia donde mira su rotación; con sombras proyecta sombra.
- [ ] Con más de 16 luces cerca solo se dibujan las 16 más cercanas, sin parpadeos fuertes.
- [ ] Partículas del catálogo: arrancan, se apagan al alejarse más de 150 m y vuelven al acercarse.
- [ ] Revisar cada efecto de `Config.PtfxCatalog`; quitar o corregir los que no existan.
- [ ] Una pista de transform mueve también luces, textos y partículas.

## 2. Visibilidad

- [ ] "Ocultar desde aquí" a mitad del timeline: visible antes, oculto después; la pista aparece en el timeline.
- [ ] Funciona en actores, coches, props, textos, luces y partículas, en el editor y en la reproducción.

## 3. Grabación en vivo

- [ ] Grabar un actor caminando: al terminar vuelves a tu sitio y la trayectoria queda en keys; Play la reproduce.
- [ ] Grabar un coche conduciendo (subido a un coche); sin vehículo avisa "Súbete a un vehículo".
- [ ] El resto de la escena se mueve a la vez mientras grabas.
- [ ] Deshacer quita la grabación.
- [ ] Ajustar `Config.Recording.epsilon` si quedan demasiadas o muy pocas keys.

## 4. Set pieces

- [ ] Seleccionar varias entidades con Ctrl+clic y guardarlas como set piece.
- [ ] Insertarla en otra escena: aparece donde mira la cámara, con sus pistas desplazadas al instante actual.
- [ ] Guardar con un nombre existente la sobrescribe; borrarla no afecta a escenas que ya la usaron.

## 5. Regresión y limpieza

- [ ] Repetir `docs/pruebas-fase-1.md` y `docs/pruebas-fase-2.md`.
- [ ] `ensure dwkambience` durante una grabación, una cutscene y dentro de un ambience: nada queda colgado
      (luces, partículas, cámara, jugador congelado o fuera de su sitio).
