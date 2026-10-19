-- Ciclo de vida del editor y puente con la NUI.

local isOpen = false
local camLook = false
local typing = false
local currentScene -- id de la escena abierta
local prepared     -- escena preparada para Evaluate
local currentT = 0
local cameraView = false
local savedCam     -- pose de la free cam antes de entrar en Camera view
local worldPreview = false -- clima y hora de la escena aplicados mientras se edita
local previewing = false   -- previsualizando la cutscene (el editor queda en pausa)

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- La NUI tiene el cursor; el juego sigue recibiendo teclado y ratón salvo mientras se escribe en un campo
local function setFocus()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(not typing)
end

local function editorLoop()
    local last, lastWorld = GetGameTimer(), 0
    while isOpen do
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now

        if previewing then
            Wait(100)
            goto continue
        end

        if worldPreview and prepared and now - lastWorld > 250 then
            World.apply(prepared.data.settings, false)
            lastWorld = now
        end

        if not Gizmo.isRunning() then
            DisableAllControlActions(0)
            Freecam.update(dt, camLook and not typing)
        end
        HideHudAndRadarThisFrame()
        Select.draw()
        Wait(0)
        ::continue::
    end
end

local function openEditor()
    if isOpen then return end
    isOpen = true
    camLook, typing = false, false

    FreezeEntityPosition(PlayerPedId(), true)
    Freecam.start(GetGameplayCamCoord(), GetGameplayCamRot(2))
    setFocus()
    send('open', { studios = Config.Studios, defaultStudio = Config.DefaultStudio, locale = Config.Locale })
    CreateThread(editorLoop)
end

--- Lleva la free cam a la pose de la pista de cámara en t (Camera view)
local function applyCamera(state)
    if not cameraView or not state.camera then return end
    local c = state.camera
    Freecam.set(vector3(c.pos[1], c.pos[2], c.pos[3]), vector3(c.rot[1], c.rot[2], c.rot[3]))
    Freecam.setFov(c.fov)
end

--- Coloca entidades (y cámara en Camera view) en su estado en currentT
local function applyTime()
    if not prepared then return end
    local state = Evaluate.scene(prepared, currentT)
    Entities:applyState(state)
    applyCamera(state)
end

local function setCameraView(active)
    if active == cameraView then return end
    cameraView = active
    if active then
        local pos, rot, fov = Freecam.get()
        savedCam = { pos = pos, rot = rot, fov = fov }
        applyTime()
    elseif savedCam then
        Freecam.set(savedCam.pos, savedCam.rot)
        Freecam.setFov(savedCam.fov)
        savedCam = nil
    end
end

local function closeScene()
    if currentScene then
        lib.callback.await('dwkambience:close', false, currentScene)
    end
    currentScene = nil
    prepared = nil
    Entities:clear()
    Select.set(nil)
    setCameraView(false)
    worldPreview = false
    World.restore()
end

-- Limpieza local sin hablar con el servidor (válida también en onResourceStop)
local function teardown()
    isOpen = false
    camLook, typing = false, false
    currentScene = nil
    prepared = nil
    cameraView, savedCam = false, nil
    worldPreview, previewing = false, false
    World.restore()
    Entities:clear()
    Select.set(nil)
    Freecam.stop()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    FreezeEntityPosition(PlayerPedId(), false)
end

local function closeEditor()
    if not isOpen then return end
    closeScene()
    teardown()
    send('close')
    TriggerServerEvent('dwkambience:editorClosed')
end

--- Monta en el mundo una escena recibida del servidor y lleva la cámara a ella.
local function loadScene(result)
    currentScene = result.meta.id
    currentT = 0
    Select.set(nil)
    prepared = Evaluate.prepare(result.data)
    result.failed = Entities:load(prepared, 0)

    local target
    for _, entity in ipairs(result.data.entities or {}) do
        local pos = Scene.baseTransform(result.data, entity.id)
        if pos then
            target = vector3(pos[1], pos[2], pos[3])
            break
        end
    end
    local trigger = result.data.settings.trigger
    if not target and trigger then
        target = vector3(trigger.center[1], trigger.center[2], trigger.center[3])
    end
    if target then Freecam.lookAt(target, 10.0) end
