-- Set pieces: grupos de entidades y sus pistas guardados en scene_assets para reutilizarlos.
-- data = { schema, origin = {x,y,z}, start = ms, entities, tracks } (posiciones absolutas; al insertar
-- la NUI las desplaza al punto de la cámara y al instante actual).

local function fail(code)
    return { ok = false, error = code }
end

local function guard(src)
    if not Permissions.canEdit(src) then return 'forbidden' end
    if not Migrations.ready then return 'db_not_ready' end
end

--- Valida una set piece con Scene.sanitize envolviéndola en una escena mínima.
local function cleanSetPiece(data)
    if type(data) ~= 'table' or type(data.origin) ~= 'table' then return nil, 'bad_set_piece' end
    local scene = Scene.new('cutscene')
    scene.entities, scene.tracks = data.entities, data.tracks
    local clean, err = Scene.sanitize(scene, {
        maxEntities = Config.Studios[Config.DefaultStudio].maxEntities,
        maxCrowd = Config.Ambience.maxPedsPerAmbience,
    })
    if not clean then return nil, err end
    if #clean.entities == 0 then return nil, 'empty_set_piece' end

    local o = data.origin
    for i = 1, 3 do
        if type(o[i]) ~= 'number' or o[i] ~= o[i] or math.abs(o[i]) > 100000 then return nil, 'bad_origin' end
    end
    local start = math.tointeger(tonumber(data.start) or 0) or 0
    return { schema = Scene.SCHEMA, origin = { o[1], o[2], o[3] }, start = math.max(0, start), entities = clean.entities, tracks = clean.tracks }
end

lib.callback.register('dwkambience:setPieces', function(src)
    local err = guard(src)
    if err then return fail(err) end
    local rows = MySQL.query.await("SELECT id, name FROM scene_assets WHERE kind = 'set_piece' ORDER BY name") or {}
    return { ok = true, items = rows }
end)

lib.callback.register('dwkambience:setPieceGet', function(src, id)
    local err = guard(src)
    if err then return fail(err) end
    local row = MySQL.single.await("SELECT data FROM scene_assets WHERE id = ? AND kind = 'set_piece'", { tonumber(id) })
    if not row then return fail('not_found') end
    local data = json.decode(row.data)
    -- Las set pieces se migran como cualquier escena antes de usarse
    local wrapper = Scene.migrate({ schema = data.schema or 1, settings = Scene.new('cutscene').settings, entities = data.entities, tracks = data.tracks })
    if not wrapper then return fail('corrupt_scene') end
    data.entities, data.tracks, data.schema = wrapper.entities, wrapper.tracks, Scene.SCHEMA
    return { ok = true, data = data }
end)

lib.callback.register('dwkambience:setPieceSave', function(src, payload)
    local err = guard(src)
    if err then return fail(err) end
    if type(payload) ~= 'table' or type(payload.name) ~= 'string' then return fail('bad_request') end
    local name = payload.name:match('^%s*(.-)%s*$')
    if #name == 0 or #name > 64 then return fail('bad_name') end

    local data
    data, err = cleanSetPiece(payload.data)
    if not data then return fail(err) end
    local encoded = json.encode(data)
    if #encoded > Config.MaxDataBytes then return fail('too_large') end

    MySQL.query.await([[
        INSERT INTO scene_assets (kind, name, data) VALUES ('set_piece', ?, ?)
        ON DUPLICATE KEY UPDATE data = VALUES(data)
    ]], { name, encoded })
    Log.action(src, 'Set piece guardada', ('%s (%d entidades)'):format(name, #data.entities))
    return { ok = true }
end)

lib.callback.register('dwkambience:setPieceDelete', function(src, id)
    local err = guard(src)
    if err then return fail(err) end
    MySQL.update.await("DELETE FROM scene_assets WHERE id = ? AND kind = 'set_piece'", { tonumber(id) })
    Log.action(src, 'Set piece borrada', ('#%s'):format(tostring(id)))
    return { ok = true }
end)
