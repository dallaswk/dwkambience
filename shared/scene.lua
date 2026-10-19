-- Esquema de escena: valores por defecto, migraciones, saneado y utilidades puras.
-- Sin natives ni globals de FiveM, para poder probarlo con un intérprete de Lua normal.

Scene = Scene or {}

Scene.SCHEMA = 1

Scene.TYPES = { cutscene = true, ambience = true }
Scene.KINDS = { ped = true, vehicle = true, prop = true, sound = true, crowd = true }
Scene.CHANNELS = { transform = true, camera = true, audio = true }
Scene.EASES = { linear = true, ['in'] = true, out = true, inOut = true }

Scene.WEATHERS = {
    CLEAR = true, EXTRASUNNY = true, CLOUDS = true, OVERCAST = true, RAIN = true, CLEARING = true,
    THUNDER = true, SMOG = true, FOGGY = true, XMAS = true, SNOW = true, SNOWLIGHT = true,
    BLIZZARD = true, HALLOWEEN = true, NEUTRAL = true,
}

local DEFAULT_LIMITS = {
    maxEntities = 300,
    maxTracks = 1000,
    maxKeysPerTrack = 2000,
    maxDurationMs = 30 * 60 * 1000,
}

local ID_PATTERN = '^[%w_%-]+$'
local MODEL_PATTERN = '^[%w_%-]+$'
local TIME_PATTERN = '^(%d%d):(%d%d)$'

local MAX_PROPS = 32
local MAX_PROP_ARRAY = 16
local MAX_STRING = 128

--- Escena vacía para un tipo.
function Scene.new(sceneType)
    local isAmbience = sceneType == 'ambience'
    return {
        schema = Scene.SCHEMA,
        settings = {
            weather = 'CLEAR',
            time = '12:00',
            duration = isAmbience and 60000 or 10000,
            output = { letterbox = not isAmbience, hud = isAmbience },
            loop = isAmbience,
            active = false,
            schedule = nil,
            trigger = nil,
        },
        entities = {},
        tracks = {},
    }
end

-- Migraciones: Scene.MIGRATIONS[n] convierte un documento de schema n a n + 1.
Scene.MIGRATIONS = {}

--- Lleva un documento al schema actual. Devuelve data o nil, error.
function Scene.migrate(data)
    if type(data) ~= 'table' then return nil, 'data_not_table' end
    local version = data.schema
    if math.type(version) ~= 'integer' or version < 1 then return nil, 'invalid_schema' end
    if version > Scene.SCHEMA then return nil, 'schema_too_new' end

    while version < Scene.SCHEMA do
        local step = Scene.MIGRATIONS[version]
        if not step then return nil, ('missing_migration_%d'):format(version) end
        data = step(data)
        version = version + 1
        data.schema = version
    end

    return data
end

---------------------------------------------------------------------------
-- Saneado: construye una copia solo con campos conocidos y tipos válidos.
---------------------------------------------------------------------------

local function isFinite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function isArray(t)
    if type(t) ~= 'table' then return false end
    local n = #t
    for k in pairs(t) do
        if math.type(k) ~= 'integer' or k < 1 or k > n then return false end
    end
    return true
end

local function cleanString(s, maxLen, pattern)
    if type(s) ~= 'string' or #s == 0 or #s > maxLen then return nil end
    if pattern and not s:match(pattern) then return nil end
    return s
end

local function cleanVec3(v)
    if not isArray(v) or #v ~= 3 then return nil end
    for i = 1, 3 do
        if not isFinite(v[i]) then return nil end
    end
    return { v[1] + 0.0, v[2] + 0.0, v[3] + 0.0 }
end

local function cleanTime(s)
    if type(s) ~= 'string' then return nil end
    local h, m = s:match(TIME_PATTERN)
    if not h or tonumber(h) > 23 or tonumber(m) > 59 then return nil end
    return s
end

