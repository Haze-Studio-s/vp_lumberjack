fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vp_lumberjack'
author 'vinicius3232'
version '3.0.0'
description 'Job de lenhador (QBox) — 3 sub-jobs (corte/empilhamento/entrega), operação de garfo, pagamento na devolução do veículo, cancelamento por morte/distância/dano. Server-authoritative, sem DB, assets nativos.'

-- @ox_lib/init.lua SEMPRE primeiro no shared (CLAUDE.md regra 10)
shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
}

-- framework (sessão/cancelamento/devolução) antes dos módulos de cada job.
-- Os módulos cutting/stacking/delivery entram conforme as fases 2–4.
client_scripts {
    'client/ui.lua',
    'client/framework.lua',
    'client/fork.lua',
    'client/polish.lua',
    'client/cutting.lua',
    'client/stacking.lua',
    'client/delivery.lua',
    'client/main.lua',
}

server_scripts {
    'server/security.lua',
    'server/main.lua',
    'server/framework.lua',
    'server/cutting.lua',
    'server/stacking.lua',
    'server/delivery.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'qbx_core',
    'qbx_vehiclekeys',
}
