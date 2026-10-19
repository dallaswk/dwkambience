-- Esquema de escena: valores por defecto, migraciones, saneado y utilidades puras.
-- Sin natives ni globals de FiveM, para poder probarlo con un intérprete de Lua normal.

Scene = Scene or {}

Scene.SCHEMA = 4

Scene.TYPES = { cutscene = true, ambience = true }
Scene.KINDS = { ped = true, vehicle = true, prop = true, sound = true, crowd = true, text = true, light = true, ptfx = true }
Scene.CHANNELS = { transform = true, anim = true, camera = true, audio = true, event = true, visibility = true }
Scene.EASES = { linear = true, ['in'] = true, out = true, inOut = true, spline = true }
Scene.EVENT_TYPES = { fade = true, subtitle = true, trigger = true }
Scene.FACINGS = { random = true, along = true, point = true }
Scene.LIGHT_TYPES = { point = true, spot = true }

-- Tipos con entidad de juego (necesitan modelo); sound y crowd se definen por sus propios campos
Scene.GAME_KINDS = { ped = true, vehicle = true, prop = true }

-- Targets reservados que no son entidades: no se pueden usar como id de entidad
Scene.RESERVED_TARGETS = { camera = true, events = true, music = true }

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
    maxCrowd = 60,
    maxPeds = nil, -- límite de peds (actores + multitudes); el servidor lo fija para los ambiences
}

local ID_PATTERN = '^[%w_%-]+$'
local ANIM_DICT_PATTERN = '^[%w_@/%-%.]+$'
local ANIM_CLIP_PATTERN = '^[%w_%-%.]+$'
local MODEL_PATTERN = '^[%w_%-]+$'
local TIME_PATTERN = '^(%d%d):(%d%d)$'

local MAX_PROPS = 32
local MAX_CROWD_POINTS = 32
local MAX_CROWD_MODELS = 16
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
Scene.MIGRATIONS = {
    -- 1 -> 2: añade canales anim y event, ease 'spline' y el target 'music'. Los documentos v1 siguen siendo válidos.
    [1] = function(data) return data end,
    -- 2 -> 3: campos crowd y sound en entidades, settings.timecycle y modelo opcional en sound/crowd.
    [2] = function(data) return data end,
    -- 3 -> 4: tipos text, light y ptfx, y el canal visibility.
    [3] = function(data) return data end,
}

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

    if s.timecycle ~= nil then
        local tc = s.timecycle
        local name = type(tc) == 'table' and cleanString(tc.name, 64, ID_PATTERN)
        if not name or not isFinite(tc.strength) or tc.strength < 0 or tc.strength > 1 then return nil, 'settings.timecycle' end
        out.timecycle = { name = name, strength = tc.strength }
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

local function cleanCrowd(c, limits, path)
    if type(c) ~= 'table' then return nil, path end
    local out = {}
    out.preset = cleanString(c.preset, 32, ID_PATTERN)
    if not out.preset then return nil, path .. '.preset' end

    if math.type(c.count) ~= 'integer' and not (isFinite(c.count) and c.count % 1 == 0) then return nil, path .. '.count' end
    out.count = math.tointeger(c.count)
    if out.count < 1 or out.count > limits.maxCrowd then return nil, path .. '.count' end

    if not isFinite(c.seed) or c.seed % 1 ~= 0 or c.seed < 1 or c.seed > 2147483646 then return nil, path .. '.seed' end
    out.seed = math.tointeger(c.seed) or c.seed

    if not isArray(c.points) or #c.points < 1 or #c.points > MAX_CROWD_POINTS then return nil, path .. '.points' end
    out.points = {}
    for j, p in ipairs(c.points) do
        out.points[j] = cleanVec3(p)
        if not out.points[j] then return nil, ('%s.points[%d]'):format(path, j) end
    end

    out.spread = c.spread == nil and 0 or c.spread
    if not isFinite(out.spread) or out.spread < 0 or out.spread > 30 then return nil, path .. '.spread' end

    out.facing = c.facing or 'random'
    if not Scene.FACINGS[out.facing] then return nil, path .. '.facing' end
    if out.facing == 'point' then
        out.lookAt = cleanVec3(c.lookAt)
        if not out.lookAt then return nil, path .. '.lookAt' end
    end

    if c.models ~= nil then
        if not isArray(c.models) or #c.models > MAX_CROWD_MODELS then return nil, path .. '.models' end
        out.models = {}
        for j, m in ipairs(c.models) do
            out.models[j] = cleanString(m, 64, MODEL_PATTERN)
            if not out.models[j] then return nil, ('%s.models[%d]'):format(path, j) end
        end
    end
    if c.scenario ~= nil then
        out.scenario = cleanString(c.scenario, 64, ID_PATTERN)
        if not out.scenario then return nil, path .. '.scenario' end
    end
    return out
