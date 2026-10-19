-- CRUD de escenas. Todo pasa por Permissions.canEdit y el guardado por Scene.sanitize.

local LIST_COLUMNS = 'id, name, type, group_name, studio, duration_ms, active, entity_count, key_count, updated_by, updated_at'

local function fail(code)
    return { ok = false, error = code }
end

local function toBool(v)
    return v == true or v == 1
end

local function rowToMeta(row)
    return {
        id = row.id,
        name = row.name,
        type = row.type,
        group = row.group_name,
        studio = row.studio,
        durationMs = row.duration_ms,
        active = toBool(row.active),
        entityCount = row.entity_count,
        keyCount = row.key_count,
        updatedBy = row.updated_by,
        updatedAt = row.updated_at,
        lockedBy = Locks.ownerName(row.id),
    }
end

local function trim(s)
    return type(s) == 'string' and s:match('^%s*(.-)%s*$') or nil
end

--- Nombre obligatorio (1-64) y grupo opcional (0-64). Devuelve name, group o nil, error.
local function cleanMeta(meta)
    if type(meta) ~= 'table' then return nil, nil, 'bad_meta' end
    local name = trim(meta.name)
    if not name or #name == 0 or #name > 64 then return nil, nil, 'bad_name' end
    local group = trim(meta.group)
    if group and #group > 64 then return nil, nil, 'bad_group' end
    if group == '' then group = nil end
    return name, group
end

local function studioLimits(studioId, sceneType)
    local studio = Config.Studios[studioId] or Config.Studios[Config.DefaultStudio]
    local ambience = sceneType == 'ambience'
    return {
        maxEntities = studio.maxEntities,
        maxTracks = Config.Limits.maxTracks,
        maxKeysPerTrack = Config.Limits.maxKeysPerTrack,
        maxDurationMs = Config.Limits.maxDurationMs,
        maxCrowd = Config.Ambience.maxPedsPerAmbience,
        maxPeds = ambience and Config.Ambience.maxPedsPerAmbience or nil,
        maxNetworked = ambience and (studio.maxNetworked or 0) or 0, -- las cutscenes son siempre locales
    }
end

-- Callback que necesita la base de datos: espera a que las migraciones estén aplicadas
local function register(name, handler)
    lib.callback.register(name, function(src, ...)
        if not Migrations.ready then return fail('db_not_ready') end
        return handler(src, ...)
    end)
end

local function sceneId(value)
    local id = math.tointeger(tonumber(value))
    return id and id > 0 and id or nil
end

--- Abre una escena para el jugador: toma el bloqueo si está libre, si no queda en solo lectura.
local function openFor(src, id)
    local row = MySQL.single.await(('SELECT %s, data FROM scenes WHERE id = ?'):format(LIST_COLUMNS), { id })
    if not row then return fail('not_found') end

    local data, err = Scene.migrate(json.decode(row.data))
    if not data then
        print(('[dwkambience] escena %d ilegible: %s'):format(id, err))
        return fail('corrupt_scene')
    end

    local locked, owner = Locks.acquire(id, src)
    local meta = rowToMeta(row)

    return {
        ok = true,
        meta = meta,
        data = data,
        readOnly = not locked,
        lockedBy = not locked and GetPlayerName(owner) or nil,
    }
end

register('dwkambience:list', function(src)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    local rows = MySQL.query.await(('SELECT %s FROM scenes ORDER BY group_name, name'):format(LIST_COLUMNS))
    local list = {}
    for i, row in ipairs(rows or {}) do list[i] = rowToMeta(row) end
    return { ok = true, scenes = list }
end)

