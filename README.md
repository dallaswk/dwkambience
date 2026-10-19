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
