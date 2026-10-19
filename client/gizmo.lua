-- Gizmo nativo de CFX (DRAW_GIZMO, 0xEB2EDCA2) sobre la matriz de la entidad, con el cursor del juego.
-- Técnica de object_gizmo: el native escribe la matriz modificada en el buffer que recibe.
-- Pendiente de verificar in-game; alternativa del plan: flechas propias + raycast.
Gizmo = {}

local running = false

local MATRIX_FORMAT = '<ffffffffffffffff'

RegisterKeyMapping('+gizmoSelect', 'dwkambience: seleccionar eje del gizmo', 'MOUSE_BUTTON', 'MOUSE_LEFT')
RegisterKeyMapping('+gizmoTranslation', 'dwkambience: gizmo en modo mover', 'keyboard', 'W')
RegisterKeyMapping('+gizmoRotation', 'dwkambience: gizmo en modo rotar', 'keyboard', 'R')
RegisterKeyMapping('+gizmoLocal', 'dwkambience: gizmo en ejes locales', 'keyboard', 'L')

local function packMatrix(handle)
    local forward, right, up, pos = GetEntityMatrix(handle)
    return string.pack(MATRIX_FORMAT,
        right.x, right.y, right.z, 0.0,
        forward.x, forward.y, forward.z, 0.0,
        up.x, up.y, up.z, 0.0,
        pos.x, pos.y, pos.z, 1.0)
end

local function applyMatrix(handle, buffer)
    local rx, ry, rz, _, fx, fy, fz, _, ux, uy, uz, _, px, py, pz = string.unpack(MATRIX_FORMAT, buffer)
    SetEntityMatrix(handle, fx, fy, fz, rx, ry, rz, ux, uy, uz, px, py, pz)
end

local function pulse(command)
    ExecuteCommand('+' .. command)
    ExecuteCommand('-' .. command)
end

function Gizmo.isRunning()
    return running
end

--- Bloquea hasta que el usuario confirma (Enter) o cancela (Esc / Retroceso).
--- mode: 'translate' | 'rotate'. Devuelve true si se confirmó.
function Gizmo.run(handle, mode)
    if running or not DoesEntityExist(handle) then return false end
    running = true

    local startPos = GetEntityCoords(handle)
    local startRot = GetEntityRotation(handle, 2)

    pulse(mode == 'rotate' and 'gizmoRotation' or 'gizmoTranslation')
    EnterCursorMode()

    local confirmed
    while confirmed == nil and DoesEntityExist(handle) do
        DisableAllControlActions(0)
        local buffer = packMatrix(handle)
        local changed = Citizen.InvokeNative(0xEB2EDCA2, buffer, 'Editor1', Citizen.ReturnResultAnyway())
        if changed then applyMatrix(handle, buffer) end

        if IsDisabledControlJustPressed(0, 191) then -- Enter
            confirmed = true
        elseif IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then -- Esc / Retroceso
            confirmed = false
        end
        Wait(0)
    end

    LeaveCursorMode()

    if confirmed == false and DoesEntityExist(handle) then
        SetEntityCoordsNoOffset(handle, startPos.x, startPos.y, startPos.z, false, false, false)
        SetEntityRotation(handle, startRot.x, startRot.y, startRot.z, 2, true)
    end

    running = false
    return confirmed == true
end