register('dwkambience:create', function(src, payload)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    if type(payload) ~= 'table' or not Scene.TYPES[payload.type] then return fail('bad_type') end
    local name, group, err = cleanMeta(payload)
    if not name then return fail(err) end

    local data = Scene.new(payload.type)
    -- Un ambience nace con su zona en el punto donde está la cámara del editor
    if payload.type == 'ambience' then
        local c = payload.center
        if type(c) == 'table' and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
            data.settings.trigger = {
                center = { tonumber(c[1]) + 0.0, tonumber(c[2]) + 0.0, tonumber(c[3]) + 0.0 },
                enter = Config.Ambience.defaultEnter,
                exit = Config.Ambience.defaultExit,
            }
        end
    end
    local stats = Scene.stats(data)
    local id = MySQL.insert.await([[
        INSERT INTO scenes (name, type, group_name, studio, duration_ms, data, schema_version, updated_by)
        VALUES (?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?)
    ]], { name, payload.type, group or '', Config.DefaultStudio, stats.durationMs, json.encode(data), Scene.SCHEMA, Log.who(src) })
    if not id then return fail('db_error') end

    Log.action(src, 'Escena creada', ('#%d %s (%s)'):format(id, name, payload.type))
    return openFor(src, id)
end)

register('dwkambience:open', function(src, id)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    id = sceneId(id)
    if not id then return fail('bad_id') end
    return openFor(src, id)
end)

register('dwkambience:save', function(src, payload)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    if type(payload) ~= 'table' then return fail('bad_request') end
    local id = sceneId(payload.id)
    if not id then return fail('bad_id') end
    if not Locks.holds(id, src) then return fail('not_locked') end

    local name, group, err = cleanMeta(payload.meta)
    if not name then return fail(err) end

    local row = MySQL.single.await('SELECT studio, type, active FROM scenes WHERE id = ?', { id })
    if not row then return fail('not_found') end

    local data
    data, err = Scene.sanitize(payload.data, studioLimits(row.studio, row.type))
    if not data then return fail((err == 'too_many_entities' or err == 'too_many_peds' or err == 'too_many_networked') and err or ('invalid: ' .. err)) end
    -- El interruptor on/off solo se cambia con dwkambience:setActive; el guardado conserva el valor actual
    data.settings.active = row.active == 1 or row.active == true

    local encoded = json.encode(data)
    if #encoded > Config.MaxDataBytes then return fail('too_large') end

    local stats = Scene.stats(data)
    local who = Log.who(src)
    local schedule = data.settings.schedule and json.encode(data.settings.schedule) or ''
    local rev = (MySQL.scalar.await('SELECT MAX(rev) FROM scene_revisions WHERE scene_id = ?', { id }) or 0) + 1

    local saved = MySQL.transaction.await({
        {
            query = [[
                UPDATE scenes SET name = ?, group_name = NULLIF(?, ''), duration_ms = ?, active = ?, schedule = NULLIF(?, ''),
                    entity_count = ?, key_count = ?, data = ?, schema_version = ?, updated_by = ?
                WHERE id = ?
            ]],
            values = { name, group or '', stats.durationMs, data.settings.active and 1 or 0, schedule,
                stats.entities, stats.keys, encoded, Scene.SCHEMA, who, id },
        },
        {
            query = 'INSERT INTO scene_revisions (scene_id, rev, data, created_by) VALUES (?, ?, ?, ?)',
            values = { id, rev, encoded, who },
        },
        {
            query = 'DELETE FROM scene_revisions WHERE scene_id = ? AND rev <= ?',
            values = { id, rev - Config.MaxRevisions },
        },
    })
    if not saved then return fail('db_error') end

    Log.action(src, 'Escena guardada', ('#%d %s rev %d (%d entidades, %d keys)'):format(id, name, rev, stats.entities, stats.keys))
    if row.type == 'ambience' then Ambience.refresh(id) end

    local updated = MySQL.single.await(('SELECT %s FROM scenes WHERE id = ?'):format(LIST_COLUMNS), { id })
    return { ok = true, meta = rowToMeta(updated), rev = rev }
end)

lib.callback.register('dwkambience:close', function(src, id)
    id = sceneId(id)
    if id then Locks.release(id, src) end
    return { ok = true }
end)

