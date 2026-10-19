Permissions = {}

local QBCore

local function getQB()
    if QBCore == nil and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
    end
    return QBCore
end

--- ¿Puede este jugador usar el editor? ACE primero, grupos de QB-Core como alternativa.
function Permissions.canEdit(src)
    if not src or src <= 0 then return false end
    if IsPlayerAceAllowed(src, Config.Ace) then return true end

    local qb = getQB()
    if qb then
        for _, group in ipairs(Config.QBGroups) do
            if qb.Functions.HasPermission(src, group) then return true end
        end
    end

    return false
end