local function cleanPropValue(v)
    local tv = type(v)
    if tv == 'boolean' then return v end
    if tv == 'number' then return isFinite(v) and v or nil end
    if tv == 'string' then return #v <= MAX_STRING and v or nil end
    if tv == 'table' then
        -- Mapa plano de primitivas (p. ej. anim = { dict, clip }) o array corto de primitivas
        local out, count = {}, 0
        for k, item in pairs(v) do
            count = count + 1
            if count > MAX_PROP_ARRAY then return nil end
            local okKey = (math.type(k) == 'integer' and k >= 1) or (type(k) == 'string' and #k <= 32)
            local ti = type(item)
            if not okKey or not (ti == 'boolean' or ti == 'string' or isFinite(item)) then return nil end
            if ti == 'string' and #item > MAX_STRING then return nil end
            out[k] = item
        end
        return out
    end
    return nil
end

local function cleanProps(props, path)
    if props == nil then return {} end
    if type(props) ~= 'table' then return nil, path .. ': props' end
    local out, count = {}, 0
    for k, v in pairs(props) do
        count = count + 1
        if count > MAX_PROPS then return nil, path .. ': too_many_props' end
        if type(k) ~= 'string' or #k > 32 then return nil, path .. ': prop_key' end
        local clean = cleanPropValue(v)
        if clean == nil then return nil, ('%s: prop %s'):format(path, k) end
        out[k] = clean
    end
    return out
end

local function cleanSettings(s)
    if type(s) ~= 'table' then return nil, 'settings' end
    local out = {}

    out.weather = Scene.WEATHERS[s.weather] and s.weather or nil
    if not out.weather then return nil, 'settings.weather' end

    out.time = cleanTime(s.time)
    if not out.time then return nil, 'settings.time' end

    if math.type(s.duration) ~= 'integer' and not (isFinite(s.duration) and s.duration % 1 == 0) then
        return nil, 'settings.duration'
    end
    out.duration = math.tointeger(s.duration)
    if out.duration < 0 then return nil, 'settings.duration' end

    if type(s.output) ~= 'table' or type(s.output.letterbox) ~= 'boolean' or type(s.output.hud) ~= 'boolean' then
        return nil, 'settings.output'
    end
    out.output = { letterbox = s.output.letterbox, hud = s.output.hud }

    if type(s.loop) ~= 'boolean' then return nil, 'settings.loop' end
    out.loop = s.loop
    if type(s.active) ~= 'boolean' then return nil, 'settings.active' end
    out.active = s.active

    if s.schedule ~= nil then
        local from, to = cleanTime(type(s.schedule) == 'table' and s.schedule.from), cleanTime(type(s.schedule) == 'table' and s.schedule.to)
        if not from or not to then return nil, 'settings.schedule' end
        out.schedule = { from = from, to = to }
    end

    if s.trigger ~= nil then
        local t = s.trigger
        local center = type(t) == 'table' and cleanVec3(t.center)
        if not center or not isFinite(t.enter) or not isFinite(t.exit) or t.enter <= 0 or t.exit < t.enter then
            return nil, 'settings.trigger'
        end
        out.trigger = { center = center, enter = t.enter, exit = t.exit }
    end

    return out
end

local function cleanEntity(e, i)
    local path = ('entities[%d]'):format(i)
    if type(e) ~= 'table' then return nil, path end
    local id = cleanString(e.id, 32, ID_PATTERN)
    if not id or id == 'camera' then return nil, path .. '.id' end
    if not Scene.KINDS[e.kind] then return nil, path .. '.kind' end
    local model = cleanString(e.model, 64, MODEL_PATTERN)
    if not model then return nil, path .. '.model' end
    local label = cleanString(e.label, 64)
    if not label then return nil, path .. '.label' end
    local props, err = cleanProps(e.props, path)
    if not props then return nil, err end
    if e.networked ~= nil and type(e.networked) ~= 'boolean' then return nil, path .. '.networked' end

    return {
        id = id,
        kind = e.kind,
        model = model,
        label = label,
        props = props,
        networked = e.networked == true,
    }
end

local function cleanKey(k, channel, limits, path)
    if type(k) ~= 'table' then return nil, path end
    if math.type(k.t) ~= 'integer' and not (isFinite(k.t) and k.t % 1 == 0) then return nil, path .. '.t' end
    local t = math.tointeger(k.t)
    if t < 0 or t > limits.maxDurationMs then return nil, path .. '.t' end

    local out = { t = t }
    out.pos = cleanVec3(k.pos)
    out.rot = cleanVec3(k.rot)
    if not out.pos or not out.rot then return nil, path .. '.pos/rot' end

    if k.ease ~= nil then
        if not Scene.EASES[k.ease] then return nil, path .. '.ease' end
        out.ease = k.ease
    end

    if channel == 'camera' and k.fov ~= nil then
        if not isFinite(k.fov) or k.fov < 1 or k.fov > 130 then return nil, path .. '.fov' end
        out.fov = k.fov
    end

    return out
end

local function cleanClip(c, limits, path)
    if type(c) ~= 'table' then return nil, path end
    if not isFinite(c.start) or c.start < 0 or c.start > limits.maxDurationMs then return nil, path .. '.start' end
    local asset = cleanString(c.asset, 64, ID_PATTERN)
    if not asset then return nil, path .. '.asset' end
    local volume = c.volume == nil and 1.0 or c.volume
    if not isFinite(volume) or volume < 0 or volume > 1 then return nil, path .. '.volume' end
    local fadeIn = c.fadeIn == nil and 0 or c.fadeIn
    if not isFinite(fadeIn) or fadeIn < 0 then return nil, path .. '.fadeIn' end
    if c.loop ~= nil and type(c.loop) ~= 'boolean' then return nil, path .. '.loop' end
    return { start = math.floor(c.start), asset = asset, volume = volume, loop = c.loop == true, fadeIn = math.floor(fadeIn) }
end

local function cleanTrack(tr, i, entityIds, limits)
    local path = ('tracks[%d]'):format(i)
    if type(tr) ~= 'table' then return nil, path end
    local id = cleanString(tr.id, 48, ID_PATTERN)
    if not id then return nil, path .. '.id' end
    if not Scene.CHANNELS[tr.channel] then return nil, path .. '.channel' end
    if tr.channel == 'camera' then
        if tr.target ~= 'camera' then return nil, path .. '.target' end
    elseif not entityIds[tr.target] then
        return nil, path .. '.target'
    end

    local out = { id = id, target = tr.target, channel = tr.channel }

    if tr.channel == 'audio' then
        if tr.clips ~= nil and not isArray(tr.clips) then return nil, path .. '.clips' end
        out.clips = {}
        for j, c in ipairs(tr.clips or {}) do
            if j > limits.maxKeysPerTrack then return nil, path .. '.too_many_clips' end
            local clip, err = cleanClip(c, limits, ('%s.clips[%d]'):format(path, j))
            if not clip then return nil, err end
            out.clips[j] = clip
        end
        table.sort(out.clips, function(a, b) return a.start < b.start end)
    else
        if tr.keys ~= nil and not isArray(tr.keys) then return nil, path .. '.keys' end
        out.keys = {}
        local seen = {}
        for j, k in ipairs(tr.keys or {}) do
            if j > limits.maxKeysPerTrack then return nil, path .. '.too_many_keys' end
            local key, err = cleanKey(k, tr.channel, limits, ('%s.keys[%d]'):format(path, j))
            if not key then return nil, err end
            if seen[key.t] then return nil, ('%s.keys[%d].t duplicated'):format(path, j) end
            seen[key.t] = true
            out.keys[j] = key
        end
        table.sort(out.keys, function(a, b) return a.t < b.t end)
    end

    return out
end

--- Valida un documento y devuelve una copia saneada, o nil, error.
--- limits: { maxEntities, maxTracks, maxKeysPerTrack, maxDurationMs } (opcional).
function Scene.sanitize(data, limits)
    limits = limits or DEFAULT_LIMITS
    for k, v in pairs(DEFAULT_LIMITS) do
        if limits[k] == nil then limits[k] = v end
    end

    if type(data) ~= 'table' then return nil, 'data' end
    if data.schema ~= Scene.SCHEMA then return nil, 'schema' end

    local settings, err = cleanSettings(data.settings)
    if not settings then return nil, err end

    local entities, entityIds = {}, {}
    if data.entities ~= nil and not isArray(data.entities) then return nil, 'entities' end
    for i, e in ipairs(data.entities or {}) do
        if i > limits.maxEntities then return nil, 'too_many_entities' end
        local clean
        clean, err = cleanEntity(e, i)
        if not clean then return nil, err end
        if entityIds[clean.id] then return nil, ('entities[%d].id duplicated'):format(i) end
        entityIds[clean.id] = true
        entities[i] = clean
    end

    local tracks, trackIds = {}, {}
    if data.tracks ~= nil and not isArray(data.tracks) then return nil, 'tracks' end
    for i, tr in ipairs(data.tracks or {}) do
        if i > limits.maxTracks then return nil, 'too_many_tracks' end
        local clean
        clean, err = cleanTrack(tr, i, entityIds, limits)
        if not clean then return nil, err end
        if trackIds[clean.id] then return nil, ('tracks[%d].id duplicated'):format(i) end
        trackIds[clean.id] = true
        tracks[i] = clean
    end

    return {
        schema = Scene.SCHEMA,
        settings = settings,
        entities = entities,
        tracks = tracks,
    }
end

---------------------------------------------------------------------------
-- Consultas
---------------------------------------------------------------------------

--- Pista de un canal para un target, o nil.
function Scene.findTrack(data, target, channel)
    for _, tr in ipairs(data.tracks or {}) do
        if tr.target == target and tr.channel == channel then return tr end
    end
end

--- Transform base de una entidad: la key de transform con menor t. Devuelve pos, rot o nil.
function Scene.baseTransform(data, entityId)
    local tr = Scene.findTrack(data, entityId, 'transform')
    local first = tr and tr.keys and tr.keys[1]
    if not first then return nil end
    for _, k in ipairs(tr.keys) do
        if k.t < first.t then first = k end
    end
    return first.pos, first.rot
end

--- Recuento para las columnas de índice: entidades, pistas, keys y duración (ms).
function Scene.stats(data)
    local keys, lastT = 0, 0
    for _, tr in ipairs(data.tracks or {}) do
        for _, k in ipairs(tr.keys or {}) do
            keys = keys + 1
            if k.t > lastT then lastT = k.t end
        end
        for _, c in ipairs(tr.clips or {}) do
            keys = keys + 1
            if c.start > lastT then lastT = c.start end
        end
    end
    local duration = data.settings and data.settings.duration or 0
    return {
        entities = #(data.entities or {}),
        tracks = #(data.tracks or {}),
        keys = keys,
        durationMs = math.max(duration, lastT),
    }
end

return Scene
