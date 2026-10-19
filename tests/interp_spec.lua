-- Pruebas de shared/interp.lua

test('ease: extremos fijos y orden de curvas en el centro', function()
    for _, name in ipairs({ 'linear', 'in', 'out', 'inOut', 'spline' }) do
        near(Interp.ease(name, 0), 0, name .. '(0)')
        near(Interp.ease(name, 1), 1, name .. '(1)')
    end
    near(Interp.ease('inOut', 0.5), 0.5, 'inOut(0.5)')
    assert(Interp.ease('in', 0.5) < 0.5, 'in lento al principio')
    assert(Interp.ease('out', 0.5) > 0.5, 'out rápido al principio')
    near(Interp.ease('linear', 2), 1, 'satura en 1')
end)

test('ángulos: camino más corto al cruzar 360', function()
    near(Interp.angleDelta(350, 10), 20, '350 -> 10')
    near(Interp.angleDelta(10, 350), -20, '10 -> 350')
    near(Interp.lerpAngle(350, 10, 0.5), 360, 'mitad')
    near(Interp.angleDelta(0, 180), -180, '0 -> 180')
end)

test('catmull pasa por los puntos de control', function()
    near(Interp.catmull(0, 1, 5, 7, 0), 1, 'x = 0')
    near(Interp.catmull(0, 1, 5, 7, 1), 5, 'x = 1')
    near(Interp.catmull(0, 1, 2, 3, 0.5), 1.5, 'recta')
end)

test('segment: antes, dentro y después de las keys', function()
    local keys = { { t = 0 }, { t = 1000 }, { t = 3000 } }
    local i, x = Interp.segment(keys, -50)
    eq(i, 1, 'antes i'); near(x, 0, 'antes x')
    i, x = Interp.segment(keys, 2000)
    eq(i, 2, 'dentro i'); near(x, 0.5, 'dentro x')
    i, x = Interp.segment(keys, 1000)
    eq(i, 2, 'exacto i'); near(x, 0, 'exacto x')
    i, x = Interp.segment(keys, 9999)
    eq(i, 3, 'después i'); near(x, 0, 'después x')
    eq(Interp.segment({}, 0), nil, 'sin keys')
end)

test('vec3 con rotación cruza 360 por el camino corto', function()
    local keys = {
        { t = 0, rot = { 0, 0, 350 } },
        { t = 1000, rot = { 0, 0, 30 } },
    }
    local rot = Interp.vec3(keys, 'rot', 1, 0.5, true)
    near(rot[3], 370, 'yaw a mitad')
end)

test('vec3 spline coincide con las keys en sus extremos', function()
    local keys = {
        { t = 0, pos = { 0, 0, 0 }, ease = 'spline' },
        { t = 1000, pos = { 10, 0, 0 }, ease = 'spline' },
        { t = 2000, pos = { 10, 10, 0 }, ease = 'spline' },
    }
    local a = Interp.vec3(keys, 'pos', 1, 0, false)
    local b = Interp.vec3(keys, 'pos', 1, 1, false)
    near(a[1], 0, 'inicio'); near(b[1], 10, 'final x'); near(b[2], 0, 'final y')
end)
