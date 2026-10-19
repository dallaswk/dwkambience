-- Conjunto de entidades locales de una escena: resuelve ids de escena a handles y aplica su estado.
-- El editor usa un pool (Entities) y cada reproducción crea el suyo.
EntityPool = {}
EntityPool.__index = EntityPool

local pools = setmetatable({}, { __mode = 'k' })

local VEHICLE_DOORS = 5 -- 0 FL, 1 FR, 2 RL, 3 RR, 4 capó, 5 maletero

--- opts.skipNetworked: no crear las entidades marcadas en red (las crea el servidor en los ambiences)
function EntityPool.new(opts)
    local pool = setmetatable({ items = {}, skipNetworked = opts and opts.skipNetworked }, EntityPool)
    pools[pool] = true
    return pool
end

local function create(kind, hash, pos, rot)
    local handle
    if kind == 'ped' then
        handle = CreatePed(4, hash, pos.x, pos.y, pos.z, rot.z, false, false)
    elseif kind == 'vehicle' then
        handle = CreateVehicle(hash, pos.x, pos.y, pos.z, rot.z, false, false)
    elseif kind == 'prop' then
        handle = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    end
    if not handle or handle == 0 then return nil end

    SetEntityAsMissionEntity(handle, true, true)
    FreezeEntityPosition(handle, true)
    SetEntityInvincible(handle, true)

    if kind == 'ped' then
        SetBlockingOfNonTemporaryEvents(handle, true)
        SetPedCanRagdoll(handle, false)
        SetPedDefaultComponentVariation(handle)
    elseif kind == 'vehicle' then
        SetVehicleDoorsLocked(handle, 2)
    end

    return handle
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- Animación o escenario "de reposo" del ped (props). Solo se usa cuando ninguna pista de anim está activa.
local function applyIdle(handle, props)
    ClearPedTasksImmediately(handle)
    local anim = props.anim
    if type(anim) == 'table' and anim.dict and anim.clip then
        local ok = pcall(lib.requestAnimDict, anim.dict, 5000)
        if ok then
            TaskPlayAnim(handle, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            RemoveAnimDict(anim.dict)
        end
    elseif type(props.scenario) == 'string' and props.scenario ~= '' then
        TaskStartScenarioInPlace(handle, props.scenario, 0, true)
    end
end

local function applyVehicleProps(handle, props)
    SetVehicleEngineOn(handle, props.engine == true, true, true)
    SetVehicleLights(handle, props.headlights and 2 or 1)
    SetVehicleSiren(handle, props.siren == true)
    SetVehicleDirtLevel(handle, math.max(0.0, math.min(15.0, (props.dirt or 0) + 0.0)))

    local open = {}
    for _, door in ipairs(type(props.doors) == 'table' and props.doors or {}) do open[door] = true end
    for door = 0, VEHICLE_DOORS do
        if open[door] then
            SetVehicleDoorOpen(handle, door, false, true)
        else
            SetVehicleDoorShut(handle, door, true)
        end
    end
end

--- Crea o actualiza una entidad para que coincida con su definición. pos/rot son arrays {x, y, z}.
--- Devuelve true o false, error.
function EntityPool:apply(entity, pos, rot)
    if self.skipNetworked and entity.networked then return true end
    local current = self.items[entity.id]
    if current and (current.model ~= entity.model or current.kind ~= entity.kind) then
        self:remove(entity.id)
        current = nil
    end

    -- Emisor de sonido: sin entidad de juego, solo posición (de su pista de transform)
    if entity.kind == 'sound' then
        self.items[entity.id] = { kind = 'sound', sound = entity.sound, label = entity.label, props = {}, pos = pos or (current and current.pos) }
        return true
    end

    -- Texto, luz y partículas: sin entidad de juego; Fx.drawPool los dibuja cada frame
    if entity.kind == 'text' or entity.kind == 'light' or entity.kind == 'ptfx' then
        local def = entity[entity.kind]
        if current and entity.kind == 'ptfx' and json.encode(current.def) ~= json.encode(def) then Fx.stopPtfx(current) end
        self.items[entity.id] = {
            kind = entity.kind, label = entity.label, props = {}, def = def,
            pos = pos or (current and current.pos), rot = rot or (current and current.rot),
            visible = not current or current.visible ~= false,
            ptfxHandle = current and current.ptfxHandle, ptfxKey = current and current.ptfxKey,
        }
        return true
    end

    -- Multitud: sus personas se crean por distancia en updateCrowds; se rehace si cambia su definición
    if entity.kind == 'crowd' then
        local key = json.encode(entity.crowd)
        if not current or current.crowdKey ~= key then
            if current and current.crowdSet then current.crowdSet:clear() end
            current = { kind = 'crowd', label = entity.label, props = {}, crowdKey = key, crowd = entity.crowd, crowdSet = CrowdSet.new(entity.crowd) }
            self.items[entity.id] = current
        end
        current.label = entity.label
        return true
    end

    pos = pos or { 0.0, 0.0, 0.0 }
    rot = rot or { 0.0, 0.0, 0.0 }

    if not current then
        local hash = Util.loadModel(entity.model)
        if not hash then return false, 'invalid_model' end
        local handle = create(entity.kind, hash, vector3(pos[1], pos[2], pos[3]), vector3(rot[1], rot[2], rot[3]))
        SetModelAsNoLongerNeeded(hash)
        if not handle then return false, 'spawn_failed' end
        current = { handle = handle, kind = entity.kind, model = entity.model, props = {} }
        self.items[entity.id] = current
    end

    self:setPose(entity.id, pos, rot)

    local props = entity.props or {}
    if entity.kind == 'ped' then
        local idleChanged = not same(props.anim, current.props.anim) or props.scenario ~= current.props.scenario
        if idleChanged and not current.timelineAnim then applyIdle(current.handle, props) end
    elseif entity.kind == 'vehicle' then
        applyVehicleProps(current.handle, props)
    end
    current.props = props
    current.label = entity.label

    return true
end

function EntityPool:setPose(id, pos, rot)
    local item = self.items[id]
    if not item or not pos then return end
    if not item.handle then
        item.pos, item.rot = pos, rot
        return
    end
    SetEntityCoordsNoOffset(item.handle, pos[1] + 0.0, pos[2] + 0.0, pos[3] + 0.0, false, false, false)
    SetEntityRotation(item.handle, rot[1] + 0.0, rot[2] + 0.0, rot[3] + 0.0, 2, true)
end

--- Pone la animación de la pista en su fase exacta (velocidad 0: la fase la manda t, no el juego).
--- anim = { dict, clip, phase } o nil para volver al reposo.
function EntityPool:setAnim(id, anim)
    local item = self.items[id]
    if not item or not item.handle or item.kind ~= 'ped' then return end
    local handle = item.handle

    if not anim then
        if item.timelineAnim then
            item.timelineAnim = nil
            applyIdle(handle, item.props)
        end
        return
    end

    if not HasAnimDictLoaded(anim.dict) then
        RequestAnimDict(anim.dict) -- se aplicará en una evaluación posterior, cuando esté cargado
        return
    end

    local current = item.timelineAnim
    if not current or current.dict ~= anim.dict or current.clip ~= anim.clip
        or not IsEntityPlayingAnim(handle, anim.dict, anim.clip, 3) then
        TaskPlayAnim(handle, anim.dict, anim.clip, 1000.0, -1000.0, -1, 1, 0.0, false, false, false)
        item.timelineAnim = { dict = anim.dict, clip = anim.clip }
    end
    SetEntityAnimSpeed(handle, anim.dict, anim.clip, 0.0)
    SetEntityAnimCurrentTime(handle, anim.dict, anim.clip, anim.phase)
end

--- Pide por adelantado los diccionarios de todas las pistas de anim.
function EntityPool:preloadAnims(prepared)
    for _, clips in pairs(prepared.anim) do
        for _, c in ipairs(clips) do RequestAnimDict(c.dict) end
    end
end

--- Aplica el estado evaluado (Evaluate.scene) a las entidades del pool.
function EntityPool:applyState(state)
    for id, s in pairs(state.entities) do
        if s.pos then self:setPose(id, s.pos, s.rot) end
        self:setAnim(id, s.anim)
        self:setVisible(id, s.visible ~= false)
    end
end

function EntityPool:setVisible(id, visible)
    local item = self.items[id]
    if not item or item.visible == visible then return end
    item.visible = visible
    if item.handle and DoesEntityExist(item.handle) then
        SetEntityVisible(item.handle, visible, false)
        SetEntityCollision(item.handle, visible, false)
    end
end

function EntityPool:drawFx(camPos)
    Fx.drawPool(self, camPos)
end

--- Crea las entidades de una escena en su pose en t. Devuelve las etiquetas que no se pudieron crear.
function EntityPool:load(prepared, t)
    self:clear()
    local state = Evaluate.scene(prepared, t or 0)
    local failed = {}
    for _, entity in ipairs(prepared.data.entities or {}) do
        local s = state.entities[entity.id]
        if not self:apply(entity, s and s.pos, s and s.rot) then failed[#failed + 1] = entity.label end
    end
    self:preloadAnims(prepared)
    return failed
end

--- Sincroniza el pool con una lista de entidades: crea o actualiza las que hay y borra las que sobran.
function EntityPool:sync(prepared, t)
    local state = Evaluate.scene(prepared, t)
    local keep = {}
    for _, entity in ipairs(prepared.data.entities or {}) do
        keep[entity.id] = true
        local s = state.entities[entity.id]
        local current = self.items[entity.id]
        local pos, rot = s and s.pos, s and s.rot
        if current and current.handle and not pos then
            pos, rot = Util.vecToArray(GetEntityCoords(current.handle), 3), Util.vecToArray(GetEntityRotation(current.handle, 2), 2)
        end
        self:apply(entity, pos, rot)
    end
    for id in pairs(self.items) do
        if not keep[id] then self:remove(id) end
    end
    self:preloadAnims(prepared)
    self:applyState(state)
end

function EntityPool:remove(id)
    local item = self.items[id]
    if not item then return end
    if item.crowdSet then item.crowdSet:clear() end
    Fx.stopPtfx(item)
    if item.handle and DoesEntityExist(item.handle) then
        SetEntityAsMissionEntity(item.handle, true, true)
        DeleteEntity(item.handle)
    end
    self.items[id] = nil
end

function EntityPool:clear()
    for id in pairs(self.items) do self:remove(id) end
end

--- Crea o borra personas de las multitudes según la distancia a origin (vector3).
function EntityPool:updateCrowds(origin, spawnDistance, despawnDistance, budget)
    for _, item in pairs(self.items) do
        if item.crowdSet then item.crowdSet:update(origin, spawnDistance, despawnDistance, budget) end
    end
end

--- ¿Están creadas todas las personas de todas las multitudes?
function EntityPool:crowdsReady()
    for _, item in pairs(self.items) do
        if item.crowdSet and item.crowdSet.spawned < #item.crowdSet.members then return false end
    end
    return true
end

--- Peds vivos de este pool: actores más personas de multitudes
function EntityPool:pedCount()
    local count = 0
    for _, item in pairs(self.items) do
        if item.kind == 'ped' and item.handle then count = count + 1 end
        if item.crowdSet then count = count + item.crowdSet.spawned end
    end
    return count
end

--- Emisores de sonido con posición, en el formato de Audio3D.set
function EntityPool:emitters()
    local out = {}
    for id, item in pairs(self.items) do
        if item.kind == 'sound' and item.sound and item.pos then
            out[#out + 1] = {
                id = id, asset = item.sound.asset, volume = item.sound.volume, range = item.sound.range,
                loop = item.sound.loop, pos = item.pos,
            }
        end
    end
    return out
end

--- Id de la multitud a la que pertenece un ped, o nil
function EntityPool:crowdOf(handle)
    for id, item in pairs(self.items) do
        if item.crowdSet and item.crowdSet:owns(handle) then return id end
    end
end

function EntityPool:handle(id)
    local item = self.items[id]
    return item and item.handle
end

function EntityPool:each()
    return pairs(self.items)
end

--- Transform actual en el juego, redondeado para la NUI.
function EntityPool:transform(id)
    local handle = self:handle(id)
    if not handle or not DoesEntityExist(handle) then return nil end
    return Util.vecToArray(GetEntityCoords(handle), 3), Util.vecToArray(GetEntityRotation(handle, 2), 2)
end

--- Pega la entidad al suelo y devuelve su nuevo transform.
function EntityPool:ground(id)
    local item = self.items[id]
    if not item or not item.handle then return nil end
    local handle = item.handle

    FreezeEntityPosition(handle, false)
    if item.kind == 'vehicle' then
        SetVehicleOnGroundProperly(handle)
    elseif item.kind == 'prop' then
        PlaceObjectOnGroundProperly(handle)
    else
        local coords = GetEntityCoords(handle)
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
        if found then
            SetEntityCoordsNoOffset(handle, coords.x, coords.y, groundZ + 1.0, false, false, false)
        end
    end
    FreezeEntityPosition(handle, true)

    return self:transform(id)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for pool in pairs(pools) do pool:clear() end
end)

-- Pool del editor
Entities = EntityPool.new()
