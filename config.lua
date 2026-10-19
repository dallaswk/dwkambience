Config = {}

-- Idioma de la UI y los avisos: 'es' o 'en'
Config.Locale = 'es'

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

Config.Playback = {
    command = 'cutscene',
    preloadMs = 4000,  -- margen entre la orden y t = 0 para cargar modelos con la pantalla en negro
    fadeMs = 500,
    skipControl = 177, -- INPUT_CELLPHONE_CANCEL (Retroceso)
}

Config.Ambience = {
    maxPedsPerAmbience = 60,  -- actores + personas de multitudes en un mismo ambience (lo valida el servidor)
    maxPedsTotal = 100,       -- peds de ambiences vivos a la vez en un cliente
    checkIntervalMs = 500,    -- cada cuánto se comprueba la entrada/salida de zona
    crowdSpawnDistance = 120, -- una persona de multitud aparece a menos de esta distancia...
    crowdDespawnDistance = 150, -- ...y desaparece a más de esta (histéresis)
    defaultEnter = 80,
    defaultExit = 100,
}

-- Presets de multitudes: modelos y escenarios (o anims { dict, clip }) entre los que se reparte la gente.
-- El nombre visible sale de la NUI (preset_<id> en web/src/i18n.ts).
Config.CrowdPresets = {
    custom = {
        models = {},
        scenarios = { 'WORLD_HUMAN_STAND_IMPATIENT' },
    },
    club = {
        models = { 'a_m_y_clubcust_01', 'a_m_y_clubcust_02', 'a_m_y_clubcust_03', 'a_f_y_clubcust_01', 'a_f_y_clubcust_02', 'a_f_y_clubcust_03' },
        scenarios = { 'WORLD_HUMAN_PARTYING', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_SMOKING' },
    },
    street = {
        models = { 'a_m_y_hipster_01', 'a_m_y_hipster_02', 'a_f_y_hipster_01', 'a_f_y_hipster_02', 'a_m_m_skater_01', 'a_f_y_tourist_01' },
        scenarios = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_TOURIST_MOBILE' },
    },
    business = {
        models = { 'a_m_m_business_01', 'a_m_y_business_01', 'a_m_y_business_02', 'a_m_y_business_03', 'a_f_y_business_01', 'a_f_y_business_02' },
        scenarios = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_CLIPBOARD', 'WORLD_HUMAN_AA_COFFEE' },
    },
    beach = {
        models = { 'a_m_y_beach_01', 'a_m_y_beach_02', 'a_m_y_beach_03', 'a_f_y_beach_01', 'a_f_m_beach_01' },
        scenarios = { 'WORLD_HUMAN_SUNBATHE_BACK', 'WORLD_HUMAN_SUNBATHE', 'WORLD_HUMAN_MUSCLE_FLEX', 'WORLD_HUMAN_TOURIST_MAP' },
    },
    gangs = {
        models = { 'g_m_y_ballaorig_01', 'g_m_y_ballasout_01', 'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_mexgoon_01' },
        scenarios = { 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_DRUG_DEALER' },
    },
    paparazzi = {
        models = { 'a_m_m_paparazzi_01' },
        scenarios = { 'WORLD_HUMAN_PAPARAZZI', 'WORLD_HUMAN_MOBILE_FILM_SHOCKING' },
    },
    concert = {
        models = { 'a_m_y_clubcust_01', 'a_f_y_clubcust_01', 'a_m_y_hipster_01', 'a_f_y_hipster_01', 'a_m_y_beach_01' },
        scenarios = { 'WORLD_HUMAN_CHEERING', 'WORLD_HUMAN_PARTYING' },
    },
}

-- Overlay de depuración de reproducción: setr dwkambience_debug 1
Config.DebugConvar = 'dwkambience_debug'

-- Webhook de Discord: set dwkambience_webhook "https://discord.com/api/webhooks/..."
Config.WebhookConvar = 'dwkambience_webhook'
