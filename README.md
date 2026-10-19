# dwkambience

Editor in-game de cutscenes y ambiences para FiveM. Alcance y roadmap en [`docs/PLAN.md`](docs/PLAN.md).

## Instalación

1. Dependencias: `ox_lib`, `oxmysql` (QB-Core opcional, para permisos por grupo).
2. Ejecuta `sql/001_init.sql` en la base de datos.
3. Compila la NUI: `cd web && npm install && npm run build`.
4. Permisos en `server.cfg`:
   ```
   add_ace group.admin cutscene.editor allow
   ensure dwkambience
   ```
5. In-game: `/scenes`.

## Controles del editor

| Acción | Control |
| --- | --- |
| Volar la cámara | Mantener botón derecho sobre el viewport + WASD, Q/E bajar/subir, Shift rápido, Ctrl lento |
| Seleccionar | Clic izquierdo sobre la entidad o en el outliner |
| Mover / rotar | Botones Move / Rotate del inspector; W/R cambian de modo, Enter o Esc para terminar |
| Guardar | Ctrl+S |
| Borrar selección | Supr |
| Encuadrar selección | F |
