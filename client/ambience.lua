-- Ambiences en vivo: se crean al entrar en su zona y se limpian al salir, en bucle y sin quitar el control.
-- Todos los clientes calculan t = tiempo de red % duración, así que ven el bucle en el mismo punto.

local index = {} -- [id] = { id, name, active, schedule, trigger, version }
local live = {}  -- [id] = runtime
local cache = {} -- [id] = { version, data }
local worldOwner -- ambience cuyo clima/hora se está aplicando

local cfg = Config.Ambience

local function minutes(hhmm)
    local h, m = hhmm:match('^(%d+):(%d+)$')
    return tonumber(h) * 60 + tonumber(m)
end

--- ¿Está dentro de su franja horaria? Usa la hora del juego; admite franjas que cruzan medianoche.
local function inSchedule(schedule)
    if not schedule then return true end
    local now = GetClockHours() * 60 + GetClockMinutes()
    local from, to = minutes(schedule.from), minutes(schedule.to)
    if from <= to then return now >= from and now < to end
    return now >= from or now < to
end

local function group(id)
    return 'amb_' .. id
end

local function stop(id)
    local rt = live[id]
    if not rt then return end
    live[id] = nil
    TriggerServerEvent('dwkambience:ambiencePresence', id, false)
    if rt.pool then rt.pool:clear() end
    Audio3D.clear(group(id))
    SendNUIMessage({ action = 'music', data = { group = group(id), state = 'stop' } })
    if worldOwner == id then
        World.restore()
        worldOwner = nil
    end
end

local function stopAll()
    for id in pairs(live) do stop(id) end
end

local function start(id, entry)
    local rt = { entry = entry, loading = true }
    live[id] = rt
    TriggerServerEvent('dwkambience:ambiencePresence', id, true)

    CreateThread(function()
        local cached = cache[id]
        if not cached or cached.version ~= entry.version then
            local result = lib.callback.await('dwkambience:ambienceData', false, id)
            if not result or live[id] ~= rt then
                if live[id] == rt then live[id] = nil end
                return
            end
            cached = { version = result.version, data = result.data }
            cache[id] = cached
        end
        if live[id] ~= rt then return end

        rt.prepared = Evaluate.prepare(cached.data)
        rt.settings = cached.data.settings
        rt.duration = math.max(Scene.stats(cached.data).durationMs, 1000)
        rt.pool = EntityPool.new({ skipNetworked = true })
        rt.pool:load(rt.prepared, GetNetworkTimeAccurate() % rt.duration)
        rt.loading = false

        Audio3D.set(group(id), rt.pool:emitters())
        SendNUIMessage({ action = 'music', data = {
            group = group(id), state = 'start',
            clips = rt.prepared.audio.music or {},
            t = GetNetworkTimeAccurate() % rt.duration, loop = rt.duration,
        } })
    end)
end

local function setIndex(list)
    index = {}
    for _, entry in ipairs(list or {}) do index[entry.id] = entry end
    -- Los que ya no existen o han cambiado de versión se paran; el bucle de zona los reanuda si toca
    for id, rt in pairs(live) do
        local entry = index[id]
        if not entry or entry.version ~= rt.entry.version then stop(id) end
    end
end

RegisterNetEvent('dwkambience:ambienceIndex', setIndex)

CreateThread(function()
    setIndex(lib.callback.await('dwkambience:ambienceIndex', false))
end)

local function totalPeds()
    local n = 0
    for _, rt in pairs(live) do
        if rt.pool then n = n + rt.pool:pedCount() end
    end
    return n
end

-- Entrada y salida de zona
CreateThread(function()
    while true do
        if Editor.isOpen() then
            -- El editor monta sus propias escenas: los ambiences en vivo se apartan mientras está abierto
            stopAll()
        else
            local pos = GetEntityCoords(PlayerPedId())
            for id, entry in pairs(index) do
                local c = entry.trigger.center
                local distance = #(pos - vector3(c[1], c[2], c[3]))
                local allowed = entry.active and inSchedule(entry.schedule)
                if live[id] then
                    if not allowed or distance > entry.trigger.exit then stop(id) end
                elseif allowed and distance <= entry.trigger.enter then
                    start(id, entry)
                end
            end
        end
        Wait(cfg.checkIntervalMs)
    end
end)

-- Clima/hora del ambience más cercano (salvo durante una cutscene, que manda sobre el mundo)
local function updateWorld(pos)
    if Player.isActive() then return end
    local best, bestDistance
    for id, rt in pairs(live) do
        if not rt.loading then
            local c = rt.entry.trigger.center
            local d = #(pos - vector3(c[1], c[2], c[3]))
            if not bestDistance or d < bestDistance then best, bestDistance = id, d end
        end
    end
    if best then
        World.apply(live[best].settings, worldOwner ~= best)
        worldOwner = best
    elseif worldOwner then
        World.restore()
        worldOwner = nil
    end
end

local function drawDebug()
    local count, lines = 0, {}
    for id, rt in pairs(live) do
        count = count + 1
        lines[#lines + 1] = ('#%d %s%s'):format(id, rt.entry.name, rt.loading and ' (cargando)' or '')
    end
    SetTextFont(4)
    SetTextScale(0.0, 0.3)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('ambiences %d · peds %d/%d · %.1f ms/frame~n~%s'):format(
        count, totalPeds(), cfg.maxPedsTotal, GetFrameTime() * 1000, table.concat(lines, '~n~')))
    EndTextCommandDisplayText(0.01, 0.3)
end

-- Bucle por frame: timeline en bucle, multitudes por distancia, audio y clima
CreateThread(function()
    local lastCrowds, lastWorld, lastAudio, lastSync = 0, 0, 0, 0
    while true do
        if not next(live) then
            Wait(500)
        else
            local now = GetNetworkTimeAccurate()
            local clock = GetGameTimer()
            local pos = GetEntityCoords(PlayerPedId())

            local camPos = GetFinalRenderedCamCoord()
            for _, rt in pairs(live) do
                if not rt.loading then
                    rt.pool:applyState(Evaluate.scene(rt.prepared, now % rt.duration))
                    rt.pool:drawFx(camPos)
                end
            end

            if clock - lastCrowds > 1000 then
                local budget = { left = cfg.maxPedsTotal - totalPeds() }
                for _, rt in pairs(live) do
                    if not rt.loading then
                        rt.pool:updateCrowds(pos, cfg.crowdSpawnDistance, cfg.crowdDespawnDistance, budget)
                    end
                end
                lastCrowds = clock
            end

            if clock - lastWorld > 250 then
                updateWorld(pos)
                lastWorld = clock
            end

            -- Los emisores pueden moverse con su pista: se reenvían dos veces por segundo
            if clock - lastAudio > 500 then
                for id, rt in pairs(live) do
                    if not rt.loading then Audio3D.set(group(id), rt.pool:emitters()) end
                end
                lastAudio = clock
            end

            if clock - lastSync > 1000 then
                for id, rt in pairs(live) do
                    if not rt.loading then
                        SendNUIMessage({ action = 'music', data = { group = group(id), state = 'sync', t = now % rt.duration } })
                    end
                end
                lastSync = clock
            end

            if GetConvarInt(Config.DebugConvar, 0) == 1 then drawDebug() end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stopAll() end
end)
