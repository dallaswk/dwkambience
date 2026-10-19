-- Ciclo de vida del editor y puente con la NUI.

local isOpen = false
local camLook = false
local typing = false
local currentScene -- id de la escena abierta

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- La NUI tiene el cursor; el juego sigue recibiendo teclado y ratón salvo mientras se escribe en un campo
local function setFocus()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(not typing)
end

local function editorLoop()
    local last = GetGameTimer()
    while isOpen do
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now

        if not Gizmo.isRunning() then
            DisableAllControlActions(0)
            Freecam.update(dt, camLook and not typing)
        end
        HideHudAndRadarThisFrame()
        Select.draw()
        Wait(0)
    end
end

local function openEditor()
    if isOpen then return end
    isOpen = true
    camLook, typing = false, false

    FreezeEntityPosition(PlayerPedId(), true)
    Freecam.start(GetGameplayCamCoord(), GetGameplayCamRot(2))
    setFocus()
    send('open', { studios = Config.Studios, defaultStudio = Config.DefaultStudio })
    CreateThread(editorLoop)
end

local function closeScene()
    if currentScene then
        lib.callback.await('dwkambience:close', false, currentScene)
    end
    currentScene = nil
    Entities.clear()
    Select.set(nil)
end

-- Limpieza local sin hablar con el servidor (válida también en onResourceStop)
local function teardown()
    isOpen = false
    camLook, typing = false, false
    currentScene = nil
    Entities.clear()
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
    Select.set(nil)
    result.failed = Entities.loadScene(result.data)

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
    local ok, err = Entities.apply(data.entity, data.pos, data.rot)
    return { ok = ok, error = err }
end)

nui('removeEntity', function(data)
    Entities.remove(data.id)
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
    local pos, rot = Entities.ground(data.id)
    return { ok = pos ~= nil, pos = pos, rot = rot }
end)

nui('gizmo', function(data)
    local handle = Entities.handle(data.id)
    if not handle or Gizmo.isRunning() then return { ok = false, error = 'unavailable' } end

    CreateThread(function()
        SetNuiFocus(false, false)
        send('gizmo', { active = true, id = data.id })
        local confirmed = Gizmo.run(handle, data.mode)
        if isOpen then setFocus() end
        local pos, rot = Entities.transform(data.id)
        send('gizmo', { active = false, id = data.id, confirmed = confirmed, pos = pos, rot = rot })
    end)
end)

nui('focus', function(data)
    local handle = Entities.handle(data.id)
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

RegisterNetEvent('dwkambience:openEditor', openEditor)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then teardown() end
end)
