fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Distortionz'
description 'Distortionz Reports — premium player report / support ticket system. NUI submit form + staff queue + threaded conversation view. Tier-gated via distortionz_perms.'
version '1.0.3'
repository 'https://github.com/Distortionzz/Distortionz_Reports'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server.lua',
    'version_check.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'distortionz_perms',
}
