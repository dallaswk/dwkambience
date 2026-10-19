-- Ambiences en vivo: índice ligero para todos los clientes y datos completos bajo demanda.
Ambience = {}

local index = {} -- [id] = { id, name, active, schedule, trigger, version }
local cache = {} -- [id] = { version, data }

local function list()
    local out = {}
    for _, entry in pairs(index) do out[#out + 1] = entry end
    return out
end

local function broadcast()
    TriggerClientEvent('dwkambience:ambienceIndex', -1, list())
end

local function entryFrom(row)
    local data = Scene.migrate(json.decode(row.data))
    -- Sin zona no hay forma de activarlo: no entra en el índice
    if not data or not data.settings.trigger then return nil end
    data.settings.active = row.active == 1 or row.active == true
    local version = tostring(row.updated_at)
    return {
        id = row.id,
        name = row.name,
        active = data.settings.active,
        schedule = data.settings.schedule,
        trigger = data.settings.trigger,
        version = version,
    }, data
end

--- Vuelve a leer un ambience de la base de datos (tras guardar o activar) y avisa a los clientes.
function Ambience.refresh(id)
    local row = MySQL.single.await('SELECT id, name, type, active, data, updated_at FROM scenes WHERE id = ?', { id })
    index[id], cache[id] = nil, nil
    if row and row.type == 'ambience' then
        local entry, data = entryFrom(row)
        if entry then
            index[id] = entry
            cache[id] = { version = entry.version, data = data }
        end
    end
    broadcast()
    NetEnts.reset(id)
end

function Ambience.remove(id)
    index[id], cache[id] = nil, nil
    broadcast()
    NetEnts.reset(id)
end

--- Entrada del índice y datos de un ambience con zona, o nil
function Ambience.get(id)
    local entry = index[id]
    local cached = cache[id]
    return entry, cached and cached.data
end

CreateThread(function()
    while not Migrations.ready and not Migrations.failed do Wait(250) end
    if not Migrations.ready then return end
    local rows = MySQL.query.await("SELECT id, name, type, active, data, updated_at FROM scenes WHERE type = 'ambience'") or {}
    for _, row in ipairs(rows) do
        local entry, data = entryFrom(row)
        if entry then
            index[row.id] = entry
            cache[row.id] = { version = entry.version, data = data }
        end
    end
    print(('[dwkambience] %d ambience(s) con zona cargados'):format(#list()))
    broadcast()
end)

lib.callback.register('dwkambience:ambienceIndex', function()
    return list()
end)

-- Cualquier jugador puede pedir los datos de un ambience activo (los necesita para verlo)
lib.callback.register('dwkambience:ambienceData', function(_, id)
    local entry = index[tonumber(id)]
    if not entry or not entry.active then return nil end
    local cached = cache[entry.id]
    return cached and { version = cached.version, data = cached.data } or nil
end)

lib.callback.register('dwkambience:setActive', function(src, id, active)
    if not Permissions.canEdit(src) then return { ok = false, error = 'forbidden' } end
    if not Migrations.ready then return { ok = false, error = 'db_not_ready' } end
    id = math.tointeger(tonumber(id))
    local row = id and MySQL.single.await('SELECT name, type, data FROM scenes WHERE id = ?', { id })
    if not row then return { ok = false, error = 'not_found' } end
    if row.type ~= 'ambience' then return { ok = false, error = 'not_ambience' } end

    local data = Scene.migrate(json.decode(row.data))
    if not data then return { ok = false, error = 'corrupt_scene' } end
    data.settings.active = active == true
    MySQL.update.await('UPDATE scenes SET active = ?, data = ? WHERE id = ?', { active and 1 or 0, json.encode(data), id })

    Log.action(src, active and 'Ambience activado' or 'Ambience desactivado', ('#%d %s'):format(id, row.name))
    Ambience.refresh(id)
    return { ok = true, active = active == true }
end)
