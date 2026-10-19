-- Entidades locales de la escena abierta en el editor. Las pistas apuntan a ids; aquí se resuelven a handles.
Entities = {}

local spawned = {} -- [id] = { handle, kind, model, props }

local VEHICLE_DOORS = 5 -- 0 FL, 1 FR, 2 RL, 3 RR, 4 capó, 5 maletero

local function create(kind, hash, pos, rot)
    local handle
    if kind == 'ped' then
        handle = CreatePed(4, hash, pos.x, pos.y, pos.z, rot.z, false, false)
    elseif kind == 'vehicle' then
        handle = CreateVehicle(hash, pos.x, pos.y, pos.z, rot.z, false, false)
    elseif kind == 'prop' then
        handle = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    end
    if not handle or handle == 0 then return nil end

    SetEntityAsMissionEntity(handle, true, true)
    FreezeEntityPosition(handle, true)
    SetEntityInvincible(handle, true)

    if kind == 'ped' then
        SetBlockingOfNonTemporaryEvents(handle, true)
        SetPedCanRagdoll(handle, false)
        SetPedDefaultComponentVariation(handle)
    elseif kind == 'vehicle' then
        SetVehicleDoorsLocked(handle, 2)
    end

    return handle
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local function applyPedProps(handle, props, prev)
    if same(props.anim, prev.anim) and props.scenario == prev.scenario then return end

    ClearPedTasksImmediately(handle)
    local anim = props.anim
    if type(anim) == 'table' and anim.dict and anim.clip then
        local ok = pcall(lib.requestAnimDict, anim.dict, 5000)
        if ok then
            TaskPlayAnim(handle, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            RemoveAnimDict(anim.dict)
        end
    elseif type(props.scenario) == 'string' and props.scenario ~= '' then
        TaskStartScenarioInPlace(handle, props.scenario, 0, true)
    end
end

local function applyVehicleProps(handle, props)
    SetVehicleEngineOn(handle, props.engine == true, true, true)
    SetVehicleLights(handle, props.headlights and 2 or 1)
    SetVehicleSiren(handle, props.siren == true)
    SetVehicleDirtLevel(handle, math.max(0.0, math.min(15.0, (props.dirt or 0) + 0.0)))

    local open = {}
    for _, door in ipairs(type(props.doors) == 'table' and props.doors or {}) do open[door] = true end
    for door = 0, VEHICLE_DOORS do
        if open[door] then
            SetVehicleDoorOpen(handle, door, false, true)
        else
            SetVehicleDoorShut(handle, door, true)
        end
    end
end

local function setTransform(handle, pos, rot)
    SetEntityCoordsNoOffset(handle, pos[1] + 0.0, pos[2] + 0.0, pos[3] + 0.0, false, false, false)
    SetEntityRotation(handle, rot[1] + 0.0, rot[2] + 0.0, rot[3] + 0.0, 2, true)
end

--- Crea o actualiza una entidad para que coincida con su definición. pos/rot son arrays {x, y, z}.
--- Devuelve true o false, error.
function Entities.apply(entity, pos, rot)
    local current = spawned[entity.id]
    if current and (current.model ~= entity.model or current.kind ~= entity.kind) then
        Entities.remove(entity.id)
        current = nil
    end

    -- sound y crowd no tienen entidad de juego en la fase 0
    if entity.kind ~= 'ped' and entity.kind ~= 'vehicle' and entity.kind ~= 'prop' then
        spawned[entity.id] = { kind = entity.kind, model = entity.model, props = entity.props or {}, pos = pos }
        return true
    end

    pos = pos or { 0.0, 0.0, 0.0 }
    rot = rot or { 0.0, 0.0, 0.0 }

    if not current then
        local hash = Util.loadModel(entity.model)
        if not hash then return false, 'invalid_model' end
        local handle = create(entity.kind, hash, vector3(pos[1], pos[2], pos[3]), vector3(rot[1], rot[2], rot[3]))
        SetModelAsNoLongerNeeded(hash)
        if not handle then return false, 'spawn_failed' end
        current = { handle = handle, kind = entity.kind, model = entity.model, props = {} }
        spawned[entity.id] = current
    end

    setTransform(current.handle, pos, rot)

    local props = entity.props or {}
    if entity.kind == 'ped' then
        applyPedProps(current.handle, props, current.props)
    elseif entity.kind == 'vehicle' then
        applyVehicleProps(current.handle, props)
    end
    current.props = props
    current.label = entity.label

    return true
end

function Entities.remove(id)
    local current = spawned[id]
    if not current then return end
    if current.handle and DoesEntityExist(current.handle) then
        SetEntityAsMissionEntity(current.handle, true, true)
        DeleteEntity(current.handle)
    end
    spawned[id] = nil
end

function Entities.clear()
    for id in pairs(spawned) do Entities.remove(id) end
end

--- Carga todas las entidades de una escena en su transform base.
function Entities.loadScene(data)
    Entities.clear()
    local failed = {}
    for _, entity in ipairs(data.entities or {}) do
        local pos, rot = Scene.baseTransform(data, entity.id)
        local ok = Entities.apply(entity, pos, rot)
        if not ok then failed[#failed + 1] = entity.label end
    end
    return failed
end

function Entities.handle(id)
    local current = spawned[id]
    return current and current.handle
end

function Entities.label(id)
    local current = spawned[id]
    return current and current.label
end

function Entities.each()
    return pairs(spawned)
end

--- Transform actual de la entidad en el juego, redondeado para la NUI.
function Entities.transform(id)
    local handle = Entities.handle(id)
    if not handle or not DoesEntityExist(handle) then return nil end
    return Util.vecToArray(GetEntityCoords(handle), 3), Util.vecToArray(GetEntityRotation(handle, 2), 2)
end

--- Pega la entidad al suelo y devuelve su nuevo transform.
function Entities.ground(id)
    local current = spawned[id]
    if not current or not current.handle then return nil end
    local handle = current.handle

    FreezeEntityPosition(handle, false)
    if current.kind == 'vehicle' then
        SetVehicleOnGroundProperly(handle)
    elseif current.kind == 'prop' then
        PlaceObjectOnGroundProperly(handle)
    else
        local coords = GetEntityCoords(handle)
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
        if found then
            SetEntityCoordsNoOffset(handle, coords.x, coords.y, groundZ + 1.0, false, false, false)
        end
    end
    FreezeEntityPosition(handle, true)

    return Entities.transform(id)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Entities.clear() end
end)
