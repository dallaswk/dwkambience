Config = {}

-- Permisos: ACE (add_ace group.admin cutscene.editor allow) o grupos de QB-Core
Config.Ace = 'cutscene.editor'
Config.QBGroups = { 'god', 'admin' }

Config.Command = 'scenes'

-- Límite de entidades por estudio (el MVP usa solo uno)
Config.Studios = {
    [1] = { label = 'Studio 1', maxEntities = 300 },
}
Config.DefaultStudio = 1

Config.MaxRevisions = 20
Config.MaxDataBytes = 512 * 1024

-- Límites de esquema que comprueba el servidor al guardar
Config.Limits = {
    maxTracks = 1000,
    maxKeysPerTrack = 2000,
    maxDurationMs = 30 * 60 * 1000,
}

Config.Freecam = {
    speed = 8.0,          -- m/s
    fastMultiplier = 4.0, -- Shift
    slowMultiplier = 0.2, -- Ctrl
    sensitivity = 8.0,
    fov = 50.0,
}

Config.Editor = {
    labelDistance = 60.0,
    spawnDistance = 6.0,
}

-- Webhook de Discord: set dwkambience_webhook "https://discord.com/api/webhooks/..."
Config.WebhookConvar = 'dwkambience_webhook'
