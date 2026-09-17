-- vp_lumberjack v2 — ESTÁGIO Entrega (client): caminhão carregado → obra marcada →
-- descarregar pallet a pallet → devolver o caminhão. Paga por entrega + por km.

local active = false
local siteCoords = nil
local left = 0
local cosmetics = {}    -- pallets visuais na prancha
local siteBlip, zoneId = nil, nil

--------------------------------------------------------------------------------
-- Pallets cosméticos na prancha (visual da carga)
--------------------------------------------------------------------------------
local function attachCosmetics(n)
    local veh = VPL.GetJobVehicle()
    if not veh then return end
    local model = Config.Assets.props.woodpile
    if not lib.requestModel(model, 5000) then return end
    local vc = GetEntityCoords(veh)
    for i = 1, n do
        local p = CreateObject(model, vc.x, vc.y, vc.z, false, false, false)
        AttachEntityToEntity(p, veh, 0, 0.0, 1.5 - (i - 1) * 0.7, 0.95, 0.0, 0.0, 90.0,
            false, false, false, false, 1, true)
        cosmetics[#cosmetics + 1] = p
    end
    SetModelAsNoLongerNeeded(model)
end

local function popCosmetic()
    local i = #cosmetics
    if i > 0 then
        if DoesEntityExist(cosmetics[i]) then DeleteEntity(cosmetics[i]) end
        cosmetics[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Descarga
--------------------------------------------------------------------------------
local function unloadFlow()
    local okBegin, resBegin = lib.callback.await('vp_lumberjack:delivery:beginUnload', false)
    if not okBegin then
        VPL.Notify('error', VPL.Err(resBegin, {
            no_load = 'deliv_done', site_far = 'site_far', truck_far = 'truck_far', vehicle_gone = 'truck_far'
        }))
        return
    end

    local done = VPL.UI.ProgressBar({
        duration = Config.Delivery.unloadDuration,
        label = locale('deliv_unloading'),
        icon = 'dolly',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    if not done or not active then return end

    local ok, data = lib.callback.await('vp_lumberjack:delivery:finishUnload', false)
    if not active then return end

    if ok then
        left = data.left
        popCosmetic()
        VPL.Notify('success', 'deliv_paid', VPL.Money(data.pay))
        if left <= 0 then VPL.Notify('inform', 'deliv_done') end
    else
        VPL.Notify('error', VPL.Err(data, {
            no_load = 'deliv_done', site_far = 'site_far', truck_far = 'truck_far',
        }))
    end
end

--------------------------------------------------------------------------------
-- Setup / teardown
--------------------------------------------------------------------------------
local function setupDelivery()
    if active then return end
    active = true
    cosmetics = {}

    local ok, a = lib.callback.await('vp_lumberjack:delivery:getAssignment', false)
    if not ok then VPL.Notify('error', 'no_session'); active = false; return end
    left = a.left
    siteCoords = vector3(a.coords.x, a.coords.y, a.coords.z)

    siteBlip = AddBlipForCoord(siteCoords.x, siteCoords.y, siteCoords.z)
    SetBlipSprite(siteBlip, Config.Delivery.blip.sprite)
    SetBlipColour(siteBlip, Config.Delivery.blip.color)
    SetBlipScale(siteBlip, Config.Delivery.blip.scale)
    SetBlipRoute(siteBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(a.label); EndTextCommandSetBlipName(siteBlip)

    zoneId = exports.ox_target:addSphereZone({
        coords = siteCoords, radius = Config.Delivery.siteRadius, debug = Config.Debug,
        options = {
            {
                name = 'vp_lumberjack_unload', icon = 'fas fa-dolly', label = locale('deliv_target'),
                canInteract = function() return active and left > 0 end,
                onSelect = unloadFlow,
            },
        },
    })

    -- carga visual: espera o caminhão streamar e ancora os pallets
    CreateThread(function()
        local tries = 0
        while active and not VPL.GetJobVehicle() and tries < 50 do Wait(100); tries = tries + 1 end
        if active then attachCosmetics(left) end
    end)
end

local function teardownDelivery()
    active = false
    if siteBlip and DoesBlipExist(siteBlip) then RemoveBlip(siteBlip); siteBlip = nil end
    if zoneId then exports.ox_target:removeZone(zoneId); zoneId = nil end
    for _, e in ipairs(cosmetics) do if DoesEntityExist(e) then DeleteEntity(e) end end
    cosmetics = {}
end

AddEventHandler('vp_lumberjack:client:jobStarted', function(jobKey)
    if jobKey == 'delivery' then setupDelivery() end
end)
AddEventHandler('vp_lumberjack:client:jobEnded', function(jobKey)
    if jobKey == 'delivery' then teardownDelivery() end
end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then teardownDelivery() end
end)
