-- Personas de una multitud en el mundo. Se colocan con Crowd.layout (igual en todos los clientes)
-- y solo existen cerca del jugador: aparecen a menos de spawnDistance y desaparecen pasado despawnDistance.
CrowdSet = {}
CrowdSet.__index = CrowdSet

function CrowdSet.new(crowd)
    local preset = Config.CrowdPresets[crowd.preset] or Config.CrowdPresets.custom
    return setmetatable({
        crowd = crowd,
        members = Crowd.layout(crowd, preset),
        handles = {},
        spawned = 0,
    }, CrowdSet)
end

local function groundZ(pos)
    local found, z = GetGroundZFor_3dCoord(pos[1] + 0.0, pos[2] + 0.0, pos[3] + 2.0, false)
    return found and z + 1.0 or pos[3] + 0.0
end

-- Crea una persona si su modelo ya está cargado; si no, lo pide y devuelve nil (se reintenta luego)
local function spawnMember(m)
    local hash = joaat(m.model)
    if not IsModelInCdimage(hash) then return false end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        return nil
    end
    -- Sin el diccionario cargado la persona se quedaría quieta para siempre: se reintenta luego
    if m.anim and not HasAnimDictLoaded(m.anim.dict) then
        if not DoesAnimDictExist(m.anim.dict) then return false end
        RequestAnimDict(m.anim.dict)
        return nil
    end

    local ped = CreatePed(4, hash, m.pos[1] + 0.0, m.pos[2] + 0.0, groundZ(m.pos), m.heading + 0.0, false, false)
    if not ped or ped == 0 then return false end
    SetEntityAsMissionEntity(ped, true, true)
    SetPedDefaultComponentVariation(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    if m.scenario then
        TaskStartScenarioInPlace(ped, m.scenario, 0, true)
    elseif m.anim then
        TaskPlayAnim(ped, m.anim.dict, m.anim.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
        SetEntityAnimCurrentTime(ped, m.anim.dict, m.anim.clip, m.phase)
    end
    return ped
end

--- Crea o borra personas según la distancia a origin. budget = { left = n } se comparte entre multitudes.
function CrowdSet:update(origin, spawnDistance, despawnDistance, budget)
    for i, m in ipairs(self.members) do
        local d = #(origin - vector3(m.pos[1], m.pos[2], m.pos[3]))
        local ped = self.handles[i]
        if ped and (d > despawnDistance or not DoesEntityExist(ped)) then
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            self.handles[i] = nil
            self.spawned = self.spawned - 1
        elseif not ped and d < spawnDistance and budget.left > 0 then
            local created = spawnMember(m)
            if created then
                self.handles[i] = created
                self.spawned = self.spawned + 1
                budget.left = budget.left - 1
            elseif created == false then
                self.handles[i] = nil
            end
        end
    end
end

--- Miembro (índice) cuyo ped es este handle, para seleccionar la multitud con el ratón
function CrowdSet:owns(handle)
    for _, ped in pairs(self.handles) do
        if ped == handle then return true end
    end
    return false
end

function CrowdSet:each()
    return pairs(self.handles)
end

function CrowdSet:clear()
    for i, ped in pairs(self.handles) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
        self.handles[i] = nil
    end
    self.spawned = 0
end
