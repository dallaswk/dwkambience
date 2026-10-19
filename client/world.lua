-- Clima y hora de una escena aplicados solo a este jugador, con pausa de qb-weathersync.
World = {}

local overridden = false
local timecycle -- nombre del modificador aplicado, o nil

local function weatherSync(enabled)
    if GetResourceState('qb-weathersync') ~= 'started' then return end
    TriggerEvent(enabled and 'qb-weathersync:client:EnableSync' or 'qb-weathersync:client:DisableSync')
end

--- Aplica clima y hora. Conviene llamarlo de forma periódica (cada ~250 ms): qb-weathersync,
--- aun en pausa, fuerza su propio clima cada pocos segundos.
function World.apply(settings, force)
    if not overridden then
        weatherSync(false)
        overridden = true
        force = true
    end
    local h, m = settings.time:match('^(%d+):(%d+)$')
    NetworkOverrideClockTime(tonumber(h), tonumber(m), 0)
    if force or GetPrevWeatherTypeHashName() ~= GetHashKey(settings.weather) then
        SetWeatherTypeNowPersist(settings.weather)
        SetOverrideWeather(settings.weather)
    end

    local tc = settings.timecycle
    if tc then
        if force or timecycle ~= tc.name then
            SetTimecycleModifier(tc.name)
            timecycle = tc.name
        end
        SetTimecycleModifierStrength(tc.strength + 0.0)
    elseif timecycle then
        ClearTimecycleModifier()
        timecycle = nil
    end
end

function World.restore()
    if not overridden then return end
    overridden = false
    if timecycle then
        ClearTimecycleModifier()
        timecycle = nil
    end
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    NetworkClearClockTimeOverride()
    weatherSync(true)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then World.restore() end
end)
