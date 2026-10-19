-- Bloqueo por escena en memoria: un editor por escena, el resto en solo lectura.
Locks = {}

local owners = {}   -- [sceneId] = src
local sessions = {} -- [src] = sceneId

--- Intenta tomar el bloqueo. Devuelve true o false, src del dueño actual.
function Locks.acquire(sceneId, src)
    local owner = owners[sceneId]
    if owner and owner ~= src and GetPlayerName(owner) then
        return false, owner
    end

    local previous = sessions[src]
    if previous and previous ~= sceneId then Locks.release(previous, src) end

    owners[sceneId] = src
    sessions[src] = sceneId
    return true
end

function Locks.release(sceneId, src)
    if owners[sceneId] == src then owners[sceneId] = nil end
    if sessions[src] == sceneId then sessions[src] = nil end
end

function Locks.releaseAll(src)
    local sceneId = sessions[src]
    if sceneId then Locks.release(sceneId, src) end
end

function Locks.holds(sceneId, src)
    return owners[sceneId] == src
end

--- Nombre de quien edita la escena, o nil.
function Locks.ownerName(sceneId)
    local owner = owners[sceneId]
    return owner and GetPlayerName(owner) or nil
end

AddEventHandler('playerDropped', function()
    Locks.releaseAll(source)
end)