register('dwkambience:delete', function(src, id)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    id = sceneId(id)
    if not id then return fail('bad_id') end
    if Locks.ownerName(id) and not Locks.holds(id, src) then return fail('locked') end

    local row = MySQL.single.await('SELECT name FROM scenes WHERE id = ?', { id })
    if not row then return fail('not_found') end

    MySQL.update.await('DELETE FROM scenes WHERE id = ?', { id })
    Locks.release(id, src)
    Ambience.remove(id)
    Log.action(src, 'Escena borrada', ('#%d %s'):format(id, row.name))
    return { ok = true }
end)

-- Exportar / importar ---------------------------------------------------------------

register('dwkambience:export', function(src, id)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    id = sceneId(id)
    local row = id and MySQL.single.await('SELECT name, type, group_name, data FROM scenes WHERE id = ?', { id })
    if not row then return fail('not_found') end
    local data = Scene.migrate(json.decode(row.data))
    if not data then return fail('corrupt_scene') end
    Log.action(src, 'Escena exportada', ('#%d %s'):format(id, row.name))
    return { ok = true, name = row.name, type = row.type, group = row.group_name, data = data }
end)

-- Crea una escena nueva a partir de un JSON exportado (de este u otro servidor). Siempre se migra
-- y se valida con el esquema; un ambience importado llega apagado.
register('dwkambience:import', function(src, payload)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    if type(payload) ~= 'table' or not Scene.TYPES[payload.type] then return fail('bad_type') end
    local name, group, err = cleanMeta(payload)
    if not name then return fail(err) end

    local data
    data, err = Scene.migrate(payload.data)
    if not data then return fail('invalid: ' .. tostring(err)) end
    data, err = Scene.sanitize(data, studioLimits(Config.DefaultStudio, payload.type))
    if not data then return fail((err == 'too_many_entities' or err == 'too_many_peds') and err or ('invalid: ' .. err)) end
    data.settings.active = false

    local encoded = json.encode(data)
    if #encoded > Config.MaxDataBytes then return fail('too_large') end
    local stats = Scene.stats(data)
    local id = MySQL.insert.await([[
        INSERT INTO scenes (name, type, group_name, studio, duration_ms, entity_count, key_count, data, schema_version, updated_by)
        VALUES (?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?)
    ]], { name, payload.type, group or '', Config.DefaultStudio, stats.durationMs, stats.entities, stats.keys, encoded, Scene.SCHEMA, Log.who(src) })
    if not id then return fail('db_error') end

    Log.action(src, 'Escena importada', ('#%d %s (%s, %d entidades)'):format(id, name, payload.type, stats.entities))
    if payload.type == 'ambience' then Ambience.refresh(id) end
    return openFor(src, id)
end)

-- Historial de revisiones ---------------------------------------------------------------

register('dwkambience:revisions', function(src, id)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    id = sceneId(id)
    if not id then return fail('bad_id') end
    local rows = MySQL.query.await(
        'SELECT rev, created_by, created_at, CHAR_LENGTH(data) AS size FROM scene_revisions WHERE scene_id = ? ORDER BY rev DESC',
        { id }) or {}
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = { rev = row.rev, createdBy = row.created_by, createdAt = row.created_at, size = row.size }
    end
    return { ok = true, revisions = list }
end)

-- Datos de una revisión, migrados al esquema actual. Restaurar es cosa del editor: los carga como
-- cambios sin guardar, así que el bloqueo y la validación del guardado normal siguen aplicando.
register('dwkambience:revisionGet', function(src, id, rev)
    if not Permissions.canEdit(src) then return fail('forbidden') end
    id, rev = sceneId(id), math.tointeger(tonumber(rev))
    if not id or not rev then return fail('bad_id') end
    local row = MySQL.single.await('SELECT data FROM scene_revisions WHERE scene_id = ? AND rev = ?', { id, rev })
    if not row then return fail('not_found') end
    local data = Scene.migrate(json.decode(row.data))
    if not data then return fail('corrupt_scene') end
    return { ok = true, data = data }
end)
