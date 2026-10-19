-- Cámara libre del editor. Solo se mueve mientras `active` es true (botón derecho sobre el viewport).
Freecam = {}

local cam
local pos, rot
local fov = Config.Freecam.fov
local speedMultiplier = 1.0

local CONTROL = {
    lookX = 1, lookY = 2,
    forward = 32, back = 33, left = 34, right = 35,
    down = 44, up = 38,
    fast = 21, slow = 36,
}

function Freecam.start(startPos, startRot)
    pos = startPos
    rot = vector3(startRot.x, 0.0, startRot.z)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, fov, true, 2)
    RenderScriptCams(true, false, 0, true, true)
end

function Freecam.stop()
    if not cam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    ClearFocus()
    cam = nil
end

function Freecam.isActive()
    return cam ~= nil
end

function Freecam.get()
    return pos, rot, fov
end

function Freecam.setSpeedMultiplier(value)
    speedMultiplier = math.max(0.1, math.min(10.0, value + 0.0))
end

--- Vuelve a renderizar la free cam (otra cámara de script la sustituyó, p. ej. una previsualización)
function Freecam.reactivate()
    if not cam then return end
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

function Freecam.setFov(value)
    fov = math.max(1.0, math.min(130.0, value + 0.0))
end

function Freecam.set(newPos, newRot)
    pos = newPos
    if newRot then rot = vector3(newRot.x, 0.0, newRot.z) end
end

--- Coloca la cámara mirando a un punto desde una distancia.
function Freecam.lookAt(target, distance)
    local forward = Util.rotAxes(rot)
    pos = target - forward * (distance or 6.0)
end

function Freecam.update(dt, active)
    if not cam then return end

    if active then
        local cfg = Config.Freecam
        local lookX = GetDisabledControlNormal(0, CONTROL.lookX)
        local lookY = GetDisabledControlNormal(0, CONTROL.lookY)
        rot = vector3(math.max(-89.0, math.min(89.0, rot.x - lookY * cfg.sensitivity)), 0.0, rot.z - lookX * cfg.sensitivity)

        local speed = cfg.speed * speedMultiplier
        if IsDisabledControlPressed(0, CONTROL.fast) then speed = speed * cfg.fastMultiplier end
        if IsDisabledControlPressed(0, CONTROL.slow) then speed = speed * cfg.slowMultiplier end

        local forward, right = Util.rotAxes(rot)
        local move = forward * (GetDisabledControlNormal(0, CONTROL.forward) - GetDisabledControlNormal(0, CONTROL.back))
            + right * (GetDisabledControlNormal(0, CONTROL.right) - GetDisabledControlNormal(0, CONTROL.left))
            + vector3(0.0, 0.0, GetDisabledControlNormal(0, CONTROL.up) - GetDisabledControlNormal(0, CONTROL.down))

        pos = pos + move * (speed * dt)
    end

    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
end
