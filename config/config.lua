-- vp_lumberjack v3 — Configuração central (QBox / QBCore)
-- 3 sub-jobs (corte / empilhamento / entrega). Pagamento ACUMULA e é pago só quando
-- você DEVOLVE o veículo. Cancela por morte / distância / dano.
-- Server-authoritative, sem DB (estado em runtime).

Config = {}

Config.Debug   = false
Config.Webhook = ''

-- Acesso ao job. RequireJob=false → aberto a todos (bico). true → exige job 'lumberjack'.
Config.RequireJob = false
Config.JobName    = 'lumberjack'
Config.PayoutAccount = 'bank'  -- 'bank' (aust_banking v3) ou 'cash' (ox_inventory)

-- Item ox_inventory exigido p/ cortar. Toras/pallets são server-side (não item de inventário).
Config.Items = { chainsaw = 'chainsaw' }

-- Motosserra: som durante o corte + comando de volume.
Config.Chainsaw = {
    volumeCommand = 'serravolume',   -- /serravolume 0-100
    defaultVolume = 70,
    loopMs        = 600,             -- re-trigger do som enquanto corta
    sound = { set = 'DLC_HEIST_FLEECA_SOUNDSET', name = 'Drill_Pin_Break' },
}

--------------------------------------------------------------------------------
-- DUAL ENGINE DE ASSETS: Modelos customizados (plt_lumberjack-streams) vs Nativos
-- Se Config.UseCustomStreams = true, o script tenta usar os modelos e props de alta
-- fidelidade do plt_lumberjack. Se o stream não estiver montado, cai suavemente no nativo.
--------------------------------------------------------------------------------
Config.UseCustomStreams = true

Config.Assets = {
    -- Modelos customizados do plt_lumberjack-streams
    custom = {
        vehicles = {
            telehandler = 'jcb',           -- Telehandler JCB
            forklift    = 'pltforklift',    -- Empilhadeira Polat
            truck       = 'pltpacker',      -- Caminhão Packer
            trailer     = 'plttrflat',      -- Carreta Flatbed com rampas
        },
        props = {
            chainsaw  = 'polat_lumberjack_chainsaw003',
            tree      = 'polat_lumberjack_tree',
            stump     = 'prop_tree_stump_01',
            log       = 'polat_lumberjack_a1',
            logs      = { 'polat_lumberjack_a1', 'polat_lumberjack_a2', 'polat_lumberjack_a3' },
            woodpile  = 'polat_lumberjack_woodpile_1',
            woodpile2 = 'polat_lumberjack_woodpile_2',
            ramp      = 'polat_lumberjack_ramp001',
        },
    },
    -- Modelos nativos do GTA (Fallback universal seguro)
    native = {
        vehicles = {
            telehandler = 'forklift',
            forklift    = 'forklift',
            truck       = 'flatbed',
            trailer     = 'trailerlogs',
        },
        props = {
            chainsaw  = 'prop_tool_consaw',
            tree      = 'prop_tree_pine_02',
            stump     = 'prop_tree_stump_01',
            log       = 'prop_log_01',
            logs      = { 'prop_log_01', 'prop_log_02', 'prop_log_01' },
            woodpile  = 'prop_woodpile_01a',
            woodpile2 = 'prop_woodpile_01a',
            ramp      = 'prop_ramp_01',
        },
    },
    cutAnim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
    particles = { asset = 'core', name = 'ent_dst_wood_splinter' }
}

-- Metatabela de compatibilidade retroativa para Config.Assets.vehicles e Config.Assets.props
Config.Assets.vehicles = setmetatable({}, {
    __index = function(_, k)
        return (VPL and VPL.GetAsset and VPL.GetAsset('vehicles', k)) or Config.Assets.native.vehicles[k]
    end
})

Config.Assets.props = setmetatable({}, {
    __index = function(_, k)
        return (VPL and VPL.GetAsset and VPL.GetAsset('props', k)) or Config.Assets.native.props[k]
    end
})