end

local function nui(name, handler)
    RegisterNUICallback(name, function(data, cb)
        if not isOpen then return cb({ ok = false, error = 'closed' }) end
        local ok, result = pcall(handler, data or {})
        if not ok then
            print(('[dwkambience] error en NUI %s: %s'):format(name, result))
            return cb({ ok = false, error = 'client_error' })
        end
        cb(result or { ok = true })
    end)
end

nui('exit', function()
    closeEditor()
end)

nui('list', function()
    return lib.callback.await('dwkambience:list', false)
end)

nui('create', function(data)
    closeScene()
    local result = lib.callback.await('dwkambience:create', false, data)
    if result and result.ok then loadScene(result) end
    return result
end)

nui('open', function(data)
    closeScene()
    local result = lib.callback.await('dwkambience:open', false, data.id)
    if result and result.ok then loadScene(result) end
    return result
end)

nui('closeScene', function()
    closeScene()
end)

nui('save', function(data)
    if data.id ~= currentScene then return { ok = false, error = 'not_open' } end
    return lib.callback.await('dwkambience:save', false, data)
end)

nui('delete', function(data)
    if data.id == currentScene then closeScene() end
    return lib.callback.await('dwkambience:delete', false, data.id)
end)

-- Punto donde colocar una entidad nueva: lo que mira la cámara, o unos metros delante
nui('spawnPoint', function(data)
    if type(data.model) ~= 'string' or not IsModelInCdimage(joaat(data.model)) then
        return { ok = false, error = 'invalid_model' }
    end
    local camPos, camRot = Freecam.get()
    local forward = Util.rotAxes(camRot)
    local point = Util.worldHit(camPos, camPos + forward * 50.0, PlayerPedId())
        or camPos + forward * Config.Editor.spawnDistance
    local heading = (camRot.z + 180.0) % 360.0
    return { ok = true, pos = Util.vecToArray(point, 3), rot = { 0.0, 0.0, Util.round(heading, 2) } }
end)

nui('applyEntity', function(data)
    local ok, err = Entities:apply(data.entity, data.pos, data.rot)
    return { ok = ok, error = err }
end)

nui('removeEntity', function(data)
    Entities:remove(data.id)
    if Select.get() == data.id then Select.set(nil) end
end)

nui('select', function(data)
    Select.set(data.id)
end)

nui('pick', function(data)
    local id = Select.pick(data.x, data.y)
    Select.set(id)
    return { ok = true, id = id }
end)

nui('ground', function(data)
    local pos, rot = Entities:ground(data.id)
    return { ok = pos ~= nil, pos = pos, rot = rot }
end)

nui('gizmo', function(data)
    local handle = Entities:handle(data.id)
    if not handle or Gizmo.isRunning() then return { ok = false, error = 'unavailable' } end

    CreateThread(function()
        SetNuiFocus(false, false)
        send('gizmo', { active = true, id = data.id })
        local confirmed = Gizmo.run(handle, data.mode)
        if isOpen then setFocus() end
        local pos, rot = Entities:transform(data.id)
        send('gizmo', { active = false, id = data.id, confirmed = confirmed, pos = pos, rot = rot })
    end)
end)

