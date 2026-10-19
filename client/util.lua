Util = {}

local rad, sin, cos = math.rad, math.sin, math.cos

function Util.round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

function Util.vecToArray(v, decimals)
    return { Util.round(v.x, decimals), Util.round(v.y, decimals), Util.round(v.z, decimals) }
end

--- Ejes de una rotación de cámara (pitch x, yaw z, grados). Ignora el roll.
function Util.rotAxes(rot)
    local x, z = rad(rot.x), rad(rot.z)
    local forward = vector3(-sin(z) * cos(x), cos(z) * cos(x), sin(x))
    local right = vector3(cos(z), sin(z), 0.0)
    local up = vector3(sin(z) * sin(x), -cos(z) * sin(x), cos(x))
    return forward, right, up
end

--- Dirección del rayo que pasa por un punto de pantalla normalizado (0-1, origen arriba a la izquierda).
--- Asume que el FOV de la cámara es vertical.
function Util.screenRay(camRot, fov, nx, ny)
    local forward, right, up = Util.rotAxes(camRot)
    local w, h = GetActiveScreenResolution()
    local tanV = math.tan(rad(fov) / 2)
    local tanH = tanV * (w / h)
    local dir = forward + right * ((nx * 2 - 1) * tanH) + up * ((1 - ny * 2) * tanV)
    return dir / #dir
end

--- Raycast síncrono contra el mapa. Devuelve el punto de impacto o nil.
function Util.worldHit(from, to, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1, ignore or 0, 7)
    local _, hit, coords = GetShapeTestResult(handle)
    return hit == 1 and coords or nil
end

--- Profundidad de campo en una cámara de script. dof = { strength, near, far } o nil para quitarla.
--- SetUseHiDof tiene que llamarse cada frame mientras haya DOF (Util.tickDof).
function Util.applyDof(cam, dof)
    if dof then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, dof.near + 0.0)
        SetCamFarDof(cam, dof.far + 0.0)
        SetCamDofStrength(cam, dof.strength + 0.0)
    else
        SetCamUseShallowDofMode(cam, false)
        SetCamDofStrength(cam, 0.0)
    end
end

function Util.tickDof(dof)
    if dof then SetUseHiDof() end
end

function Util.loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    local ok = pcall(lib.requestModel, hash, 10000)
    return ok and hash or nil
end

function Util.drawText3D(coords, text, scale)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.0, scale or 0.28)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end
