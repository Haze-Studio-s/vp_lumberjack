fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vp_lumberjack'
author 'vinicius3232'
version '3.1.0'
description 'Job de lenhador (QBox) — 3 sub-jobs (corte/empilhamento/entrega), maquinário pesado e telehandler JCB, carreta florestal, serraria e motosserras customizadas. Server-authoritative, aust_banking v3 fail-closed.'

data_file 'DLC_ITYP_REQUEST' 'stream/polat_lumberjack_tree.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/polat_lumberjack_ramp001.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/polat_lumberjack_chainsaw003.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/[yMap]/rotto_plt_objects.ytyp'

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
}

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
    'data/*.meta',
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'qbx_core',
    'qbx_vehiclekeys',
}
