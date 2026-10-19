-- Pruebas de shared/crowd.lua y de los campos de schema 3

local PRESET = {
    models = { 'a_m_y_hipster_01', 'a_f_y_hipster_01' },
    scenarios = { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE' },
    anims = { { dict = 'amb@world_human_hang_out_street@male_a@idle_a', clip = 'idle_a' } },
}

local function crowd(over)
    local c = { preset = 'street', count = 20, seed = 1234, points = { { 0, 0, 30 }, { 40, 0, 30 } }, spread = 2, facing = 'along' }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

test('rng: determinista y en [0, 1)', function()
    local a, b = Crowd.rng(42), Crowd.rng(42)
    for _ = 1, 200 do
        local x = a()
        eq(x, b(), 'misma secuencia')
        assert(x >= 0 and x < 1, 'rango')
    end
    assert(Crowd.rng(1)() ~= Crowd.rng(2)(), 'semillas distintas')
end)

test('heading: norte 0, oeste 90, sur 180, este 270', function()
    near(Crowd.heading(0, 1), 0, 'norte')
    near(Crowd.heading(-1, 0), 90, 'oeste')
    near(Crowd.heading(0, -1), 180, 'sur')
    near(Crowd.heading(1, 0), 270, 'este')
end)

test('layout: misma semilla, misma multitud', function()
    deepEq(Crowd.layout(crowd(), PRESET), Crowd.layout(crowd(), PRESET))
    local other = Crowd.layout(crowd({ seed = 999 }), PRESET)
    assert(other[1].pos[1] ~= Crowd.layout(crowd(), PRESET)[1].pos[1] or other[1].heading ~= Crowd.layout(crowd(), PRESET)[1].heading, 'otra semilla cambia')
end)

test('layout en línea: cuenta, posiciones dentro de la franja y acción asignada', function()
    local members = Crowd.layout(crowd(), PRESET)
    eq(#members, 20, 'count')
    for _, m in ipairs(members) do
        assert(m.pos[1] >= -0.01 and m.pos[1] <= 40.01, 'x en la línea')
        assert(math.abs(m.pos[2]) <= 2.0001, 'dentro del spread lateral')
        assert(m.scenario or m.anim, 'tiene acción')
        assert(m.model == 'a_m_y_hipster_01' or m.model == 'a_f_y_hipster_01', 'modelo del preset')
    end
end)

test('layout en área: un punto reparte dentro del radio', function()
    for _, m in ipairs(Crowd.layout(crowd({ points = { { 10, 10, 5 } }, spread = 6, facing = 'random' }), PRESET)) do
        local d = math.sqrt((m.pos[1] - 10) ^ 2 + (m.pos[2] - 10) ^ 2)
        assert(d <= 6.0001, 'dentro del radio')
    end
end)

test('layout mirando a un punto', function()
    local members = Crowd.layout(crowd({ facing = 'point', lookAt = { 20, 50, 30 } }), PRESET)
    local m = members[1]
    near(m.heading, Crowd.heading(20 - m.pos[1], 50 - m.pos[2]), 'heading hacia lookAt')
end)

test('layout custom: modelos y escenario del propio crowd', function()
    for _, m in ipairs(Crowd.layout(crowd({ models = { 's_m_y_cop_01' }, scenario = 'WORLD_HUMAN_COP_IDLES' }), PRESET)) do
        eq(m.model, 's_m_y_cop_01', 'modelo')
        eq(m.scenario, 'WORLD_HUMAN_COP_IDLES', 'escenario')
    end
end)

local function ambience()
    local data = Scene.new('ambience')
    data.settings.timecycle = { name = 'MP_Bull_tost', strength = 0.6 }
    data.entities = {
        { id = 'crowd_1', kind = 'crowd', label = 'Multitud', props = {}, networked = false, crowd = crowd() },
        { id = 'snd_1', kind = 'sound', label = 'Altavoz', props = {}, networked = false, sound = { asset = 'club', volume = 0.5, range = 40, loop = true } },
        { id = 'ped_1', kind = 'ped', model = 'a_m_y_hipster_01', label = 'DJ', props = {}, networked = false },
    }
    data.tracks = { { id = 'tr_snd_1', target = 'snd_1', channel = 'transform', keys = { { t = 0, pos = { 1, 2, 3 }, rot = { 0, 0, 0 } } } } }
    return data
end

test('schema 3: ambience con multitud, sonido y timecycle es válido', function()
    local clean = assert(Scene.sanitize(ambience()))
    eq(clean.entities[1].crowd.count, 20, 'crowd')
    eq(clean.entities[2].sound.range, 40, 'sound')
    eq(clean.entities[2].model, nil, 'sound sin modelo')
    eq(clean.settings.timecycle.strength, 0.6, 'timecycle')
end)

test('schema 3: peso de entidades y límite de peds', function()
    local s = Scene.stats(ambience())
    eq(s.weight, 21, 'peso: 20 de la multitud + 1 ped')
    eq(s.peds, 21, 'peds')
    local clean, err = Scene.sanitize(ambience(), { maxPeds = 20 })
    eq(clean, nil, 'excede peds'); eq(err, 'too_many_peds', 'err peds')
    clean, err = Scene.sanitize(ambience(), { maxEntities = 10 })
    eq(err, 'too_many_entities', 'err entidades')
end)

test('schema 3: rechaza multitudes y sonidos mal formados', function()
    local bad = {
        function(d) d.entities[1].crowd.count = 0 end,
        function(d) d.entities[1].crowd.count = 61 end,
        function(d) d.entities[1].crowd.points = {} end,
        function(d) d.entities[1].crowd.facing = 'point' end,
        function(d) d.entities[1].crowd.spread = 99 end,
        function(d) d.entities[1].crowd.models = { 'a b' } end,
        function(d) d.entities[2].sound.range = 0 end,
        function(d) d.entities[2].sound = nil end,
        function(d) d.entities[3].model = nil end,
        function(d) d.settings.timecycle = { name = 'x y', strength = 1 } end,
        function(d) d.settings.timecycle = { name = 'ok', strength = 2 } end,
    }
    for i, mutate in ipairs(bad) do
        local data = ambience()
        mutate(data)
        eq(Scene.sanitize(data), nil, 'caso ' .. i)
    end
end)
