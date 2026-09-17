-- vp_lumberjack v2 — ESTÁGIO Entrega (server): obra atribuída por sessão + descarga.
-- Paga perDelivery + perKm*distanceKm (distanceKm é AUTORITATIVO, do config) por pallet.

local function isDelivery(src)
    return VPL.GetJobOf(src) == 'delivery'
end

--- Atribui (uma vez) uma obra aleatória e a carga à sessão; devolve ao client.
lib.callback.register('vp_lumberjack:delivery:getAssignment', function(src)
    if not Security.IsValidSource(src) or not isDelivery(src) then return false, 'no_session' end
    local s = VPL.GetSession(src)
    if not s then return false, 'no_session' end

    if not s.site then
        s.site      = math.random(#Config.Delivery.sites)
        s.delivLeft = Config.Delivery.truckCapacity
    end
    local site = Config.Delivery.sites[s.site]
    return true, {
        siteIndex  = s.site,
        left       = s.delivLeft,
        label      = site.label,
        coords     = { x = site.coords.x, y = site.coords.y, z = site.coords.z },
        distanceKm = site.distanceKm,
    }
end)

--- Inicia a descarga de 1 pallet (abre token com duracao minima)
lib.callback.register('vp_lumberjack:delivery:beginUnload', function(src)
    if not Security.IsValidSource(src) or not isDelivery(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'delivUnload', Config.Cooldowns.action) then return false, 'cooldown' end

    local s = VPL.GetSession(src)
    if not s or not s.site or (s.delivLeft or 0) <= 0 then return false, 'no_load' end

    -- Fail-closed se o caminhao nao existir
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    local site = Config.Delivery.sites[s.site]
    local sc = vector3(site.coords.x, site.coords.y, site.coords.z)
    if Security.DistanceTo(src, sc) > Config.Delivery.siteRadius + 2.0 then return false, 'site_far' end
    if #(GetEntityCoords(s.vehicle) - sc) > Config.Delivery.siteRadius + 10.0 then
        return false, 'truck_far'
    end

    local minDuration = math.max(1000, (Config.Delivery.unloadDuration or 5000) - 1000)
    Security.BeginAuth(src, 'delivUnload', s.site, minDuration)
    return true
end)

--- Finaliza a descarga autoritativa com consumo de token
lib.callback.register('vp_lumberjack:delivery:finishUnload', function(src)
    if not Security.IsValidSource(src) or not isDelivery(src) then return false, 'no_session' end
    local s = VPL.GetSession(src)
    if not s or not s.site or (s.delivLeft or 0) <= 0 then return false, 'no_load' end

    -- Fail-closed se o caminhao nao existir
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    local site = Config.Delivery.sites[s.site]
    local sc = vector3(site.coords.x, site.coords.y, site.coords.z)
    if Security.DistanceTo(src, sc) > Config.Delivery.siteRadius + 2.0 then return false, 'site_far' end
    if #(GetEntityCoords(s.vehicle) - sc) > Config.Delivery.siteRadius + 10.0 then
        return false, 'truck_far'
    end

    if not Security.ConsumeAuth(src, 'delivUnload', s.site) then
        Security.LogSuspicious(src, 'finishUnload', 'instant/sem token valido')
        return false, 'failed'
    end

    s.delivLeft = s.delivLeft - 1
    local pay = Config.Jobs.delivery.pay.perDelivery + math.floor(Config.Jobs.delivery.pay.perKm * site.distanceKm)
    VPL.AddEarning(src, pay, { km = site.distanceKm })

    return true, { left = s.delivLeft, pay = pay }
end)

--- Compatibilidade legada (caso chamada direta)
lib.callback.register('vp_lumberjack:delivery:unload', function(src)
    if not Security.IsValidSource(src) or not isDelivery(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'delivUnload', Config.Cooldowns.action) then return false, 'cooldown' end

    local s = VPL.GetSession(src)
    if not s or not s.site or (s.delivLeft or 0) <= 0 then return false, 'no_load' end

    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    local site = Config.Delivery.sites[s.site]
    local sc = vector3(site.coords.x, site.coords.y, site.coords.z)
    if Security.DistanceTo(src, sc) > Config.Delivery.siteRadius + 2.0 then return false, 'site_far' end
    if #(GetEntityCoords(s.vehicle) - sc) > Config.Delivery.siteRadius + 10.0 then
        return false, 'truck_far'
    end

    s.delivLeft = s.delivLeft - 1
    local pay = Config.Jobs.delivery.pay.perDelivery + math.floor(Config.Jobs.delivery.pay.perKm * site.distanceKm)
    VPL.AddEarning(src, pay, { km = site.distanceKm })

    return true, { left = s.delivLeft, pay = pay }
end)
