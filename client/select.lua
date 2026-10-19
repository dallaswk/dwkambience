-- Selección por rayo desde la cámara y overlays (caja de la selección, etiquetas).
Select = {}

local selectedId
local showLabels = true

local SELECTED_COLOR = { 1, 150, 133 } -- acento #019685

local function boundingRadius(handle)
    local min, max = GetModelDimensions(GetEntityModel(handle))
    return math.max(0.5, #(max - min) / 2)
end

--- Entidad de la escena bajo un punto de pantalla normalizado, o nil.
--- Prueba el rayo contra la esfera de cada entidad y descarta las tapadas por el mapa.
function Select.pick(nx, ny)
    local camPos, camRot, fov = Freecam.get()
    local dir = Util.screenRay(camRot, fov, nx, ny)
    local maxDist = 500.0
    local hit = Util.worldHit(camPos, camPos + dir * maxDist)
    if hit then maxDist = #(hit - camPos) + 0.5 end

    local bestId, bestT
    local function test(id, center, radius)
        local toCenter = center - camPos
        local t = toCenter.x * dir.x + toCenter.y * dir.y + toCenter.z * dir.z
        if t > 0 and t - radius < maxDist then
            local closest = camPos + dir * t
            if #(center - closest) <= radius and (not bestT or t < bestT) then
                bestId, bestT = id, t
            end
        end
    end

    for id, item in Entities:each() do
        if item.handle and DoesEntityExist(item.handle) then
            test(id, GetEntityCoords(item.handle), boundingRadius(item.handle))
        elseif item.kind == 'sound' and item.pos then
            test(id, vector3(item.pos[1], item.pos[2], item.pos[3]), 0.8)
        elseif item.crowdSet then
            for _, ped in item.crowdSet:each() do
                if DoesEntityExist(ped) then test(id, GetEntityCoords(ped), 1.0) end
            end
        end
    end
    return bestId
end

function Select.set(id)
    selectedId = id
end

function Select.get()
    return selectedId
end

function Select.setLabels(enabled)
    showLabels = enabled
end

local function drawBox(handle)
    local min, max = GetModelDimensions(GetEntityModel(handle))
    local corners = {}
    for i = 0, 7 do
        local x = ((i & 1) == 0) and min.x or max.x
        local y = ((i & 2) == 0) and min.y or max.y
        local z = ((i & 4) == 0) and min.z or max.z
        corners[i] = GetOffsetFromEntityInWorldCoords(handle, x, y, z)
    end
    local r, g, b = SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3]
    local edges = { {0,1}, {2,3}, {4,5}, {6,7}, {0,2}, {1,3}, {4,6}, {5,7}, {0,4}, {1,5}, {2,6}, {3,7} }
    for _, e in ipairs(edges) do
        local a, c = corners[e[1]], corners[e[2]]
        DrawLine(a.x, a.y, a.z, c.x, c.y, c.z, r, g, b, 255)
    end
end

local function drawCrowd(item, selected)
    local points = item.crowd and item.crowd.points or {}
    local r, g, b = SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3]
    local alpha = selected and 255 or 90
    for i, p in ipairs(points) do
        DrawMarker(28, p[1], p[2], p[3], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, r, g, b, alpha, false, false, 2, false, nil, nil, false)
        local nextPoint = points[i + 1]
        if nextPoint then DrawLine(p[1], p[2], p[3], nextPoint[1], nextPoint[2], nextPoint[3], r, g, b, alpha) end
    end
    -- Con un solo punto la multitud ocupa un círculo de radio spread
    if selected and #points == 1 and (item.crowd.spread or 0) > 0 then
        local d = item.crowd.spread * 2
        DrawMarker(1, points[1][1], points[1][2], points[1][3] - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 0.3, r, g, b, 60, false, false, 2, false, nil, nil, false)
    end
end

local function drawSound(item, selected)
    local p = item.pos
    if not p then return end
    local r, g, b = SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3]
    DrawMarker(28, p[1], p[2], p[3], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.35, 255, 255, 255, selected and 230 or 120, false, false, 2, false, nil, nil, false)
    if selected and item.sound then
        local d = item.sound.range * 2
        DrawMarker(1, p[1], p[2], p[3] - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 0.2, r, g, b, 40, false, false, 2, false, nil, nil, false)
    end
end

--- Zona de activación de un ambience: radio de entrada (más visible) y de salida
function Select.drawZone(trigger)
    if not trigger then return end
    local c = trigger.center
    local r, g, b = SELECTED_COLOR[1], SELECTED_COLOR[2], SELECTED_COLOR[3]
    DrawMarker(1, c[1], c[2], c[3] - 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, trigger.enter * 2, trigger.enter * 2, 4.0, r, g, b, 45, false, false, 2, false, nil, nil, false)
    DrawMarker(1, c[1], c[2], c[3] - 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, trigger.exit * 2, trigger.exit * 2, 2.0, 255, 255, 255, 20, false, false, 2, false, nil, nil, false)
    DrawMarker(28, c[1], c[2], c[3], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4, r, g, b, 200, false, false, 2, false, nil, nil, false)
end

function Select.draw()
    local camPos = Freecam.get()
    for id, item in Entities:each() do
        if item.kind == 'crowd' then
            drawCrowd(item, id == selectedId)
            local first = item.crowd and item.crowd.points[1]
            if showLabels and first then Util.drawText3D(vector3(first[1], first[2], first[3] + 1.2), item.label or id) end
        elseif item.kind == 'sound' then
            drawSound(item, id == selectedId)
            if showLabels and item.pos then Util.drawText3D(vector3(item.pos[1], item.pos[2], item.pos[3] + 0.5), item.label or id) end
        end
    end
    for id, item in Entities:each() do
        local handle = item.handle
        if handle and DoesEntityExist(handle) then
            if id == selectedId then drawBox(handle) end
            if showLabels then
                local coords = GetEntityCoords(handle)
                if #(coords - camPos) < Config.Editor.labelDistance then
                    local _, max = GetModelDimensions(GetEntityModel(handle))
                    Util.drawText3D(coords + vector3(0.0, 0.0, max.z + 0.25), item.label or id)
                end
            end
        end
    end
end
