-- Texto 3D, luces dinámicas y partículas de los pools de entidades. Se llama en cada frame desde el
-- editor, las cutscenes y los ambiences con Fx.drawPool(pool, posición de la cámara).
Fx = {}

local cfg = Config.Fx

-- Presupuesto de luces compartido por todos los pools en un mismo frame
local lightFrame, lightsDrawn = -1, 0

local function lightBudget()
    local frame = GetFrameCount()
    if frame ~= lightFrame then
        lightFrame, lightsDrawn = frame, 0
    end
    return cfg.maxLights - lightsDrawn
end

-- Pantallas: modelo -> nombre del render target, y targets ya registrados
local screenTargets = {}
for _, s in ipairs(Config.ScreenProps or {}) do screenTargets[joaat(s.model)] = s.target end
local registered = {}

local function renderId(target, hash)
    if not registered[target] then
        if not IsNamedRendertargetRegistered(target) then RegisterNamedRendertarget(target, false) end
        registered[target] = true
    end
    if not IsNamedRendertargetLinked(hash) then LinkNamedRendertarget(hash) end
    return GetNamedRendertargetRenderId(target)
end

local function drawScreen(screen, target, hash)
    local id = renderId(target, hash)
    if not id or id == 0 then return end
    SetTextRenderId(id)
    SetScriptGfxDrawOrder(4)
    DrawRect(0.5, 0.5, 1.0, 1.0, screen.background[1], screen.background[2], screen.background[3], 255)
    SetTextFont(screen.font)
    SetTextScale(0.0, 0.6 * screen.scale)
    SetTextColour(screen.color[1], screen.color[2], screen.color[3], 255)
    SetTextCentre(true)
    SetTextWrap(0.05, 0.95)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(screen.content)
    EndTextCommandDisplayText(0.5, 0.5 - 0.035 * screen.scale)
    SetTextRenderId(GetDefaultScriptRendertargetRenderId())
end

local function vec(a)
    return vector3(a[1] + 0.0, a[2] + 0.0, a[3] + 0.0)
end

local function drawText(item, camPos, distance)
    local def = item.def
    local pos = vec(item.pos)
    -- Sin "visible desde detrás", el texto solo se ve desde el lado al que mira su rotación
    if not def.backface then
        local forward = Util.rotAxes(vec(item.rot or { 0, 0, 0 }))
        local toCam = camPos - pos
        if toCam.x * forward.x + toCam.y * forward.y + toCam.z * forward.z < 0 then return end
    end

    -- Escala inversa a la distancia para que el texto tenga tamaño "de mundo"
    local fov = GetFinalRenderedCamFov()
    local scale = def.scale * (1.0 / math.max(distance, 0.5)) * 2.0 * (50.0 / fov)

    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    SetTextFont(def.font)
    SetTextScale(0.0, math.min(scale, 3.0))
    SetTextColour(def.color[1], def.color[2], def.color[3], 255)
    if def.outline then SetTextOutline() end
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(def.content)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawLight(item, shadowId)
    local def = item.def
    local p = item.pos
    local r, g, b = def.color[1], def.color[2], def.color[3]
    if def.type == 'spot' then
        local dir = Util.rotAxes(vec(item.rot or { 0, 0, 0 }))
        if def.shadow then
            DrawSpotLightWithShadow(p[1], p[2], p[3], dir.x, dir.y, dir.z, r, g, b, def.range + 0.0, def.intensity + 0.0, 1.0, def.angle + 0.0, def.falloff + 0.0, shadowId)
        else
            DrawSpotLight(p[1], p[2], p[3], dir.x, dir.y, dir.z, r, g, b, def.range + 0.0, def.intensity + 0.0, 1.0, def.angle + 0.0, def.falloff + 0.0)
        end
    else
        DrawLightWithRangeAndShadow(p[1], p[2], p[3], r, g, b, def.range + 0.0, def.intensity + 0.0, def.shadow and 1.0 or 0.0)
    end
end

function Fx.stopPtfx(item)
    if item and item.ptfxHandle then
        StopParticleFxLooped(item.ptfxHandle, false)
        item.ptfxHandle = nil
    end
end

-- Arranca, reinicia (si se movió o cambió) o para el efecto según visibilidad y distancia
local function updatePtfx(item, distance)
    local def = item.def
    local wanted = item.visible ~= false and distance <= cfg.ptfxDistance
    if not wanted then
        Fx.stopPtfx(item)
        return
    end

    local key = ('%s|%.2f|%.2f|%.2f|%.1f'):format(json.encode(def), item.pos[1], item.pos[2], item.pos[3], (item.rot or { 0, 0, 0 })[3])
    if item.ptfxHandle and item.ptfxKey == key then return end
    Fx.stopPtfx(item)

    if not HasNamedPtfxAssetLoaded(def.asset) then
        RequestNamedPtfxAsset(def.asset)
        return
    end
    UseParticleFxAsset(def.asset)
    local p, r = item.pos, item.rot or { 0, 0, 0 }
    item.ptfxHandle = StartParticleFxLoopedAtCoord(def.effect, p[1] + 0.0, p[2] + 0.0, p[3] + 0.0, r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, def.scale + 0.0, false, false, false, false)
    item.ptfxKey = key
    if def.color and item.ptfxHandle then
        SetParticleFxLoopedColour(item.ptfxHandle, def.color[1] / 255, def.color[2] / 255, def.color[3] / 255, false)
    end
end

--- Dibuja los efectos de un pool. camPos: vector3 de la cámara activa.
function Fx.drawPool(pool, camPos)
    local lights
    local screens -- [target] = { screen, hash, distance } (la más cercana por target)
    for _, item in pool:each() do
        local kind = item.kind
        if item.screen and item.handle and item.visible ~= false and DoesEntityExist(item.handle) then
            local hash = GetEntityModel(item.handle)
            local target = screenTargets[hash]
            if target then
                local d = #(camPos - GetEntityCoords(item.handle))
                screens = screens or {}
                if d <= cfg.textDistance * 2 and (not screens[target] or d < screens[target].distance) then
                    screens[target] = { screen = item.screen, hash = hash, distance = d }
                end
            end
        end
        if (kind == 'text' or kind == 'light' or kind == 'ptfx') and item.pos then
            local distance = #(camPos - vec(item.pos))
            if kind == 'ptfx' then
                updatePtfx(item, distance)
            elseif item.visible ~= false then
                if kind == 'text' and distance <= cfg.textDistance then
                    drawText(item, camPos, distance)
                elseif kind == 'light' and distance <= cfg.lightDistance then
                    lights = lights or {}
                    lights[#lights + 1] = { item = item, distance = distance }
                end
            end
        end
    end

    for target, entry in pairs(screens or {}) do
        drawScreen(entry.screen, target, entry.hash)
    end

    if lights then
        -- Las más cercanas primero, hasta agotar el presupuesto del frame
        table.sort(lights, function(a, b) return a.distance < b.distance end)
        for i, entry in ipairs(lights) do
            if lightBudget() <= 0 then break end
            lightsDrawn = lightsDrawn + 1
            drawLight(entry.item, i)
        end
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for target in pairs(registered) do
        if IsNamedRendertargetRegistered(target) then ReleaseNamedRendertarget(target) end
    end
end)