nui('focus', function(data)
    local handle = Entities:handle(data.id)
    if not handle then return { ok = false } end
    local min, max = GetModelDimensions(GetEntityModel(handle))
    Freecam.lookAt(GetEntityCoords(handle), math.max(4.0, #(max - min) * 1.5))
end)

nui('camLook', function(data)
    camLook = data.active == true
end)

nui('typing', function(data)
    typing = data.active == true
    if not Gizmo.isRunning() then setFocus() end
end)

nui('labels', function(data)
    Select.setLabels(data.enabled == true)
end)

-- Timeline -------------------------------------------------------------------

-- La NUI manda la escena entera cuando cambia (con debounce) para reevaluar en el cliente
nui('syncScene', function(data)
    if type(data.data) ~= 'table' then return { ok = false } end
    prepared = Evaluate.prepare(data.data)
    Entities:sync(prepared, currentT)
    applyCamera(Evaluate.scene(prepared, currentT))
end)

-- Scrub y reproducción en el editor: como mucho 60 mensajes/s desde la NUI
nui('time', function(data)
    currentT = math.max(0, math.floor(tonumber(data.t) or 0))
    applyTime()
end)

nui('cameraView', function(data)
    setCameraView(data.active == true)
end)

nui('cameraPose', function()
    local pos, rot, fov = Freecam.get()
    return { ok = true, pos = Util.vecToArray(pos, 3), rot = Util.vecToArray(rot, 2), fov = Util.round(fov, 1) }
end)

nui('pose', function(data)
    local pos, rot = Entities:transform(data.id)
    return { ok = pos ~= nil, pos = pos, rot = rot }
end)

-- Duración de una animación (ms), necesaria para crear su clip en la pista
nui('animInfo', function(data)
    if type(data.dict) ~= 'string' or type(data.clip) ~= 'string' or not DoesAnimDictExist(data.dict) then
        return { ok = false, error = 'invalid_anim' }
    end
    local ok = pcall(lib.requestAnimDict, data.dict, 5000)
    if not ok then return { ok = false, error = 'invalid_anim' } end
    local seconds = GetAnimDuration(data.dict, data.clip)
    RemoveAnimDict(data.dict)
    if not seconds or seconds <= 0 then return { ok = false, error = 'invalid_anim' } end
    return { ok = true, length = math.floor(seconds * 1000) }
end)

-- Menús Mundo y Ajustes --------------------------------------------------------

nui('camSpeed', function(data)
    Freecam.setSpeedMultiplier(tonumber(data.multiplier) or 1.0)
end)

nui('cameraToPlayer', function()
    local coords = GetEntityCoords(PlayerPedId())
    Freecam.lookAt(coords, 6.0)
end)

nui('previewWorld', function(data)
    worldPreview = data.active == true and prepared ~= nil
    if worldPreview then
        World.apply(prepared.data.settings, true)
    else
        World.restore()
    end
end)

-- Previsualizar cutscene: reproduce localmente la escena tal como está en el editor (sin guardar)
nui('preview', function(data)
    if previewing or Gizmo.isRunning() or type(data.data) ~= 'table' or not currentScene then return { ok = false } end
    previewing = true

    local hidden = {}
    for _, item in Entities:each() do
        if item.handle and DoesEntityExist(item.handle) then
            SetEntityVisible(item.handle, false, false)
            hidden[#hidden + 1] = item.handle
        end
    end
    SetNuiFocus(false, false)
    send('preview', { active = true })

    -- En otro hilo: la reproducción bloquea hasta terminar y el callback NUI tiene que responder ya
    local sceneData, sceneId = data.data, currentScene
    CreateThread(function() Player.preview(sceneData, sceneId, function()
        for _, handle in ipairs(hidden) do
            if DoesEntityExist(handle) then SetEntityVisible(handle, true, false) end
        end
        previewing = false
        if not isOpen then return end
        FreezeEntityPosition(PlayerPedId(), true)
        Freecam.reactivate()
        if worldPreview and prepared then World.apply(prepared.data.settings, true) end
        setFocus()
        send('preview', { active = false })
    end) end)
end)

RegisterNetEvent('dwkambience:openEditor', openEditor)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then teardown() end
end)

Editor = {
    isOpen = function() return isOpen end,
}
