-- vp_lumberjack v3 — ESTÁGIO Corte (client):
-- 1. Derrubada com motosserra + partículas de serragem + física gradual de tombamento.
-- 2. Desdobro do tronco caído em toras individuais via ox_target.
-- 3. Transporte das toras ao stand via Telehandler com garfo dinâmico (0.00ms idle).
-- 4. Camada de UI nativa (lation_ui com fallback ox_lib).

local active = false
local trees = {}          -- [id] = { obj, blip, cuttable }
local busyTree = nil      -- id em processamento local
local standBlip = nil

--------------------------------------------------------------------------------
-- Efeitos Visuais (Partículas de Serragem)
--------------------------------------------------------------------------------
local function startSawdustPtfx(prop)
    if not prop or not DoesEntityExist(prop) then return nil end
    local asset = Config.Assets.particles and Config.Assets.particles.asset or 'core'
    local name  = Config.Assets.particles and Config.Assets.particles.name or 'ent_dst_wood_splinter'
    if lib.requestNamedPtfxAsset(asset, 2000) then
        UseParticleFxAssetNextCall(asset)
        return StartParticleFxLoopedOnEntity(name, prop, 0.0, 0.4, 0.0, 0.0, 0.0, 0.0, 1.2, false, false, false)
    end
    return nil
end

local function stopSawdustPtfx(handle)
    if handle and DoesParticleFxLoopedExist(handle) then
        StopParticleFxLooped(handle, false)
    end
end

--------------------------------------------------------------------------------
-- Props das árvores e Blips
--------------------------------------------------------------------------------
local function setBlip(id, cuttable)
    local t = trees[id]
    if not t then return end
    if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    local c = Config.Cutting.trees[id]
    t.blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(t.blip, Config.Cutting.blip and Config.Cutting.blip.sprite or 1)
    SetBlipScale(t.blip, 0.65)
    SetBlipColour(t.blip, cuttable and 2 or 1)
    SetBlipAsShortRange(t.blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cuttable and 'Árvore (Corte)' or 'Toco de Árvore')
    EndTextCommandSetBlipName(t.blip)
end

local function startFell(id) end -- forward declaration

local function setVisual(id, cuttable)
    local t = trees[id]
    if not t then t = {}; trees[id] = t end
    t.cuttable = cuttable
    if t.obj and DoesEntityExist(t.obj) then
        exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell')
        DeleteEntity(t.obj)
    end
    local coord = Config.Cutting.trees[id]
    local model = cuttable and Config.Assets.props.tree or Config.Assets.props.stump
    if not lib.requestModel(model, 7000) then return end
    local obj = CreateObject(model, coord.x, coord.y, coord.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    SetEntityHeading(obj, (id * 37) % 360)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(model)
    t.obj = obj
    if cuttable then
        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'vp_lumberjack_fell',
                icon = 'fas fa-tree',
                label = locale('tree_target_cut'),
                distance = 2.5,
                onSelect = function() startFell(id) end
            },
        })
    end
    setBlip(id, cuttable)
end