end

local function cleanSound(snd, path)
    if type(snd) ~= 'table' then return nil, path end
    local asset = cleanString(snd.asset, 64, ID_PATTERN)
    if not asset then return nil, path .. '.asset' end
    local volume = snd.volume == nil and 1.0 or snd.volume
    if not isFinite(volume) or volume < 0 or volume > 1 then return nil, path .. '.volume' end
    local range = snd.range == nil and 30 or snd.range
    if not isFinite(range) or range < 1 or range > 200 then return nil, path .. '.range' end
    if snd.loop ~= nil and type(snd.loop) ~= 'boolean' then return nil, path .. '.loop' end
    return { asset = asset, volume = volume, range = range, loop = snd.loop ~= false }
end

local function cleanColor(c)
    if not isArray(c) or #c ~= 3 then return nil end
    local out = {}
    for i = 1, 3 do
        if math.type(c[i]) ~= 'integer' and not (isFinite(c[i]) and c[i] % 1 == 0) then return nil end
        out[i] = math.tointeger(c[i])
        if out[i] < 0 or out[i] > 255 then return nil end
    end
    return out
end

local function inRange(v, min, max)
    return isFinite(v) and v >= min and v <= max
end

local function cleanText(tx, path)
    if type(tx) ~= 'table' then return nil, path end
    local content = cleanString(tx.content, 200)
    if not content then return nil, path .. '.content' end
    local color = cleanColor(tx.color or { 255, 255, 255 })
    if not color then return nil, path .. '.color' end
    local scale = tx.scale == nil and 1.0 or tx.scale
    if not inRange(scale, 0.1, 5) then return nil, path .. '.scale' end
    local font = tx.font == nil and 4 or tx.font
    if math.type(font) ~= 'integer' and not (isFinite(font) and font % 1 == 0) then return nil, path .. '.font' end
    if font < 0 or font > 8 then return nil, path .. '.font' end
    for _, k in ipairs({ 'outline', 'backface' }) do
        if tx[k] ~= nil and type(tx[k]) ~= 'boolean' then return nil, path .. '.' .. k end
    end
    return { content = content, color = color, scale = scale, font = math.tointeger(font), outline = tx.outline ~= false, backface = tx.backface == true }
end

local function cleanLight(l, path)
    if type(l) ~= 'table' then return nil, path end
    local kind = l.type or 'point'
    if not Scene.LIGHT_TYPES[kind] then return nil, path .. '.type' end
    local color = cleanColor(l.color or { 255, 255, 255 })
    if not color then return nil, path .. '.color' end
    if not inRange(l.range, 0.5, 100) then return nil, path .. '.range' end
    if not inRange(l.intensity, 0, 50) then return nil, path .. '.intensity' end
    if l.shadow ~= nil and type(l.shadow) ~= 'boolean' then return nil, path .. '.shadow' end
    local out = { type = kind, color = color, range = l.range, intensity = l.intensity, shadow = l.shadow == true }
    if kind == 'spot' then
        if not inRange(l.angle, 1, 90) then return nil, path .. '.angle' end
        local falloff = l.falloff == nil and 1.0 or l.falloff
        if not inRange(falloff, 0, 50) then return nil, path .. '.falloff' end
        out.angle, out.falloff = l.angle, falloff
    end
    return out
end

local function cleanPtfx(p, path)
    if type(p) ~= 'table' then return nil, path end
    local asset = cleanString(p.asset, 64, ID_PATTERN)
    local effect = cleanString(p.effect, 64, ID_PATTERN)
    if not asset or not effect then return nil, path .. '.asset/effect' end
    local scale = p.scale == nil and 1.0 or p.scale
    if not inRange(scale, 0.1, 10) then return nil, path .. '.scale' end
    local out = { asset = asset, effect = effect, scale = scale }
    if p.color ~= nil then
        out.color = cleanColor(p.color)
        if not out.color then return nil, path .. '.color' end
    end
    return out
end

