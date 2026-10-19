-- Evaluador del timeline: el estado de la escena es una función pura de t (ms). Sin natives.
-- Uso: local prepared = Evaluate.prepare(data); local state = Evaluate.scene(prepared, t)
Evaluate = Evaluate or {}

local DEFAULT_FOV = 50.0

--- Indexa las pistas por target y canal para no recorrerlas en cada frame.
function Evaluate.prepare(data)
    local p = {
        data = data,
        transform = {}, -- [entityId] = keys
        anim = {},      -- [entityId] = clips
        camera = nil,   -- keys
        events = {},    -- keys de todos los tracks de eventos, ordenadas
        audio = {},     -- [target] = clips
        visibility = {}, -- [entityId] = keys
    }
    for _, tr in ipairs(data.tracks or {}) do
        if tr.channel == 'transform' then
            p.transform[tr.target] = tr.keys or {}
        elseif tr.channel == 'anim' then
            p.anim[tr.target] = tr.clips or {}
        elseif tr.channel == 'camera' then
            p.camera = tr.keys or {}
        elseif tr.channel == 'event' then
            for _, k in ipairs(tr.keys or {}) do p.events[#p.events + 1] = k end
        elseif tr.channel == 'audio' then
            p.audio[tr.target] = tr.clips or {}
        elseif tr.channel == 'visibility' then
            p.visibility[tr.target] = tr.keys or {}
        end
    end
    table.sort(p.events, function(a, b) return a.t < b.t end)
    return p
end

--- pos, rot de una pista de transform en t, o nil si no tiene keys.
function Evaluate.transform(keys, t)
    local i, x = Interp.segment(keys or {}, t)
    if not i then return nil end
    return Interp.vec3(keys, 'pos', i, x, false), Interp.vec3(keys, 'rot', i, x, true)
end

--- pos, rot, fov, dof de la pista de cámara en t, o nil. dof = { strength, near, far } o nil si es 0.
function Evaluate.camera(keys, t)
    local i, x = Interp.segment(keys or {}, t)
    if not i then return nil end
    local dof
    local strength = Interp.scalar(keys, 'dofStrength', i, x, 0)
    if strength > 0.001 then
        dof = { strength = strength, near = Interp.scalar(keys, 'dofNear', i, x, 1), far = Interp.scalar(keys, 'dofFar', i, x, 50) }
    end
    return Interp.vec3(keys, 'pos', i, x, false), Interp.vec3(keys, 'rot', i, x, true), Interp.scalar(keys, 'fov', i, x, DEFAULT_FOV), dof
end

--- Clip de animación activo en t: { dict, clip, phase (0-1) } o nil.
--- Un clip dura `duration` ms; con loop la animación se repite cada `length` ms, sin loop se queda en el último frame.
function Evaluate.anim(clips, t)
    local active
    for _, c in ipairs(clips or {}) do
        if t >= c.start and t < c.start + c.duration then active = c end
    end
    if not active then return nil end
    local elapsed = t - active.start
    local phase
    if active.loop then
        phase = (elapsed % active.length) / active.length
    else
        phase = math.min(elapsed / active.length, 1.0)
    end
    return { dict = active.dict, clip = active.clip, phase = phase }
end

--- ¿Visible en t? La key más reciente manda; antes de la primera vale la primera; sin keys, visible.
function Evaluate.visible(keys, t)
    if not keys or #keys == 0 then return true end
    local i = Interp.segment(keys, t)
    return keys[i].visible
end

--- Opacidad del fundido a negro en t (0 transparente, 1 negro). Cada key 'fade' va de la opacidad previa a `to`.
function Evaluate.fade(events, t)
    local alpha = 0.0
    for _, k in ipairs(events or {}) do
        if k.type == 'fade' then
            if k.t > t then break end
            local progress = k.duration > 0 and Interp.clamp01((t - k.t) / k.duration) or 1
            alpha = alpha + (k.to - alpha) * progress
        end
    end
    return alpha
end

--- Texto del subtítulo visible en t, o nil.
function Evaluate.subtitle(events, t)
    local text
    for _, k in ipairs(events or {}) do
        if k.t > t then break end
        if k.type == 'subtitle' and t < k.t + k.duration then text = k.text end
    end
    return text
end

--- Nombres de triggers con t0 < key.t <= t1, en orden. Sirve para dispararlos una sola vez por frame.
function Evaluate.triggers(events, t0, t1)
    local out = {}
    for _, k in ipairs(events or {}) do
        if k.t > t1 then break end
        if k.type == 'trigger' and k.t > t0 then out[#out + 1] = k.name end
    end
    return out
end

--- Estado completo en t.
--- { entities = { [id] = { pos, rot, anim, visible } }, camera = { pos, rot, fov } | nil, fade, subtitle }
function Evaluate.scene(prepared, t)
    local entities = {}
    for _, entity in ipairs(prepared.data.entities or {}) do
        local id = entity.id
        local pos, rot = Evaluate.transform(prepared.transform[id], t)
        entities[id] = { pos = pos, rot = rot, anim = Evaluate.anim(prepared.anim[id], t), visible = Evaluate.visible(prepared.visibility[id], t) }
    end

    local camera
    local camPos, camRot, camFov, camDof = Evaluate.camera(prepared.camera, t)
    if camPos then camera = { pos = camPos, rot = camRot, fov = camFov, dof = camDof } end

    return {
        entities = entities,
        camera = camera,
        fade = Evaluate.fade(prepared.events, t),
        subtitle = Evaluate.subtitle(prepared.events, t),
    }
end

return Evaluate
