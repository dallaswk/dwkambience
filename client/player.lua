-- Reproducción de cutscenes en el cliente. Todos los clientes calculan t = tiempo de red - startAt,
-- así que ven lo mismo en el mismo instante aunque el evento les llegue en momentos distintos.

local active -- sesión en curso

local LETTERBOX = 0.1 -- alto de cada franja, en fracción de pantalla

lib.callback.register('dwkambience:netTime', function()
    return GetNetworkTimeAccurate()
end)

local function netNow()
    return GetNetworkTimeAccurate()
end

local function fade(out)
    if out then
        DoScreenFadeOut(Config.Playback.fadeMs)
        while not IsScreenFadedOut() do Wait(0) end
    else
        DoScreenFadeIn(Config.Playback.fadeMs)
    end
end

local function preloadModels(data, deadline)
    local hashes = {}
    for _, entity in ipairs(data.entities or {}) do
        if entity.kind == 'ptfx' and entity.ptfx then RequestNamedPtfxAsset(entity.ptfx.asset) end
        if entity.kind == 'ped' or entity.kind == 'vehicle' or entity.kind == 'prop' then
            local hash = joaat(entity.model)
            if IsModelInCdimage(hash) then
                RequestModel(hash)
                hashes[#hashes + 1] = hash
            end
        end
    end
    local pending = true
    while pending and netNow() < deadline do
        pending = false
        for _, hash in ipairs(hashes) do
            if not HasModelLoaded(hash) then pending = true end
        end
        if pending then Wait(50) end
    end
end

local function drawText2D(text, x, y, scale)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    SetTextWrap(0.15, 0.85)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawOverlay(state, settings, debug, t)
    if not settings.output.hud then
        HideHudAndRadarThisFrame()
    end
    if settings.output.letterbox then
        DrawRect(0.5, LETTERBOX / 2, 1.0, LETTERBOX, 0, 0, 0, 255)
        DrawRect(0.5, 1.0 - LETTERBOX / 2, 1.0, LETTERBOX, 0, 0, 0, 255)
    end
    if state.subtitle then
        drawText2D(state.subtitle, 0.5, settings.output.letterbox and 0.835 or 0.88, 0.45)
    end
    if state.fade > 0 then
        DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, math.floor(state.fade * 255))
    end
    if debug then
        drawText2D(('session %d · t %d ms · late %d ms'):format(active.session, t, active.lateMs or 0), 0.5, 0.02, 0.3)
    end
end

local function stop(skipped, immediate)
    local a = active
    if not a or a.stopping then return end
    a.stopping = true

    if not immediate then fade(true) end

    a.pool:clear()
    RenderScriptCams(false, false, 0, true, true)
    if a.cam then DestroyCam(a.cam, false) end
    ClearFocus()
    Audio3D.clear('cutscene')
    World.restore()
    DisplayRadar(true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)

    SendNUIMessage({ action = 'music', data = { group = 'cutscene', state = 'stop' } })
    active = nil

    if not immediate then fade(false) end

    if a.onEnd then
        a.onEnd(skipped == true)
    elseif not immediate then
        TriggerServerEvent('dwkambience:playbackEnded', a.session, skipped == true)
        TriggerEvent('dwkambience:finished', a.sceneId, skipped == true)
    end
end

local function musicClips(prepared)
    return prepared.audio.music or {}
end

-- onEnd: solo para la previsualización del editor (no avisa al servidor ni emite finished)
local function run(payload, onEnd)
    if not onEnd and Editor.isOpen() then
        TriggerServerEvent('dwkambience:playbackEnded', payload.session, false)
        return
    end
    if active then stop(false) end

    local prepared = Evaluate.prepare(payload.data)
    local settings = payload.data.settings
    local a = {
        session = payload.session,
        sceneId = payload.sceneId,
        startAt = payload.startAt,
        duration = payload.duration,
        skippable = payload.skippable,
        prepared = prepared,
        pool = EntityPool.new(),
        onEnd = onEnd,
    }
    active = a

    fade(true)
    preloadModels(payload.data, a.startAt - 300)
    if active ~= a then return end

    a.pool:load(prepared, 0)

    -- Multitudes: toda la gente se crea durante la pantalla en negro (las cutscenes no usan distancia)
    local budget = { left = Config.Studios[Config.DefaultStudio].maxEntities }
    repeat
        a.pool:updateCrowds(GetEntityCoords(PlayerPedId()), 100000.0, 100001.0, budget)
        Wait(50)
    until a.pool:crowdsReady() or netNow() >= a.startAt - 100 or active ~= a
    if active ~= a then return end
    Audio3D.set('cutscene', a.pool:emitters())

    local camPos, camRot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    a.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, camRot.x, camRot.y, camRot.z, 50.0, true, 2)
    RenderScriptCams(true, false, 0, true, true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    World.apply(settings, true)

    SendNUIMessage({ action = 'music', data = { group = 'cutscene', state = 'start', clips = musicClips(prepared), t = netNow() - a.startAt } })

    -- Pantalla en negro hasta t = 0
    while active == a and netNow() < a.startAt do
        a.pool:applyState(Evaluate.scene(prepared, 0))
        Wait(0)
    end
    if active ~= a then return end

    a.lateMs = math.max(0, netNow() - a.startAt)
    fade(false)

    local debug = GetConvarInt(Config.DebugConvar, 0) == 1
    local lastT, lastSync, lastWeather = -1, 0, 0

    while active == a and not a.stopping do
        local now = netNow()
        local t = now - a.startAt
        if t >= a.duration then
            stop(false)
            break
        end

        local state = Evaluate.scene(prepared, t)
        a.pool:applyState(state)

        if state.camera then
            local c = state.camera
            SetCamCoord(a.cam, c.pos[1], c.pos[2], c.pos[3])
            SetCamRot(a.cam, c.rot[1], c.rot[2], c.rot[3], 2)
            SetCamFov(a.cam, c.fov)
            SetFocusPosAndVel(c.pos[1], c.pos[2], c.pos[3], 0.0, 0.0, 0.0)
        end

        for _, name in ipairs(Evaluate.triggers(prepared.events, lastT, t)) do
            TriggerEvent('dwkambience:trigger', a.sceneId, name)
        end
        lastT = t

        if now - lastWeather > 250 then
            World.apply(settings, false)
            lastWeather = now
        end
        if now - lastSync > 1000 then
            SendNUIMessage({ action = 'music', data = { group = 'cutscene', state = 'sync', t = t } })
            lastSync = now
        end
        -- Los emisores pueden moverse con su pista
        if now - (a.lastAudio or 0) > 500 then
            Audio3D.set('cutscene', a.pool:emitters())
            a.lastAudio = now
        end

        DisableAllControlActions(0)
        a.pool:drawFx(GetFinalRenderedCamCoord())
        drawOverlay(state, settings, debug, t)

        if a.skippable and IsDisabledControlJustPressed(0, Config.Playback.skipControl) then
            stop(true)
            break
        end

        Wait(0)
    end
end

RegisterNetEvent('dwkambience:play', function(payload)
    run(payload)
end)

Player = {
    --- Reproduce localmente datos de escena sin servidor (Previsualizar cutscene del editor).
    preview = function(data, sceneId, onEnd)
        run({
            session = 0,
            sceneId = sceneId,
            data = data,
            startAt = netNow() + 1000,
            duration = Scene.stats(data).durationMs,
            skippable = true,
        }, onEnd)
    end,
    isActive = function() return active ~= nil end,
}

RegisterNetEvent('dwkambience:stop', function(session)
    if active and active.session == session then stop(false) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then stop(false, true) end
end)
