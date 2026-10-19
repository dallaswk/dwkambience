-- Grabación en vivo (REC): el editor controla su propio personaje (o el coche en el que va) y la
-- trayectoria se convierte en keys de la entidad seleccionada. El timeline avanza mientras tanto.
Recorder = {}

local cfg = Config.Recording
local recording = false
local restore -- devuelve al jugador a su sitio (también si el recurso se para a mitad)

function Recorder.isActive()
    return recording
end

local function drawStatus(elapsed)
    SetTextFont(4)
    SetTextScale(0.0, 0.45)
    SetTextColour(255, 80, 80, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('REC %02d:%02d · %s'):format(elapsed // 60, elapsed % 60, Recorder.hint or ''))
    EndTextCommandDisplayText(0.5, 0.06)
end

local function teleport(target, pos, heading)
    SetEntityCoordsNoOffset(target, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(target, heading)
end

--- Graba hasta que se pulsa Retroceso o se llega al máximo.
--- opts = { kind = 'ped' | 'vehicle', from = { pos, rot } (pose inicial), startT, tick = function(t), hint }
--- Devuelve las keys simplificadas (Rdp.toKeys) o nil, error. Bloquea: llamar desde un hilo propio.
function Recorder.run(opts)
    if recording then return nil, 'busy' end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if opts.kind == 'vehicle' and vehicle == 0 then return nil, 'need_vehicle' end
    local target = (opts.kind == 'vehicle' and vehicle ~= 0) and vehicle or ped

    recording = true
    Recorder.hint = opts.hint

    -- Se lleva al jugador (o su coche) a la pose de la entidad y luego se le devuelve a donde estaba
    local home, homeHeading = GetEntityCoords(target), GetEntityHeading(target)
    restore = function()
        if DoesEntityExist(target) then teleport(target, home, homeHeading) end
    end
    FreezeEntityPosition(ped, false)
    if opts.from then
        teleport(target, vector3(opts.from.pos[1], opts.from.pos[2], opts.from.pos[3]), opts.from.rot[3] + 0.0)
    end

    local samples = {}
    local started = GetGameTimer()
    local lastSample = -cfg.sampleMs
    while true do
        local elapsed = GetGameTimer() - started
        if elapsed >= cfg.maxSeconds * 1000 then break end

        if elapsed - lastSample >= cfg.sampleMs then
            local pos, rot = GetEntityCoords(target), GetEntityRotation(target, 2)
            samples[#samples + 1] = {
                t = elapsed,
                pos = { Util.round(pos.x, 3), Util.round(pos.y, 3), Util.round(pos.z, 3) },
                rot = { Util.round(rot.x, 2), Util.round(rot.y, 2), Util.round(rot.z, 2) },
            }
            lastSample = elapsed
        end

        if opts.tick then opts.tick(opts.startT + elapsed) end
        DisableControlAction(0, cfg.stopControl, true)
        HideHudComponentThisFrame(19) -- rueda de armas
        drawStatus(elapsed // 1000)
        if IsDisabledControlJustPressed(0, cfg.stopControl) then break end
        Wait(0)
    end

    restore()
    restore = nil
    FreezeEntityPosition(ped, true)
    recording = false

    if #samples < 2 then return nil, 'too_short' end
    return Rdp.toKeys(samples, cfg.epsilon, opts.startT)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and recording and restore then
        restore()
        FreezeEntityPosition(PlayerPedId(), false)
    end
end)
