-- Interpolación pura: easing, ángulos y Catmull-Rom. Sin natives.
Interp = Interp or {}

local function clamp01(x)
    return x < 0 and 0 or (x > 1 and 1 or x)
end

Interp.clamp01 = clamp01

--- Curva de easing sobre x en [0, 1]. 'spline' no curva x: la forma la da Catmull-Rom.
function Interp.ease(name, x)
    x = clamp01(x)
    if name == 'in' then
        return x * x * x
    elseif name == 'out' then
        local u = 1 - x
        return 1 - u * u * u
    elseif name == 'inOut' then
        if x < 0.5 then return 4 * x * x * x end
        local u = -2 * x + 2
        return 1 - u * u * u / 2
    end
    return x
end

function Interp.lerp(a, b, x)
    return a + (b - a) * x
end

--- Diferencia angular más corta de a a b, en grados, dentro de [-180, 180).
function Interp.angleDelta(a, b)
    return (b - a + 180) % 360 - 180
end

function Interp.lerpAngle(a, b, x)
    return a + Interp.angleDelta(a, b) * x
end

--- Catmull-Rom uniforme entre p1 y p2.
function Interp.catmull(p0, p1, p2, p3, x)
    local x2, x3 = x * x, x * x * x
    return 0.5 * ((2 * p1) + (-p0 + p2) * x + (2 * p0 - 5 * p1 + 4 * p2 - p3) * x2 + (-p0 + 3 * p1 - 3 * p2 + p3) * x3)
end

--- Segmento de keys (ordenadas por t) que contiene t. Devuelve i, x:
--- el valor está entre keys[i] y keys[i + 1] con progreso x. Antes de la primera o tras la última, x = 0.
function Interp.segment(keys, t)
    local n = #keys
    if n == 0 then return nil end
    if t <= keys[1].t then return 1, 0 end
    if t >= keys[n].t then return n, 0 end

    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if keys[mid].t <= t then lo = mid else hi = mid end
    end
    local a, b = keys[lo].t, keys[hi].t
    return lo, (t - a) / (b - a)
end

--- Interpola el vector3 `field` entre keys[i] y keys[i + 1].
--- angles = true usa el camino angular más corto (rotaciones en grados).
function Interp.vec3(keys, field, i, x, angles)
    local k1 = keys[i]
    local v1 = k1[field]
    local k2 = keys[i + 1]
    if not k2 or x <= 0 then return { v1[1], v1[2], v1[3] } end
    local v2 = k2[field]
    local ease = k1.ease or 'linear'

    local out = {}
    if ease == 'spline' then
        local v0 = (keys[i - 1] or k1)[field]
        local v3 = (keys[i + 2] or k2)[field]
        for c = 1, 3 do
            local p0, p2, p3 = v0[c], v2[c], v3[c]
            if angles then
                -- Se desenrollan los ángulos alrededor de v1 para que la curva no dé la vuelta larga
                p2 = v1[c] + Interp.angleDelta(v1[c], p2)
                p0 = v1[c] + Interp.angleDelta(v1[c], p0)
                p3 = p2 + Interp.angleDelta(p2, p3)
            end
            out[c] = Interp.catmull(p0, v1[c], p2, p3, x)
        end
    else
        local e = Interp.ease(ease, x)
        for c = 1, 3 do
            out[c] = angles and Interp.lerpAngle(v1[c], v2[c], e) or Interp.lerp(v1[c], v2[c], e)
        end
    end
    return out
end

--- Interpola un escalar `field` (p. ej. fov) entre keys[i] y keys[i + 1]; usa `default` si falta.
function Interp.scalar(keys, field, i, x, default)
    local k1, k2 = keys[i], keys[i + 1]
    local a = k1[field] or default
    if not k2 or x <= 0 then return a end
    local b = k2[field] or default
    local ease = k1.ease or 'linear'
    if ease == 'spline' then
        local a0 = (keys[i - 1] or k1)[field] or default
        local b3 = (keys[i + 2] or k2)[field] or default
        return Interp.catmull(a0, a, b, b3, x)
    end
    return Interp.lerp(a, b, Interp.ease(ease, x))
end

return Interp
