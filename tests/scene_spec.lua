-- Pruebas de shared/scene.lua

local function sample()
    local data = Scene.new('cutscene')
    data.entities = {
        { id = 'veh_1', kind = 'vehicle', model = 'elegy', label = 'Vehicle 1',
          props = { engine = true, headlights = true, dirt = 5.2, doors = { 0, 4 } }, networked = false },
        { id = 'ped_1', kind = 'ped', model = 'a_m_y_hipster_01', label = 'Ped 1',
          props = { anim = { dict = 'amb@world_human_smoking@male@male_a@idle_a', clip = 'idle_a' } }, networked = false },
    }
    data.tracks = {
        { id = 'tr_veh_1', target = 'veh_1', channel = 'transform',
          keys = { { t = 0, pos = { 292.9, -847.1, 28.8 }, rot = { 0.05, 1.42, 86.48 }, ease = 'inOut' } } },
        { id = 'cam', target = 'camera', channel = 'camera',
          keys = { { t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 }, fov = 45 } } },
    }
    return data
end

test('new() produce una escena válida para ambos tipos', function()
    for _, kind in ipairs({ 'cutscene', 'ambience' }) do
        local clean, err = Scene.sanitize(Scene.new(kind))
        assert(clean, err)
        eq(clean.settings.loop, kind == 'ambience', 'loop')
    end
end)

test('sanitize conserva un documento válido', function()
    local data = sample()
    local clean, err = Scene.sanitize(data)
    assert(clean, err)
    deepEq(clean, data)
end)

test('sanitize es idempotente', function()
    local once = assert(Scene.sanitize(sample()))
    local twice = assert(Scene.sanitize(once))
    deepEq(twice, once)
end)

test('sanitize descarta campos desconocidos', function()
    local data = sample()
    data.hack = true
    data.entities[1].handle = 1234
    data.tracks[1].keys[1].extra = 'x'
    local clean = assert(Scene.sanitize(data))
    eq(clean.hack, nil, 'hack')
    eq(clean.entities[1].handle, nil, 'handle')
    eq(clean.tracks[1].keys[1].extra, nil, 'extra')
end)

test('sanitize ordena keys por t', function()
    local data = sample()
    data.tracks[1].keys = {
        { t = 2000, pos = { 1, 1, 1 }, rot = { 0, 0, 0 } },
        { t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
    }
    local clean = assert(Scene.sanitize(data))
    eq(clean.tracks[1].keys[1].t, 0, 'primera key')
end)

local rejects = {
    { 'schema distinto', function(d) d.schema = Scene.SCHEMA + 1 end },
    { 'tipo de entidad', function(d) d.entities[1].kind = 'tank' end },
    { 'modelo con caracteres raros', function(d) d.entities[1].model = 'elegy; drop' end },
    { 'id duplicado', function(d) d.entities[2].id = 'veh_1' end },
    { 'id reservado camera', function(d) d.entities[1].id = 'camera' end },
    { 'id reservado music', function(d) d.entities[1].id = 'music' end },
    { 'ease desconocido en cámara', function(d) d.tracks[2].keys[1].ease = 'wobble' end },
    { 'cámara con target de entidad', function(d) d.tracks[2].target = 'veh_1' end },
    { 'pista a entidad inexistente', function(d) d.tracks[1].target = 'ghost' end },
    { 'canal desconocido', function(d) d.tracks[1].channel = 'lua' end },
    { 'NaN en posición', function(d) d.tracks[1].keys[1].pos[1] = 0 / 0 end },
    { 'infinito en rotación', function(d) d.tracks[1].keys[1].rot[3] = math.huge end },
    { 'vector corto', function(d) d.tracks[1].keys[1].pos = { 1, 2 } end },
    { 't negativo', function(d) d.tracks[1].keys[1].t = -1 end },
    { 't decimal', function(d) d.tracks[1].keys[1].t = 0.5 end },
    { 'keys con t repetido', function(d) d.tracks[1].keys[2] = { t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } } end },
    { 'ease desconocido', function(d) d.tracks[1].keys[1].ease = 'bounce' end },
    { 'fov fuera de rango', function(d) d.tracks[2].keys[1].fov = 500 end },
    { 'clima desconocido', function(d) d.settings.weather = 'LAVA' end },
    { 'hora inválida', function(d) d.settings.time = '25:00' end },
    { 'trigger con exit < enter', function(d) d.settings.trigger = { center = { 0, 0, 0 }, enter = 100, exit = 50 } end },
    { 'prop anidado', function(d) d.entities[1].props.deep = { a = { b = 1 } } end },
    { 'prop función', function(d) d.entities[1].props.fn = print end },
    { 'label vacío', function(d) d.entities[1].label = '' end },
}

for _, case in ipairs(rejects) do
    test('sanitize rechaza: ' .. case[1], function()
        local data = sample()
        case[2](data)
        local clean, err = Scene.sanitize(data)
        assert(clean == nil, 'debería fallar')
        assert(type(err) == 'string', 'sin mensaje de error')
    end)
end

test('sanitize respeta el límite de entidades', function()
    local data = sample()
    local clean, err = Scene.sanitize(data, { maxEntities = 1 })
    eq(clean, nil, 'clean')
    eq(err, 'too_many_entities', 'err')
end)

test('migrate acepta el schema actual y rechaza uno futuro', function()
    assert(Scene.migrate(sample()))
    local data = sample()
    data.schema = Scene.SCHEMA + 1
    local out, err = Scene.migrate(data)
    eq(out, nil, 'out')
    eq(err, 'schema_too_new', 'err')
end)

test('baseTransform devuelve la key más temprana', function()
    local data = sample()
    data.tracks[1].keys = {
        { t = 500, pos = { 9, 9, 9 }, rot = { 0, 0, 0 } },
        { t = 100, pos = { 1, 2, 3 }, rot = { 0, 0, 90 } },
    }
    local pos, rot = Scene.baseTransform(data, 'veh_1')
    eq(pos[1], 1, 'pos.x')
    eq(rot[3], 90, 'rot.z')
    eq(Scene.baseTransform(data, 'ped_1'), nil, 'sin pista')
end)

test('stats cuenta entidades, keys y duración', function()
    local data = sample()
    data.tracks[1].keys[2] = { t = 15000, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
    local s = Scene.stats(data)
    eq(s.entities, 2, 'entities')
    eq(s.tracks, 2, 'tracks')
    eq(s.keys, 3, 'keys')
    eq(s.durationMs, 15000, 'duration')
end)

