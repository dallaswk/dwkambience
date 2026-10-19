-- Audio 3D: los emisores se reproducen en la NUI con Web Audio y aquí se le manda dónde está y adónde
-- mira la cámara 20 veces por segundo. Cada sistema (editor, cada ambience) usa su propio grupo.
Audio3D = {}

local groups = {}

--- emitters: { { id, asset, volume, range, loop, pos = {x, y, z} } }
function Audio3D.set(group, emitters)
    groups[group] = true
    SendNUIMessage({ action = 'audio3d', data = { op = 'set', group = group, emitters = emitters } })
end

function Audio3D.clear(group)
    if not groups[group] then return end
    groups[group] = nil
    SendNUIMessage({ action = 'audio3d', data = { op = 'clear', group = group } })
end

CreateThread(function()
    while true do
        if next(groups) then
            local pos = GetFinalRenderedCamCoord()
            local forward, _, up = Util.rotAxes(GetFinalRenderedCamRot(2))
            SendNUIMessage({ action = 'audio3d', data = {
                op = 'listener',
                pos = { pos.x, pos.y, pos.z },
                forward = { forward.x, forward.y, forward.z },
                up = { up.x, up.y, up.z },
            } })
            Wait(50)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for group in pairs(groups) do Audio3D.clear(group) end
end)
