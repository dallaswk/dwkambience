-- Colocación de multitudes: a partir de la semilla, todos los clientes obtienen las mismas personas
-- en los mismos sitios. Sin natives.
Crowd = Crowd or {}

local MODULUS = 2147483647.0

--- Generador Park-Miller con aritmética en coma flotante: da la misma secuencia en Lua 5.4
--- (enteros de 64 bits) y en intérpretes con enteros de 32 bits.
function Crowd.rng(seed)
    local state = math.fmod(math.abs(seed or 1) + 0.0, MODULUS - 1) + 1
    return function()
        state = math.fmod(state * 16807.0, MODULUS)
        return (state - 1) / (MODULUS - 1)
    end
end

--- Heading de GTA (grados) para mirar en la dirección (dx, dy).
function Crowd.heading(dx, dy)
    return (math.deg(math.atan(-dx, dy)) + 360) % 360
end

local function pick(list, rand)
    if not list or #list == 0 then return nil end
    return list[math.floor(rand() * #list) + 1]
end

-- Longitudes acumuladas de la polilínea
local function measure(points)
    local lengths, total = { 0 }, 0
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        total = total + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        lengths[i] = total
    end
    return lengths, total
end

-- Punto y dirección a una distancia d sobre la polilínea
local function along(points, lengths, d)
    for i = 2, #points do
        if d <= lengths[i] or i == #points then
            local a, b = points[i - 1], points[i]
            local seg = lengths[i] - lengths[i - 1]
            local x = seg > 0 and (d - lengths[i - 1]) / seg or 0
            x = math.max(0, math.min(1, x))
            local dx, dy = b[1] - a[1], b[2] - a[2]
            local len = math.sqrt(dx * dx + dy * dy)
            if len == 0 then dx, dy, len = 0, 1, 1 end
            return { a[1] + (b[1] - a[1]) * x, a[2] + (b[2] - a[2]) * x, a[3] + (b[3] - a[3]) * x }, dx / len, dy / len
        end
    end
end

--- Miembros de una multitud. crowd = { count, seed, points, spread, facing, lookAt, models?, scenario? }
--- preset = { models, scenarios?, anims? } (los modelos/escenario del propio crowd mandan si existen).
--- Devuelve { { model, pos = {x,y,z}, heading, scenario | anim = {dict, clip}, phase } }
function Crowd.layout(crowd, preset)
    preset = preset or {}
    local rand = Crowd.rng(crowd.seed)
    local models = (crowd.models and #crowd.models > 0) and crowd.models or preset.models or {}
    local scenarios = crowd.scenario and { crowd.scenario } or preset.scenarios or {}
    local anims = crowd.scenario and {} or preset.anims or {}
    local points = crowd.points or {}
    local spread = crowd.spread or 0
    local count = crowd.count or 0
    if #points == 0 or #models == 0 or count <= 0 then return {} end

    local lengths, total = measure(points)
    local members = {}

    for i = 1, count do
        local pos, fx, fy
        if #points == 1 or total == 0 then
            -- Área circular alrededor del punto (sqrt para repartir uniformemente)
            local angle, radius = rand() * 2 * math.pi, math.sqrt(rand()) * spread
            local c = points[1]
            pos = { c[1] + math.cos(angle) * radius, c[2] + math.sin(angle) * radius, c[3] }
            fx, fy = math.cos(angle), math.sin(angle)
        else
            -- Repartidos a lo largo de la línea con algo de variación y desplazamiento lateral
            local slot = total / count
            local d = (i - 0.5) * slot + (rand() - 0.5) * slot * 0.6
            pos, fx, fy = along(points, lengths, math.max(0, math.min(total, d)))
            local side = (rand() * 2 - 1) * spread
            pos = { pos[1] + fy * side, pos[2] - fx * side, pos[3] }
        end

        local heading
        if crowd.facing == 'point' and crowd.lookAt then
            heading = Crowd.heading(crowd.lookAt[1] - pos[1], crowd.lookAt[2] - pos[2])
        elseif crowd.facing == 'along' then
            heading = (Crowd.heading(fx, fy) + (rand() - 0.5) * 40 + 360) % 360
        else
            heading = rand() * 360
        end

        local member = { model = pick(models, rand), pos = pos, heading = heading, phase = rand() }
        local total_actions = #scenarios + #anims
        if total_actions > 0 then
            local k = math.floor(rand() * total_actions) + 1
            if k <= #scenarios then member.scenario = scenarios[k] else member.anim = anims[k - #scenarios] end
        end
        members[i] = member
    end

    return members
end

return Crowd
