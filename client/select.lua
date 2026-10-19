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
    for id, item in Entities:each() do
        if item.handle and DoesEntityExist(item.handle) then
            local center = GetEntityCoords(item.handle)
            local radius = boundingRadius(item.handle)
            local toCenter = center - camPos
            local t = toCenter.x * dir.x + toCenter.y * dir.y + toCenter.z * dir.z
            if t > 0 and t - radius < maxDist then
                local closest = camPos + dir * t
                if #(center - closest) <= radius and (not bestT or t < bestT) then
                    bestId, bestT = id, t
                end
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

function Select.draw()
    local camPos = Freecam.get()
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