local function cleanEntity(e, i, limits)
    local path = ('entities[%d]'):format(i)
    if type(e) ~= 'table' then return nil, path end
    local id = cleanString(e.id, 32, ID_PATTERN)
    if not id or Scene.RESERVED_TARGETS[id] then return nil, path .. '.id' end
    if not Scene.KINDS[e.kind] then return nil, path .. '.kind' end
    local label = cleanString(e.label, 64)
    if not label then return nil, path .. '.label' end
    local props, err = cleanProps(e.props, path)
    if not props then return nil, err end
    if e.networked ~= nil and type(e.networked) ~= 'boolean' then return nil, path .. '.networked' end

    local out = { id = id, kind = e.kind, label = label, props = props, networked = e.networked == true }

    if Scene.GAME_KINDS[e.kind] then
        out.model = cleanString(e.model, 64, MODEL_PATTERN)
        if not out.model then return nil, path .. '.model' end
    elseif e.kind == 'crowd' then
        out.crowd, err = cleanCrowd(e.crowd, limits, path .. '.crowd')
        if not out.crowd then return nil, err end
    elseif e.kind == 'sound' then
        out.sound, err = cleanSound(e.sound, path .. '.sound')
        if not out.sound then return nil, err end
    elseif e.kind == 'text' then
        out.text, err = cleanText(e.text, path .. '.text')
        if not out.text then return nil, err end
    elseif e.kind == 'light' then
        out.light, err = cleanLight(e.light, path .. '.light')
        if not out.light then return nil, err end
    elseif e.kind == 'ptfx' then
        out.ptfx, err = cleanPtfx(e.ptfx, path .. '.ptfx')
        if not out.ptfx then return nil, err end
    end

    return out
end

local function cleanTimeMs(value, limits)
    if math.type(value) ~= 'integer' and not (isFinite(value) and value % 1 == 0) then return nil end
    local t = math.tointeger(value)
    if t < 0 or t > limits.maxDurationMs then return nil end
    return t
end

local function cleanPositiveMs(value, limits)
    local ms = cleanTimeMs(value, limits)
    return ms and ms > 0 and ms or nil
end

-- Keys de transform y cámara: posición, rotación y easing (fov solo en cámara)
local function cleanPoseKey(k, channel, limits, path)
    local out = { t = cleanTimeMs(k.t, limits) }
    if not out.t then return nil, path .. '.t' end
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

-- Keys de eventos: fade { to, duration }, subtitle { text, duration }, trigger { name }
local function cleanEventKey(k, limits, path)
    local out = { t = cleanTimeMs(k.t, limits) }
    if not out.t then return nil, path .. '.t' end
    if not Scene.EVENT_TYPES[k.type] then return nil, path .. '.type' end
    out.type = k.type

    if k.type == 'fade' then
        if k.to ~= 0 and k.to ~= 1 then return nil, path .. '.to' end
        out.to = k.to
        out.duration = cleanTimeMs(k.duration, limits)
        if not out.duration then return nil, path .. '.duration' end
    elseif k.type == 'subtitle' then
        out.text = cleanString(k.text, 200)
        if not out.text then return nil, path .. '.text' end
        out.duration = cleanPositiveMs(k.duration, limits)
        if not out.duration then return nil, path .. '.duration' end
    else
        out.name = cleanString(k.name, 64, ID_PATTERN)
        if not out.name then return nil, path .. '.name' end
    end

    return out
end

local function cleanAudioClip(c, limits, path)
    local start = cleanTimeMs(c.start, limits)
    if not start then return nil, path .. '.start' end
    local asset = cleanString(c.asset, 64, ID_PATTERN)
    if not asset then return nil, path .. '.asset' end
    local volume = c.volume == nil and 1.0 or c.volume
    if not isFinite(volume) or volume < 0 or volume > 1 then return nil, path .. '.volume' end
    local fadeIn = c.fadeIn == nil and 0 or cleanTimeMs(c.fadeIn, limits)
    if not fadeIn then return nil, path .. '.fadeIn' end
    if c.loop ~= nil and type(c.loop) ~= 'boolean' then return nil, path .. '.loop' end
    local out = { start = start, asset = asset, volume = volume, loop = c.loop == true, fadeIn = fadeIn }
    if c.duration ~= nil then
        out.duration = cleanPositiveMs(c.duration, limits)
        if not out.duration then return nil, path .. '.duration' end
    end
    return out
end

local function cleanAnimClip(c, limits, path)
    local start = cleanTimeMs(c.start, limits)
    if not start then return nil, path .. '.start' end
    local dict = cleanString(c.dict, 128, ANIM_DICT_PATTERN)
    local clip = cleanString(c.clip, 64, ANIM_CLIP_PATTERN)
    if not dict or not clip then return nil, path .. '.dict/clip' end
    local length = cleanPositiveMs(c.length, limits)
    if not length then return nil, path .. '.length' end
    local duration = cleanPositiveMs(c.duration, limits)
    if not duration then return nil, path .. '.duration' end
    if c.loop ~= nil and type(c.loop) ~= 'boolean' then return nil, path .. '.loop' end
    return { start = start, dict = dict, clip = clip, length = length, duration = duration, loop = c.loop == true }