--------------------------------------------------------------------------------
-- Motosserra na mão
--------------------------------------------------------------------------------
local function giveChainsawProp()
    local model = Config.Assets.props.chainsaw
    if not lib.requestModel(model, 4000) then return nil end
    local pc = GetEntityCoords(cache.ped)
    local prop = CreateObject(model, pc.x, pc.y, pc.z, true, true, false)
    local bone = GetPedBoneIndex(cache.ped, 28422) -- SKEL_R_Hand
    AttachEntityToEntity(prop, cache.ped, bone, 0.12, 0.0, -0.02, 90.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return prop
end

local function removeProp(prop)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

--------------------------------------------------------------------------------
-- Queda física realista da árvore (estilo plt_lumberjack Knockdown)
--------------------------------------------------------------------------------
local function fallTree(obj, fallDir)
    local yaw = GetHeadingFromVector_2d(fallDir.x, fallDir.y)
    SetEntityHeading(obj, yaw)
    local steps = Config.Cutting.fellSteps or 28
    local targetAngle = Config.Cutting.fellAngle or -85.0
    for i = 1, steps do
        local pitch = targetAngle * (i / steps)
        SetEntityRotation(obj, pitch, 0.0, yaw, 2, true)
        Wait(35)
    end
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    PlaySoundFrontend(-1, 'WOOD_BREAK', 'HUD_MINI_GAME_SOUNDSET', true)
end

--- Checa se há veículo bloqueando a queda da árvore
local function fallPathBlocked(treeCoords, fallDir)
    local mid = treeCoords + (fallDir * 5.0)
    local veh = GetClosestVehicle(mid.x, mid.y, mid.z, Config.Cutting.fellCheckRadius, 0, 70)
    if veh and veh ~= 0 and veh ~= VPL.GetJobVehicle() then return true end
    return false
end

--------------------------------------------------------------------------------
-- Fluxo de Corte e Desdobro de Toras
--------------------------------------------------------------------------------
startFell = function(id)
    if busyTree then return end
    if IsPedInAnyVehicle(cache.ped, false) then
        VPL.Notify('error', 'need_get_out')
        return
    end

    local ok, reason = lib.callback.await('vp_lumberjack:cutting:beginFell', false, id)
    if not ok then
        VPL.Notify('error', VPL.Err(reason, {
            need_chainsaw = 'need_chainsaw',
            too_far       = 'cut_too_far',
            not_cuttable  = 'cut_not_cuttable',
            no_session    = 'no_session',
        }))
        return
    end

    busyTree = id
    local treeCoords = Config.Cutting.trees[id]
    local fallDir = GetEntityCoords(cache.ped) - vector3(treeCoords.x, treeCoords.y, treeCoords.z)
    fallDir = fallDir / (#fallDir + 0.001)
    fallDir = vector3(-fallDir.x, -fallDir.y, 0.0)

    local saw = giveChainsawProp()
    local ptfx = startSawdustPtfx(saw)
    VPL.PlayChainsaw(cache.ped)

    -- Skillcheck + Barra de progresso (lation_ui / ox_lib)
    local pass = true
    if Config.Cutting.skillCheck and #Config.Cutting.skillCheck > 0 then
        pass = lib.skillCheck(Config.Cutting.skillCheck)
    end

    if pass then
        pass = VPL.UI.ProgressBar({
            duration = Config.Cutting.fellDuration,
            label = locale('cut_felling'),
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = Config.Assets.cutAnim.dict, clip = Config.Assets.cutAnim.clip },
        })
    end

    stopSawdustPtfx(ptfx)
    removeProp(saw)
    VPL.StopChainsaw()

    if not pass then
        TriggerServerEvent('vp_lumberjack:cutting:cancelFell', id)
        busyTree = nil
        VPL.Notify('inform', 'cut_cancelled')
        return
    end

    if fallPathBlocked(vector3(treeCoords.x, treeCoords.y, treeCoords.z), fallDir) then
        TriggerServerEvent('vp_lumberjack:cutting:cancelFell', id)
        busyTree = nil
        VPL.Notify('error', 'fell_blocked')
        return
    end

    local fok = lib.callback.await('vp_lumberjack:cutting:finishFell', false, id)
    if not fok then
        busyTree = nil
        VPL.Notify('error', 'cut_failed')
        return
    end

    -- 1. Queda Física da Árvore
    local t = trees[id]
    if t and t.obj and DoesEntityExist(t.obj) then
        exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell')
        FreezeEntityPosition(t.obj, false)
        fallTree(t.obj, fallDir)
    end

    -- 2. Etapa de Desdobro (Serrar o tronco em toras)
    saw = giveChainsawProp()
    ptfx = startSawdustPtfx(saw)
    VPL.PlayChainsaw(cache.ped)

    local cut = VPL.UI.ProgressBar({
        duration = Config.Cutting.buckDuration or 4500,
        label = locale('cut_logs'),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = Config.Assets.cutAnim.dict, clip = Config.Assets.cutAnim.clip },
    })

    stopSawdustPtfx(ptfx)
    removeProp(saw)
    VPL.StopChainsaw()

    if not cut then
        if t and t.obj and DoesEntityExist(t.obj) then DeleteEntity(t.obj) end
        setVisual(id, false)
        busyTree = nil
        VPL.Notify('inform', 'cut_cancelled')
        return
    end

    -- 3. Substituição por Fardo / Toras no chão para coleta com o garfo
    if t and t.obj and DoesEntityExist(t.obj) then DeleteEntity(t.obj) end
    local lm = Config.Assets.props.woodpile
    if not lib.requestModel(lm, 5000) then busyTree = nil; return end
    local bundle = CreateObject(lm, treeCoords.x, treeCoords.y, treeCoords.z, false, false, false)
    PlaceObjectOnGroundProperly(bundle)
    SetEntityHeading(bundle, GetHeadingFromVector_2d(fallDir.x, fallDir.y))
    FreezeEntityPosition(bundle, true)
    SetModelAsNoLongerNeeded(lm)

    VPL.Notify('inform', 'cut_load_ready')

    -- 4. Operação com Telehandler até o stand de toras
    local stand = Config.Cutting.stand
    local delivered = VPL.ForkCarry(
        bundle,
        GetEntityCoords(bundle),
        {
            coords = vector3(stand.coords.x, stand.coords.y, stand.coords.z),
            heading = stand.coords.w,
            radius = Config.Fork.alignDistance + 0.8
        },
        function()
            local dok, ddata = lib.callback.await('vp_lumberjack:cutting:deliver', false)
            if dok then
                VPL.Notify('success', 'cut_paid', VPL.Money(ddata.pay))
            else
                VPL.Notify('error', VPL.Err(ddata, { no_load = 'cut_failed', stand_far = 'stand_far' }))
            end
        end
    )

    if DoesEntityExist(bundle) then DeleteEntity(bundle) end
    if active then setVisual(id, false) end
    busyTree = nil