--------------------------------------------------------------------------------
-- CENTRO DO JOB — capataz, blip, pontos de spawn de veículo e zona de devolução
--------------------------------------------------------------------------------
Config.JobCenter = {
    ped    = 's_m_y_construct_01',
    coords = vector4(-552.9, 5324.4, 73.6, 21.0),     -- serraria de Paleto Forest
    blip   = { sprite = 237, color = 21, scale = 0.9, label = 'Lenhador — Serraria' },

    -- pontos onde os veículos de trabalho nascem (o framework escolhe um livre)
    vehicleSpawns = {
        vector4(-533.0, 5325.0, 73.6, 250.0),
        vector4(-536.5, 5329.5, 73.6, 250.0),
        vector4(-540.0, 5334.0, 73.6, 250.0),
    },

    -- zona p/ devolver o veículo e finalizar o job (receber o acumulado)
    returnZone = { coords = vector3(-528.0, 5320.0, 73.5), radius = 8.0 },
}

--------------------------------------------------------------------------------
-- CANCELAMENTO — condições que abortam o job e PERDEM o acumulado
--------------------------------------------------------------------------------
Config.Cancel = {
    cancelOnDeath          = true,
    maxDistanceFromVehicle  = 200.0,   -- m a pé do veículo de trabalho → cancela
    warnDistanceFromVehicle = 150.0,   -- m → aviso antes de cancelar
    engineHealthMin        = 250.0,    -- abaixo disso (motor) cancela
    bodyHealthMin          = 300.0,    -- abaixo disso (lataria) cancela
    warnHealth             = 500.0,    -- aviso de dano
    checkInterval          = 1000,     -- ms entre checagens do watchdog
}

--------------------------------------------------------------------------------
-- OS 3 SUB-JOBS — rótulos, veículo e tabela de pagamento (tudo pago server-side)
--------------------------------------------------------------------------------
Config.Jobs = {
    cutting = {
        label   = 'Corte de Árvores',
        comment = 'Motosserra + derrubada física + transportar toras ao stand.',
        vehicle = 'telehandler',
        pay     = { perTree = 700, perLog = 250 },
        order   = 1,
    },
    stacking = {
        label   = 'Empilhamento de Pallets',
        comment = 'Pegar pallets com a empilhadeira e encaixar nos trailers.',
        vehicle = 'forklift',
        pay     = { perPallet = 200 },
        order   = 2,
    },
    delivery = {
        label   = 'Entrega de Lumber',
        comment = 'Levar os pallets até a obra com o caminhão. Mais longe = mais dinheiro.',
        vehicle = 'truck',
        pay     = { perDelivery = 150, perKm = 55 },
        order   = 3,
    },
}

--------------------------------------------------------------------------------
-- DETALHE POR JOB (refinado e expandido com a física do plt_lumberjack)
--------------------------------------------------------------------------------

-- Corte (Fase 2)
Config.Cutting = {
    fellDuration    = 8500,            -- ms cortando o tronco até iniciar queda
    fellMin         = 6500,            -- ms mínimo aceito pelo server (anti instant)
    fellSteps       = 28,              -- passos de rotação física da queda
    fellAngle       = -85.0,           -- ângulo de tombamento no chão
    fellAnimTime    = 1400,            -- ms da animação de queda da árvore
    fellCheckRadius = 4.5,             -- raio à frente p/ checar veículo no caminho da queda
    buckDuration    = 4500,            -- ms p/ desdobrar o tronco caído em toras
    buckMin         = 3500,            -- ms mínimo aceito no server p/ desdobro
    logsPerTree     = { min = 2, max = 3 },
    interactRadius  = 3.5,
    respawnMinutes  = 20,
    skillCheck      = { 'easy', 'medium' },
    stand = { coords = vector4(-558.6, 5310.7, 73.6, 200.0), radius = 6.0, label = 'Stand de toras' },
    trees = {
        vector3(-583.1, 5306.4, 70.2), vector3(-595.7, 5318.9, 69.5),
        vector3(-571.0, 5338.2, 70.9), vector3(-559.4, 5357.7, 72.1),
        vector3(-540.2, 5366.0, 73.8), vector3(-520.6, 5354.1, 75.2),
        vector3(-606.9, 5293.3, 68.4), vector3(-588.8, 5352.4, 71.6),
    },
}