end

local function cleanVisibilityKey(k, limits, path)
    local t = cleanTimeMs(k.t, limits)
    if not t then return nil, path .. '.t' end
    if type(k.visible) ~= 'boolean' then return nil, path .. '.visible' end
    return { t = t, visible = k.visible }
end

-- Target válido para cada canal
local function targetAllowed(channel, target, entityIds)
    if channel == 'camera' then return target == 'camera' end
    if channel == 'event' then return target == 'events' end
    if channel == 'audio' then return target == 'music' or entityIds[target] == true end
    return entityIds[target] == true
end

local function cleanList(list, limits, path, field, cleaner)
    if list ~= nil and not isArray(list) then return nil, path .. '.' .. field end
    local out = {}
    for j, item in ipairs(list or {}) do
        if j > limits.maxKeysPerTrack then return nil, path .. '.too_many_' .. field end
        local itemPath = ('%s.%s[%d]'):format(path, field, j)
        if type(item) ~= 'table' then return nil, itemPath end
        local clean, err = cleaner(item, itemPath)
        if not clean then return nil, err end
        out[j] = clean
    end
    return out
end

local function cleanTrack(tr, i, entityIds, limits)
    local path = ('tracks[%d]'):format(i)
    if type(tr) ~= 'table' then return nil, path end
    local id = cleanString(tr.id, 48, ID_PATTERN)
    if not id then return nil, path .. '.id' end
    if not Scene.CHANNELS[tr.channel] then return nil, path .. '.channel' end
    if not targetAllowed(tr.channel, tr.target, entityIds) then return nil, path .. '.target' end

    local out = { id = id, target = tr.target, channel = tr.channel }
    local err

    if tr.channel == 'audio' or tr.channel == 'anim' then
        local cleaner = tr.channel == 'audio' and cleanAudioClip or cleanAnimClip
        out.clips, err = cleanList(tr.clips, limits, path, 'clips', function(c, p) return cleaner(c, limits, p) end)
        if not out.clips then return nil, err end
        table.sort(out.clips, function(a, b) return a.start < b.start end)
    else
        local cleaner
        if tr.channel == 'event' then
            cleaner = function(k, p) return cleanEventKey(k, limits, p) end
        elseif tr.channel == 'visibility' then
            cleaner = function(k, p) return cleanVisibilityKey(k, limits, p) end
        else
            cleaner = function(k, p) return cleanPoseKey(k, tr.channel, limits, p) end
        end
        out.keys, err = cleanList(tr.keys, limits, path, 'keys', cleaner)
        if not out.keys then return nil, err end

        -- Dos keys en el mismo instante hacen ambiguo el estado en t (los eventos sí pueden coincidir)
        if tr.channel ~= 'event' then
            local seen = {}
            for j, key in ipairs(out.keys) do
                if seen[key.t] then return nil, ('%s.keys[%d].t duplicated'):format(path, j) end
                seen[key.t] = true
            end
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
    local weight, peds = 0, 0
    for i, e in ipairs(data.entities or {}) do
        local clean
        clean, err = cleanEntity(e, i, limits)
        if not clean then return nil, err end
        if entityIds[clean.id] then return nil, ('entities[%d].id duplicated'):format(i) end
        entityIds[clean.id] = true
        entities[i] = clean

        -- Cada miembro de una multitud cuenta como una entidad para el límite del estudio
        local w = Scene.entityWeight(clean)
        weight = weight + w
        if clean.kind == 'ped' or clean.kind == 'crowd' then peds = peds + w end
        if weight > limits.maxEntities then return nil, 'too_many_entities' end
        if limits.maxPeds and peds > limits.maxPeds then return nil, 'too_many_peds' end
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

--- Cuántas entidades de juego representa (una multitud cuenta tantas como personas)
function Scene.entityWeight(entity)
    if entity.kind == 'crowd' then return entity.crowd and entity.crowd.count or 0 end
    -- Sonido, texto, luz y partículas no son entidades del juego (no cuentan para el límite)
    if not Scene.GAME_KINDS[entity.kind] then return 0 end
    return 1
end

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
    local weight, peds = 0, 0
    for _, e in ipairs(data.entities or {}) do
        local w = Scene.entityWeight(e)
        weight = weight + w
        if e.kind == 'ped' or e.kind == 'crowd' then peds = peds + w end
    end
    return {
        weight = weight,
        peds = peds,
        entities = #(data.entities or {}),
        tracks = #(data.tracks or {}),
        keys = keys,
        durationMs = math.max(duration, lastT),
    }
end

return Scene
