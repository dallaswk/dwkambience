-- Simplificación de grabaciones (Ramer–Douglas–Peucker en el tiempo). Sin natives.
-- Entrada: muestras { t, pos = {x,y,z}, rot = {x,y,z} } ordenadas por t.
-- Se conserva una muestra si, al quitarla, la interpolación lineal en el tiempo entre sus vecinas
-- se desvía más de `epsilon` metros (las rotaciones cuentan con `rotWeight` metros por grado).
Rdp = Rdp or {}

local DEFAULT_ROT_WEIGHT = 0.02 -- 50 grados de error equivalen a 1 m

local function angleDelta(a, b)
    return (b - a + 180) % 360 - 180
end

-- Error de la muestra s respecto a la interpolación entre a y b en el instante s.t
local function errorAt(a, b, s, rotWeight)
    local span = b.t - a.t
    local x = span > 0 and (s.t - a.t) / span or 0
    local d2 = 0
    for c = 1, 3 do
        local expected = a.pos[c] + (b.pos[c] - a.pos[c]) * x
        d2 = d2 + (s.pos[c] - expected) ^ 2
    end
    local posErr = math.sqrt(d2)
    local rotErr = 0
    for c = 1, 3 do
        local expected = a.rot[c] + angleDelta(a.rot[c], b.rot[c]) * x
        rotErr = math.max(rotErr, math.abs(angleDelta(expected, s.rot[c])))
    end
    return math.max(posErr, rotErr * rotWeight)
end

--- Índices de las muestras que se conservan (siempre la primera y la última).
function Rdp.simplify(samples, epsilon, rotWeight)
    local n = #samples
    if n <= 2 then
        local all = {}
        for i = 1, n do all[i] = i end
        return all
    end
    rotWeight = rotWeight or DEFAULT_ROT_WEIGHT

    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    while #stack > 0 do
        local range = table.remove(stack)
        local first, last = range[1], range[2]
        local worst, worstErr = nil, epsilon
        for i = first + 1, last - 1 do
            local err = errorAt(samples[first], samples[last], samples[i], rotWeight)
            if err > worstErr then worst, worstErr = i, err end
        end
        if worst then
            keep[worst] = true
            stack[#stack + 1] = { first, worst }
            stack[#stack + 1] = { worst, last }
        end
    end

    local out = {}
    for i = 1, n do
        if keep[i] then out[#out + 1] = i end
    end
    return out
end

--- Keys de transform a partir de una grabación, desplazadas para que la primera muestra caiga en startT.
--- Los tiempos se redondean a ms enteros y se descartan duplicados.
function Rdp.toKeys(samples, epsilon, startT, rotWeight)
    local keys, lastT = {}, nil
    if #samples == 0 then return keys end
    local origin = samples[1].t
    for _, i in ipairs(Rdp.simplify(samples, epsilon, rotWeight)) do
        local s = samples[i]
        local t = math.floor(startT + (s.t - origin) + 0.5)
        if t ~= lastT then
            keys[#keys + 1] = {
                t = t,
                pos = { s.pos[1], s.pos[2], s.pos[3] },
                rot = { s.rot[1], s.rot[2], s.rot[3] },
            }
            lastT = t
        end
    end
    return keys
end

return Rdp
