-- Reproducción de cutscenes: reloj común, sesiones por jugador y API para otros scripts.
Playback = {}

local sessions = {} -- [session] = { sceneId, name, targets = { [src] = true }, remaining }
local bySource = {} -- [src] = session
local nextSession = 0

--- nil, 'all' o -1 = todos; un id; o una lista de ids. Solo jugadores conectados, sin repetir.
local function resolveTargets(targets)
    local out, seen = {}, {}
    local function add(src)
        src = tonumber(src)
        if src and GetPlayerName(src) and not seen[src] then
            seen[src] = true
            out[#out + 1] = src
        end
    end
    if targets == nil or targets == 'all' or targets == -1 then
        for _, p in ipairs(GetPlayers()) do add(p) end
    elseif type(targets) == 'table' then
        for _, p in ipairs(targets) do add(p) end
    else
        add(targets)
    end
    return out
end

local function loadCutscene(id)
    if not Migrations.ready then return nil, 'db_not_ready' end
    local row = MySQL.single.await('SELECT name, type, data FROM scenes WHERE id = ?', { id })
    if not row then return nil, 'not_found' end
    if row.type ~= 'cutscene' then return nil, 'not_cutscene' end
    local data, err = Scene.migrate(json.decode(row.data))
    if not data then return nil, err end
    return data, row.name
end

--- Tiempo de red (GetNetworkTimeAccurate) de un cliente, o nil si no responde en 3 s.
--- Todos los clientes comparten ese reloj, así que un startAt en tiempo de red vale para todos.
local function networkTimeOf(src)
    local p = promise.new()
    local done = false
    lib.callback('dwkambience:netTime', src, function(value)
        if done then return end
        done = true
        p:resolve(value)
    end)
    SetTimeout(3000, function()
        if done then return end
        done = true
        p:resolve(nil)
    end)
    return Citizen.Await(p)
end

local function finish(src, session, skipped)
    local s = sessions[session]
    if not s or not s.targets[src] then return end
    s.targets[src] = nil
    s.remaining = s.remaining - 1
    if bySource[src] == session then bySource[src] = nil end
    TriggerEvent('dwkambience:finished', s.sceneId, src, skipped == true)
    if s.remaining <= 0 then sessions[session] = nil end
end

--- Reproduce una cutscene. opts.skippable (por defecto true).
--- Devuelve el id de sesión o nil, error.
function Playback.play(id, targets, opts)
    opts = opts or {}
    id = math.tointeger(tonumber(id))
    if not id then return nil, 'bad_id' end

    local list = resolveTargets(targets)
    if #list == 0 then return nil, 'no_targets' end

    local data, name = loadCutscene(id)
    if not data then return nil, name end

    local netNow
    for i = 1, math.min(3, #list) do
        netNow = networkTimeOf(list[i])
        if type(netNow) == 'number' then break end
    end
    if type(netNow) ~= 'number' then return nil, 'no_clock' end

    nextSession = nextSession + 1
    local session = nextSession
    local payload = {
        session = session,
        sceneId = id,
        data = data,
        startAt = netNow + Config.Playback.preloadMs,
        duration = Scene.stats(data).durationMs,
        skippable = opts.skippable ~= false,
    }

    sessions[session] = { sceneId = id, name = name, targets = {}, remaining = #list }
    for _, src in ipairs(list) do
        local previous = bySource[src]
        if previous then finish(src, previous, false) end
        sessions[session].targets[src] = true
        bySource[src] = session
        TriggerClientEvent('dwkambience:play', src, payload)
    end

    return session
end

--- Para la cutscene de los jugadores indicados (mismo formato de targets que play).
function Playback.stop(targets)
    for _, src in ipairs(resolveTargets(targets)) do
        local session = bySource[src]
        if session then TriggerClientEvent('dwkambience:stop', src, session) end
    end
end

RegisterNetEvent('dwkambience:playbackEnded', function(session, skipped)
    finish(source, tonumber(session), skipped)
end)

AddEventHandler('playerDropped', function()
    local session = bySource[source]
    if session then finish(source, session, false) end
end)

exports('PlayCutscene', function(id, targets, opts)
    return Playback.play(id, targets, opts)
end)

exports('StopCutscene', function(targets)
    Playback.stop(targets)
end)

-- /cutscene <id> [me|all|1,2,3] [noskip]   ·   /cutscene stop [me|all|1,2,3]
local MESSAGES = {
    es = {
        usage = 'Uso: /%s <id> [me|all|1,2,3] [noskip] · /%s stop [me|all|1,2,3]',
        started = 'Cutscene #%d (%s) para %d jugador(es)',
        failed = 'No se pudo reproducir: %s',
        stopped = 'Cutscene parada',
        forbidden = 'No tienes permiso para lanzar cutscenes',
    },
    en = {
        usage = 'Usage: /%s <id> [me|all|1,2,3] [noskip] · /%s stop [me|all|1,2,3]',
        started = 'Cutscene #%d (%s) for %d player(s)',
        failed = 'Could not play: %s',
        stopped = 'Cutscene stopped',
        forbidden = 'You do not have permission to play cutscenes',
    },
}

local function reply(src, kind, text)
    if src == 0 then
        print('[dwkambience] ' .. text)
    else
        TriggerClientEvent('ox_lib:notify', src, { type = kind, description = text })
    end
end

local function parseTargets(src, arg)
    if arg == nil or arg == 'me' then return src == 0 and 'all' or src end
    if arg == 'all' then return 'all' end
    local list = {}
    for id in arg:gmatch('%d+') do list[#list + 1] = tonumber(id) end
    return list
end

RegisterCommand(Config.Playback.command, function(src, args)
    local msg = MESSAGES[Config.Locale] or MESSAGES.en
    if src ~= 0 and not Permissions.canEdit(src) then return reply(src, 'error', msg.forbidden) end

    local cmd = Config.Playback.command
    if args[1] == 'stop' then
        Playback.stop(parseTargets(src, args[2]))
        return reply(src, 'success', msg.stopped)
    end

    local id = tonumber(args[1])
    if not id then return reply(src, 'inform', msg.usage:format(cmd, cmd)) end

    local targetArg, skippable = args[2], true
    if targetArg == 'noskip' then targetArg = nil end
    for _, a in ipairs(args) do
        if a == 'noskip' then skippable = false end
    end

    local targets = parseTargets(src, targetArg)
    local session, err = Playback.play(id, targets, { skippable = skippable })
    if not session then return reply(src, 'error', msg.failed:format(err)) end

    local count = sessions[session] and sessions[session].remaining or 0
    reply(src, 'success', msg.started:format(id, sessions[session] and sessions[session].name or '?', count))
    Log.action(src, 'Cutscene reproducida', ('#%d para %d jugador(es)'):format(id, count))
end, false)
