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
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/interp.lua',
    'shared/evaluate.lua',
    'shared/scene.lua',
}

client_scripts {
    'client/util.lua',
    'client/freecam.lua',
    'client/entities.lua',
    'client/select.lua',
    'client/gizmo.lua',
    'client/editor.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/log.lua',
    'server/permissions.lua',
    'server/locks.lua',
    'server/migrations.lua',
    'server/scenes.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
