-- vp_lumberjack v2 — Núcleo server: helpers (player/pay/tool) + spawn de veículo.
-- A sessão de trabalho (start/cancel/finish/pay) vive em server/framework.lua.

--- @param src number
--- @return table|nil
function VPL.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

--- Pagamento 100% server-side. Valor sempre calculado no server.
--- Padrão canônico QBox / aust_banking v3 Fail-Closed e ox_inventory.
function VPL.Pay(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    local p = VPL.GetPlayer(src)
    if not p then return false end

    local account = Config.PayoutAccount or 'bank'
    local cid = p.PlayerData and p.PlayerData.citizenid

    if account == 'bank' and cid then
        if type(GetResourceState) == 'function' and GetResourceState('aust_banking') == 'started' then
            local optId = ('lumberjack:pay:%s:%d:%d'):format(cid, amount, os.time())
            local ok, res = pcall(function()
                return exports['aust_banking']:Credit({
                    target = cid,
                    amount = amount,
                    reason = reason or 'Salário da Serraria (vp_lumberjack)',
                    operationId = optId
                })
            end)
            if ok and res and res.success then
                return true
            end
            print(('[vp_lumberjack] Falha no crédito aust_banking para cid %s (optId: %s). Abortando para evitar duplo pagamento.'):format(cid, optId))
            return false
        end
        return p.Functions.AddMoney('bank', amount, reason or 'vp_lumberjack') and true or false
    end

    -- Dinheiro físico (item 'money' do ox_inventory)
    if type(GetResourceState) == 'function' and GetResourceState('ox_inventory') == 'started' then
        local ok, res = pcall(function()
            return exports.ox_inventory:AddItem(src, 'money', amount)
        end)
        if ok and res then return true end
    end

    -- Fallback core
    return p.Functions.AddMoney('cash', amount, reason or 'vp_lumberjack') and true or false
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
