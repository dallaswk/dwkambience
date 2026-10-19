-- Entidades en red de los ambiences: el servidor las crea una sola vez (OneSync) cuando entra el primer
-- jugador en la zona y las borra cuando sale el último, al apagar el ambience o al cambiar de versión.
-- Son estáticas: quedan en su pose inicial para que los jugadores puedan interactuar con ellas.
NetEnts = {}

local presence = {} -- [ambienceId] = { [src] = true }
local spawned = {}  -- [ambienceId] = { handles }
local pedTasks = {} -- [ambienceId] = { { netId, scenario, anim } } para los peds en red

local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true, train = true }

local function count(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

local function despawn(id)
    for _, handle in ipairs(spawned[id] or {}) do
        if DoesEntityExist(handle) then DeleteEntity(handle) end
    end
    spawned[id] = nil
    pedTasks[id] = nil
end

--- Manda a los jugadores de la zona qué escenario/animación lleva cada ped en red
local function sendTasks(id, target)
    local list = pedTasks[id] or {}
    if target then
        TriggerClientEvent('dwkambience:netPeds', target, id, list)
        return
    end
    for src in pairs(presence[id] or {}) do TriggerClientEvent('dwkambience:netPeds', src, id, list) end
end

local function spawn(id)
    local entry, data = Ambience.get(id)
    if not entry or not entry.active or not data then return end
    despawn(id)
    local handles, tasks = {}, {}
    for _, entity in ipairs(data.entities or {}) do
        if entity.networked and Scene.GAME_KINDS[entity.kind] then
            local pos, rot = Scene.baseTransform(data, entity.id)
            if pos then
                local hash = joaat(entity.model)
                local x, y, z, heading = pos[1] + 0.0, pos[2] + 0.0, pos[3] + 0.0, rot[3] + 0.0
                local handle
                if entity.kind == 'ped' then
                    handle = CreatePed(4, hash, x, y, z, heading, true, true)
                elseif entity.kind == 'vehicle' then
                    local vtype = VEHICLE_TYPES[entity.props.vehicleType] and entity.props.vehicleType or 'automobile'
                    handle = CreateVehicleServerSetter(hash, vtype, x, y, z, heading)
                else
                    handle = CreateObjectNoOffset(hash, x, y, z, true, true, false)
                end

                -- La creación en el servidor es asíncrona: se espera a que exista para ajustarla
                local deadline = GetGameTimer() + 3000
                while handle and handle ~= 0 and not DoesEntityExist(handle) and GetGameTimer() < deadline do Wait(0) end
                if handle and handle ~= 0 and DoesEntityExist(handle) then
                    SetEntityRotation(handle, rot[1] + 0.0, rot[2] + 0.0, rot[3] + 0.0, 2, true)
                    SetEntityOrphanMode(handle, 2) -- no se borra si su dueño de red se desconecta
                    if entity.kind ~= 'vehicle' then FreezeEntityPosition(handle, true) end
                    handles[#handles + 1] = handle
                    local p = entity.props or {}
                    if entity.kind == 'ped' and (p.scenario or (type(p.anim) == 'table' and p.anim.dict)) then
                        tasks[#tasks + 1] = {
                            netId = NetworkGetNetworkIdFromEntity(handle),
                            scenario = p.scenario,
                            anim = type(p.anim) == 'table' and p.anim or nil,
                        }
                    end
                else
                    print(('[dwkambience] no se pudo crear en red %s (%s) del ambience #%d'):format(entity.id, entity.model, id))
                end
            end
        end
    end
    spawned[id] = handles
    pedTasks[id] = tasks
    sendTasks(id)
end

--- El ambience cambió (guardado, activado/apagado, borrado): se rehacen sus entidades si hay alguien dentro
function NetEnts.reset(id)
    despawn(id)
    local entry = Ambience.get(id)
    if entry and entry.active and count(presence[id]) > 0 then
        CreateThread(function() spawn(id) end)
    elseif not entry then
        presence[id] = nil
    end
end

local function setPresence(src, id, inside)
    presence[id] = presence[id] or {}
    local before = count(presence[id])
    presence[id][src] = inside or nil
    local after = count(presence[id])
    if before == 0 and after > 0 then
        spawn(id)
    elseif inside and after > before then
        sendTasks(id, src) -- quien llega puede acabar siendo dueño de alguno
    elseif before > 0 and after == 0 then
        despawn(id)
    end
end

RegisterNetEvent('dwkambience:ambiencePresence', function(id, inside)
    local src = source
    id = math.tointeger(tonumber(id))
    if not id or not Ambience.get(id) then return end
    setPresence(src, id, inside == true)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, set in pairs(presence) do
        if set[src] then setPresence(src, id, false) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)
