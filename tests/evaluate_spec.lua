-- Pruebas de shared/evaluate.lua

local function scene()
    local data = Scene.new('cutscene')
    data.entities = {
        { id = 'ped_1', kind = 'ped', model = 'a_m_y_hipster_01', label = 'Ped 1', props = {}, networked = false },
        { id = 'veh_1', kind = 'vehicle', model = 'elegy', label = 'Car', props = {}, networked = false },
    }
    data.tracks = {
        { id = 'tr_ped_1', target = 'ped_1', channel = 'transform', keys = {
            { t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
            { t = 2000, pos = { 10, 0, 0 }, rot = { 0, 0, 90 } },
        } },
        { id = 'an_ped_1', target = 'ped_1', channel = 'anim', clips = {
            { start = 1000, dict = 'move_m@generic', clip = 'walk', length = 1000, duration = 3000, loop = true },
        } },
        { id = 'cam', target = 'camera', channel = 'camera', keys = {
            { t = 0, pos = { 0, 0, 10 }, rot = { -10, 0, 0 }, fov = 40 },
            { t = 4000, pos = { 0, 40, 10 }, rot = { -10, 0, 0 }, fov = 60 },
        } },
        { id = 'ev', target = 'events', channel = 'event', keys = {
            { t = 0, type = 'fade', to = 0, duration = 0 },
            { t = 1000, type = 'subtitle', text = 'Hola', duration = 1500 },
            { t = 1500, type = 'trigger', name = 'door_open' },
            { t = 8000, type = 'fade', to = 1, duration = 1000 },
        } },
        { id = 'mu', target = 'music', channel = 'audio', clips = {
            { start = 0, asset = 'theme', volume = 0.8, loop = false, fadeIn = 500 },
        } },
    }
    return data
end

test('la escena de ejemplo es válida en schema 2', function()
    assert(Scene.sanitize(scene()))
end)

test('migrate lleva un documento v1 a v2', function()
    local data = scene()
    data.schema = 1
    data.tracks = { data.tracks[1] }
    local out = assert(Scene.migrate(data))
    eq(out.schema, 2, 'schema')
    assert(Scene.sanitize(out))
end)

test('transform interpola y mantiene los extremos', function()
    local p = Evaluate.prepare(scene())
    local s = Evaluate.scene(p, 1000)
    near(s.entities.ped_1.pos[1], 5, 'pos x a mitad')
    near(s.entities.ped_1.rot[3], 45, 'yaw a mitad')
    near(Evaluate.scene(p, -100).entities.ped_1.pos[1], 0, 'antes de la primera key')
    near(Evaluate.scene(p, 99999).entities.ped_1.pos[1], 10, 'tras la última key')
    eq(Evaluate.scene(p, 0).entities.veh_1.pos, nil, 'sin pista = sin pose')
end)

test('evaluar es determinista: el mismo t da el mismo estado', function()
    local p = Evaluate.prepare(scene())
    deepEq(Evaluate.scene(p, 1234), Evaluate.scene(p, 1234))
end)

test('cámara interpola posición y fov', function()
    local cam = Evaluate.scene(Evaluate.prepare(scene()), 2000).camera
    near(cam.pos[2], 20, 'pos y')
    near(cam.fov, 50, 'fov')
end)

test('anim: fase en bucle y fuera del clip', function()
    local p = Evaluate.prepare(scene())
    eq(Evaluate.scene(p, 500).entities.ped_1.anim, nil, 'antes del clip')
    near(Evaluate.scene(p, 1250).entities.ped_1.anim.phase, 0.25, 'fase 0.25')
    near(Evaluate.scene(p, 2250).entities.ped_1.anim.phase, 0.25, 'segunda vuelta')
    eq(Evaluate.scene(p, 4000).entities.ped_1.anim, nil, 'tras el clip')
end)

test('anim sin loop se queda en el último frame', function()
    local clips = { { start = 0, dict = 'd', clip = 'c', length = 1000, duration = 3000, loop = false } }
    near(Evaluate.anim(clips, 2500).phase, 1, 'fase final')
end)

test('fade, subtítulos y triggers', function()
    local p = Evaluate.prepare(scene())
    near(Evaluate.scene(p, 500).fade, 0, 'sin fundido')
    near(Evaluate.scene(p, 8500).fade, 0.5, 'fundido a mitad')
    near(Evaluate.scene(p, 9500).fade, 1, 'negro')
    eq(Evaluate.scene(p, 1200).subtitle, 'Hola', 'subtítulo visible')
    eq(Evaluate.scene(p, 2600).subtitle, nil, 'subtítulo terminado')
    eq(#Evaluate.triggers(p.events, 1000, 1500), 1, 'trigger dentro del intervalo')
    eq(#Evaluate.triggers(p.events, 1500, 2000), 0, 'no se repite')
end)

test('sanitize valida eventos y clips de anim', function()
    local bad = {
        function(d) d.tracks[4].keys[1].to = 0.5 end,
        function(d) d.tracks[4].keys[2].text = '' end,
        function(d) d.tracks[4].keys[3].name = 'rm -rf' end,
        function(d) d.tracks[4].keys[1].type = 'explode' end,
        function(d) d.tracks[2].clips[1].length = 0 end,
        function(d) d.tracks[2].clips[1].dict = 'a b' end,
        function(d) d.tracks[4].target = 'camera' end,
    }
    for i, mutate in ipairs(bad) do
        local data = scene()
        mutate(data)
        eq(Scene.sanitize(data), nil, 'caso ' .. i)
    end
end)
