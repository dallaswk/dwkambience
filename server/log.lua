Log = {}

local function identity(src)
    if not src or src == 0 then return 'console' end
    local license = GetPlayerIdentifierByType(src, 'license') or 'unknown'
    return ('%s (%s, id %d)'):format(GetPlayerName(src) or '?', license, src)
end

--- Registra una acción del editor en consola y, si hay webhook, en Discord.
function Log.action(src, action, details)
    local line = ('[dwkambience] %s: %s %s'):format(identity(src), action, details or '')
    print(line)

    local webhook = GetConvar(Config.WebhookConvar, '')
    if webhook == '' then return end

    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = 'dwkambience',
        embeds = { {
            title = action,
            description = details or '',
            footer = { text = identity(src) },
            color = 0x019685,
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function Log.who(src)
    return (GetPlayerName(src) or ('id %d'):format(src)):sub(1, 64)
end
