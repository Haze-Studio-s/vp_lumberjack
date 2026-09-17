-- vp_lumberjack v2 — Núcleo server: helpers (player/pay/tool) + spawn de veículo.
-- A sessão de trabalho (start/cancel/finish/pay) vive em server/framework.lua.

--- @param src number
--- @return table|nil
function VPL.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

--- Pagamento 100% server-side. Valor sempre calculado no server.
function VPL.Pay(src, amount, reason)
    if amount <= 0 then return false end
    local p = VPL.GetPlayer(src)
    if not p then return false end
    p.Functions.AddMoney('cash', amount, reason or 'vp_lumberjack')
    return true
end

--- @return boolean
function VPL.HasChainsaw(src)
    local c = exports.ox_inventory:GetItemCount(src, Config.Items.chainsaw)
    return c ~= nil and c > 0
end

--- Pode trabalhar? (respeita Config.RequireJob)
--- @param src number
--- @return boolean
function VPL.CanWork(src)
    if not Config.RequireJob then return true end
    local p = VPL.GetPlayer(src)
    if not p then return false end
    return p.PlayerData.job and p.PlayerData.job.name == Config.JobName
end

--- Spawna um veiculo de trabalho server-side (OneSync) e da a chave ao jogador.
--- @param src number
--- @param model string
--- @param spawn vector4
--- @return number|nil entity
function VPL.SpawnVehicle(src, model, spawn)
    if not model or type(model) ~= 'string' then return nil end
    local hash = GetHashKey(model)
    local veh = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    local timeout = 0
    while not DoesEntityExist(veh) and timeout < 100 do Wait(10); timeout = timeout + 1 end
    if not DoesEntityExist(veh) then return nil end

    Entity(veh).state:set('vpl_owner', src, true)
    pcall(function()
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            exports.qbx_vehiclekeys:GiveKeys(src, veh, true)
        end
    end)
    return veh
end

--------------------------------------------------------------------------------
-- Motosserra (item) — capataz entrega
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:getTool', function(src)
    if not Security.IsValidSource(src) then return false end
    if Security.IsOnCooldown(src, 'giveTool', Config.Cooldowns.giveTool) then return false, 'cooldown' end
    if Security.DistanceTo(src, Config.JobCenter.coords) > 6.0 then return false, 'too_far' end
    if not VPL.CanWork(src) then return false, 'no_job' end
    if VPL.HasChainsaw(src) then return false, 'have_already' end
    if not exports.ox_inventory:AddItem(src, Config.Items.chainsaw, 1) then return false end
    return true
end)
