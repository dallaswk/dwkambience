fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dwkambience'
description 'Editor in-game de cutscenes y ambiences'
version '0.1.0'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/dist/sounds/*',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/interp.lua',
    'shared/evaluate.lua',
    'shared/crowd.lua',
    'shared/rdp.lua',
    'shared/scene.lua',
}

client_scripts {
    'client/util.lua',
    'client/world.lua',
    'client/freecam.lua',
    'client/crowds.lua',
    'client/audio.lua',
    'client/fx.lua',
    'client/pool.lua',
    'client/select.lua',
    'client/gizmo.lua',
    'client/editor.lua',
    'client/player.lua',
    'client/ambience.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/log.lua',
    'server/permissions.lua',
    'server/locks.lua',
    'server/migrations.lua',
    'server/scenes.lua',
    'server/playback.lua',
    'server/ambience.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
