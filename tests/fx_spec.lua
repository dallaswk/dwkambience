-- Pruebas del esquema 4 (texto, luces, partículas, visibilidad) y de shared/rdp.lua

local function fxScene()
    local data = Scene.new('cutscene')
    data.entities = {
        { id = 'text_1', kind = 'text', label = 'Cartel', props = {}, networked = false,
          text = { content = 'Bienvenido', color = { 1, 150, 133 }, scale = 1.2, font = 4, outline = true, backface = false } },
        { id = 'light_1', kind = 'light', label = 'Foco', props = {}, networked = false,
          light = { type = 'spot', color = { 255, 220, 180 }, range = 20, intensity = 8, shadow = true, angle = 30, falloff = 2 } },
        { id = 'ptfx_1', kind = 'ptfx', label = 'Humo', props = {}, networked = false,
          ptfx = { asset = 'core', effect = 'exp_grd_bzgas_smoke', scale = 1.5 } },
    }
    data.tracks = {
        { id = 'vis_light_1', target = 'light_1', channel = 'visibility', keys = {
            { t = 0, visible = false }, { t = 2000, visible = true }, { t = 5000, visible = false },
        } },
    }
    return data
end

test('schema 4: texto, luz y partículas son válidos y no cuentan como entidades', function()
    local clean = assert(Scene.sanitize(fxScene()))
    eq(clean.entities[1].text.content, 'Bienvenido', 'texto')
    eq(clean.entities[2].light.angle, 30, 'foco')
    eq(clean.entities[3].ptfx.effect, 'exp_grd_bzgas_smoke', 'ptfx')
    eq(Scene.stats(clean).weight, 0, 'peso')
end)

test('schema 4: rechaza campos fuera de rango', function()
    local bad = {
        function(d) d.entities[1].text.content = '' end,
        function(d) d.entities[1].text.color = { 300, 0, 0 } end,
        function(d) d.entities[1].text.font = 12 end,
        function(d) d.entities[2].light.type = 'laser' end,
        function(d) d.entities[2].light.range = 0 end,
        function(d) d.entities[2].light.angle = nil end,
        function(d) d.entities[3].ptfx.effect = 'a b' end,
        function(d) d.tracks[1].keys[1].visible = 'no' end,
        function(d) d.tracks[1].keys[2].t = 0 end,
    }
    for i, mutate in ipairs(bad) do
        local data = fxScene()
        mutate(data)
        eq(Scene.sanitize(data), nil, 'caso ' .. i)
    end
end)

test('visibilidad: manda la key más reciente y antes de la primera vale la primera', function()
    local p = Evaluate.prepare(fxScene())
    eq(Evaluate.scene(p, 1000).entities.light_1.visible, false, 'apagada')
    eq(Evaluate.scene(p, 2000).entities.light_1.visible, true, 'encendida en su key')
    eq(Evaluate.scene(p, 4999).entities.light_1.visible, true, 'sigue encendida')
    eq(Evaluate.scene(p, 9000).entities.light_1.visible, false, 'apagada al final')
    eq(Evaluate.scene(p, 0).entities.text_1.visible, true, 'sin pista: visible')
end)

local function line(n, noise)
    local samples = {}
    for i = 0, n - 1 do
        samples[#samples + 1] = { t = i * 50, pos = { i * 0.5, (i % 2 == 0) and 0 or (noise or 0), 30 }, rot = { 0, 0, 90 } }
    end
    return samples
end

test('rdp: una recta se queda en sus dos extremos', function()
    local idx = Rdp.simplify(line(40), 0.05)
    eq(#idx, 2, 'dos keys'); eq(idx[1], 1, 'primera'); eq(idx[2], 40, 'última')
end)

test('rdp: conserva una esquina', function()
    local samples = {}
    for i = 0, 20 do samples[#samples + 1] = { t = i * 50, pos = { i, 0, 0 }, rot = { 0, 0, 0 } } end
    for i = 1, 20 do samples[#samples + 1] = { t = (20 + i) * 50, pos = { 20, i, 0 }, rot = { 0, 0, 0 } } end
    local idx = Rdp.simplify(samples, 0.1)
    eq(#idx, 3, 'inicio, esquina y final')
    eq(samples[idx[2]].pos[1], 20, 'la esquina')
end)

test('rdp: el ruido por debajo de epsilon se ignora, por encima se conserva', function()
    eq(#Rdp.simplify(line(30, 0.02), 0.1), 2, 'ruido pequeño')
    assert(#Rdp.simplify(line(30, 0.5), 0.1) > 2, 'ruido grande')
end)

test('rdp: los giros cuentan aunque la posición no cambie', function()
    local samples = {}
    for i = 0, 10 do samples[#samples + 1] = { t = i * 50, pos = { 0, 0, 0 }, rot = { 0, 0, i < 5 and 0 or 180 } } end
    assert(#Rdp.simplify(samples, 0.1) > 2, 'giro conservado')
end)

test('rdp: toKeys desplaza al instante de inicio y mantiene la pose', function()
    local keys = Rdp.toKeys(line(40), 0.05, 3000)
    eq(#keys, 2, 'keys')
    eq(keys[1].t, 3000, 'inicio')
    eq(keys[2].t, 3000 + 39 * 50, 'final')
    near(keys[2].pos[1], 19.5, 'pos final')
    assert(Scene.sanitize((function()
        local d = Scene.new('cutscene')
        d.entities = { { id = 'ped_1', kind = 'ped', model = 'a_m_y_hipster_01', label = 'P', props = {}, networked = false } }
        d.tracks = { { id = 'tr_ped_1', target = 'ped_1', channel = 'transform', keys = keys } }
        return d
    end)()), 'las keys grabadas pasan la validación')
end)

test('entidades en red: solo del juego y con límite', function()
    local data = Scene.new('ambience')
    data.entities = {
        { id = 'veh_1', kind = 'vehicle', model = 'elegy', label = 'A', props = { vehicleType = 'automobile' }, networked = true },
        { id = 'veh_2', kind = 'vehicle', model = 'sultan', label = 'B', props = {}, networked = true },
    }
    assert(Scene.sanitize(data), 'dos en red sin límite')
    local clean, err = Scene.sanitize(data, { maxNetworked = 1 })
    eq(clean, nil, 'pasa el límite'); eq(err, 'too_many_networked', 'error')
    eq(select(2, Scene.sanitize(data, { maxNetworked = 0 })), 'too_many_networked', 'cutscene sin red')
    data.entities = { { id = 'snd_1', kind = 'sound', label = 'S', props = {}, networked = true, sound = { asset = 'a', volume = 1, range = 10, loop = true } } }
    eq(Scene.sanitize(data), nil, 'un sonido no puede ir en red')
end)

test('schema 5: texto en pantalla solo en props y con campos válidos', function()
    local data = Scene.new('cutscene')
    data.entities = { { id = 'prop_1', kind = 'prop', model = 'prop_tv_flat_01', label = 'TV', props = {}, networked = false,
        screen = { content = 'EN DIRECTO', color = { 255, 255, 255 }, background = { 1, 150, 133 }, scale = 2, font = 4 } } }
    local clean = assert(Scene.sanitize(data))
    eq(clean.entities[1].screen.background[2], 150, 'fondo')
    data.entities[1].screen.content = ''
    eq(Scene.sanitize(data), nil, 'sin contenido')
    data.entities[1].screen.content = 'ok'
    data.entities[1].kind = 'vehicle'
    eq(Scene.sanitize(data), nil, 'solo props')
end)