end

--------------------------------------------------------------------------------
-- Ciclo de Vida do Módulo
--------------------------------------------------------------------------------
local function setupCutting()
    if active then return end
    active = true
    local state = lib.callback.await('vp_lumberjack:cutting:getState', false)
    for _, t in ipairs(state) do
        setVisual(t.id, t.cuttable)
    end
    local sc = Config.Cutting.stand.coords
    standBlip = AddBlipForCoord(sc.x, sc.y, sc.z)
    SetBlipSprite(standBlip, 478)
    SetBlipColour(standBlip, 2)
    SetBlipScale(standBlip, 0.8)
    SetBlipAsShortRange(standBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.Cutting.stand.label)
    EndTextCommandSetBlipName(standBlip)
end

local function teardownCutting()
    active = false
    busyTree = nil
    for id, t in pairs(trees) do
        if t.obj and DoesEntityExist(t.obj) then
            exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell')
            DeleteEntity(t.obj)
        end
        if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    end
    trees = {}
    if standBlip and DoesBlipExist(standBlip) then RemoveBlip(standBlip); standBlip = nil end
end

RegisterNetEvent('vp_lumberjack:cutting:update', function(id, cuttable)
    if not active or id == busyTree then return end
    setVisual(id, cuttable)
end)

RegisterNetEvent('vp_lumberjack:client:jobStarted', function(jobKey)
    if jobKey == 'cutting' then setupCutting() else teardownCutting() end
end)

RegisterNetEvent('vp_lumberjack:client:jobEnded', function(jobKey)
    if jobKey == 'cutting' then teardownCutting() end
 end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        teardownCutting()
        VPL.StopChainsaw()
    end
end)