-- Empilhamento (Fase 3)
Config.Stacking = {
    liftDuration      = 4000,
    yard              = { coords = vector3(-538.0, 5318.5, 73.5), radius = 18.0 },
    palletSpawns      = {
        vector4(-545.0, 5314.0, 73.5, 200.0),
        vector4(-548.0, 5317.0, 73.5, 200.0),
        vector4(-551.0, 5320.0, 73.5, 200.0),
    },
    trailerSpawns     = {
        vector4(-525.0, 5312.0, 73.5, 110.0),
        vector4(-522.0, 5316.0, 73.5, 110.0),
    },
    palletsPerTrailer = 4,
    ramp = {
        offset = vector3(0.0, -4.6, 0.0),
        doorIndex = 5,
    },
}

-- Entrega (Fase 4)
Config.Delivery = {
    unloadDuration = 4500,
    truckCapacity  = 4,
    siteRadius     = 12.0,
    sites = {
        { coords = vector4(-150.6, -959.7, 254.0, 250.0), distanceKm = 7.8, label = 'Obra — Maze Bank' },
        { coords = vector4(  85.4, -1958.7,  20.7, 320.0), distanceKm = 8.4, label = 'Obra — Cypress Flats' },
        { coords = vector4(  -1.2,  6457.9,  31.4,  45.0), distanceKm = 1.6, label = 'Obra — Paleto Bay' },
        { coords = vector4(-1090.0, 2715.3,  18.9, 220.0), distanceKm = 5.2, label = 'Obra — Great Chaparral' },
    },
    blip = { sprite = 478, color = 5, scale = 0.8 },
}

--------------------------------------------------------------------------------
-- GARFO (telehandler/empilhadeira) — operação real com tick rate dinâmico (0.00ms idle).
--------------------------------------------------------------------------------
Config.Fork = {
    grabKey       = 38,                       -- E
    alignDistance = 2.4,                      -- m: garfo até o marcador
    alignHeading  = 45.0,                     -- graus de tolerância de heading no drop
    forkBone      = 'forks',                  -- bone do garfo (fallback p/ offset se não existir)
    forkOffset    = vector3(0.0, 1.3, 0.1),   -- fallback: posição do garfo a partir do veículo
    loadAttach    = vector3(0.0, 1.1, 0.25),  -- onde a carga gruda no garfo
    markerSize    = vector3(2.5, 2.5, 0.8),
    markerColor   = { r = 40, g = 190, b = 80, a = 140 },
}

--------------------------------------------------------------------------------
-- ROUPA DE TRABALHO (Fase 5) — componentes de ped
--------------------------------------------------------------------------------
Config.Workwear = {
    male = {
        { component = 11, drawable = 250, texture = 0 },
        { component = 8,  drawable = 15,  texture = 0 },
        { component = 4,  drawable = 100, texture = 0 },
        { component = 6,  drawable = 25,  texture = 0 },
    },
    female = {
        { component = 11, drawable = 250, texture = 0 },
        { component = 8,  drawable = 15,  texture = 0 },
        { component = 4,  drawable = 100, texture = 0 },
        { component = 6,  drawable = 25,  texture = 0 },
    },
}

--------------------------------------------------------------------------------
-- Cooldowns (ms) — anti-flood (server-side)
--------------------------------------------------------------------------------
Config.Cooldowns = {
    startJob      = 4000,
    returnVehicle = 2000,
    giveTool      = 5000,
    action        = 1200,
}
