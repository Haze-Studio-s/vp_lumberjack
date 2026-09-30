-- vp_lumberjack v2 — Núcleo server: helpers (player/pay/tool) + spawn de veículo.
-- A sessão de trabalho (start/cancel/finish/pay) vive em server/framework.lua.

--- @param src number
--- @return table|nil
function VPL.GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local _opSeq = 0

--- Sanitiza e limita o identificador de operação
local function normalizeOpId(raw)
    if type(raw) ~= 'string' then return nil end
    local clean = raw:gsub('[^%w%-_:]', '_')
    if #clean == 0 then return nil end
    if #clean > 128 then clean = clean:sub(1, 128) end
    return clean
end

--- Sanitiza e trunca a descrição da transação
local function cleanReason(raw)
    if type(raw) ~= 'string' or raw == '' then
        return 'vp_lumberjack'
    end
    local sanitized = raw:gsub('[%c]', ' ')
    if #sanitized > 128 then
        sanitized = sanitized:sub(1, 128)
    end
    return sanitized
end

--- Normaliza e valida valor monetário contra NaN, floats negativos e overflow
local function normalizeAmount(raw, maxCeiling)
    local n = tonumber(raw)
    if not n or n ~= n or n <= 0 or n > (maxCeiling or 1000000) then
        return nil
    end
    if n % 1 ~= 0 then
        return nil
    end
    return math.floor(n)
end

--- Gera operationId verdadeiramente idempotente se ref for fornecido
local function makeOpId(category, cid, ref)
    local token
    if ref and ref ~= '' then
        token = ('lumberjack:%s:%s:%s'):format(
            category or 'pay',
            cid or 'unknown',
            ref
        )
    else
        _opSeq = (_opSeq + 1) % 100000
        token = ('lumberjack:%s:%s:%d:%d'):format(
            category or 'pay',
            cid or 'unknown',
            os.time(),
            _opSeq
        )
    end
    return normalizeOpId(token)
end

--- Consulta saldo de jogador de forma segura e autoritativa
--- @param src number
--- @param account? 'bank'|'cash'
--- @return number
function VPL.GetMoney(src, account)
    account = account or (Config.PayoutAccount or 'bank')
    if account ~= 'bank' and account ~= 'cash' then
        return 0
    end

    local p = VPL.GetPlayer(src)
    if not p then return 0 end

    local cid = p.PlayerData and p.PlayerData.citizenid

    if account == 'bank' then
        if not cid then return 0 end
        local useAust = not Config.Integrations or Config.Integrations.aust_banking ~= false
        if useAust and type(GetResourceState) == 'function' and GetResourceState('aust_banking') == 'started' then
            local ok, bal = pcall(function()
                return exports['aust_banking']:GetBankBalance(cid)
            end)
            if ok and type(bal) == 'number' then
                return math.max(0, math.floor(bal))
            end
        end
        return (p.PlayerData and p.PlayerData.money and p.PlayerData.money.bank) or 0
    end

    if type(GetResourceState) == 'function' and GetResourceState('ox_inventory') == 'started' then
        local okItem, count = pcall(function()
            return exports.ox_inventory:GetItem(src, 'money', nil, true)
        end)
        return (okItem and type(count) == 'number') and count or 0
    end

    return (p.PlayerData and p.PlayerData.money and p.PlayerData.money.cash) or 0
end

--- Pagamento 100% server-side. Valor sempre calculado no server.
--- Padrão canônico QBox / aust_banking v3 Fail-Closed e ox_inventory.
--- @param src number
--- @param amount number
--- @param reason? string
--- @param customRef? string
--- @return boolean
function VPL.Pay(src, amount, reason, customRef)
    local cleanAmount = normalizeAmount(amount, 1000000)
    if not cleanAmount then return false end

    local p = VPL.GetPlayer(src)
    if not p then return false end

    local account = Config.PayoutAccount or 'bank'
    if account ~= 'bank' and account ~= 'cash' then
        lib.print.error(('[vp_lumberjack] Conta de pagamento inválida: %s'):format(tostring(account)))
        return false
    end

    local cid = p.PlayerData and p.PlayerData.citizenid
    local safeReason = cleanReason(reason or 'Salário da Serraria (vp_lumberjack)')

    if account == 'bank' then
        if not cid then
            lib.print.error(('[vp_lumberjack] Pagamento bancário rejeitado por ausência de citizenid. src=%s'):format(src))
            return false
        end

        local useAust = not Config.Integrations or Config.Integrations.aust_banking ~= false
        if useAust then
            if type(GetResourceState) ~= 'function' or GetResourceState('aust_banking') ~= 'started' then
                lib.print.error(('[vp_lumberjack] aust_banking ativo em config mas resource offline. Abortando pagamento para cid %s.'):format(cid))
                return false
            end

            local opId = makeOpId('pay', cid, customRef)
            local ok, res = pcall(function()
                return exports['aust_banking']:Credit({
                    citizenid = cid,
                    amount = cleanAmount,
                    reason = safeReason,
                    operationId = opId,
                    source = 'vp_lumberjack'
                })
            end)

            if ok and (res == true or (type(res) == 'table' and (res.ok == true or res.success == true))) then
                return true
            end

            lib.print.error(('[vp_lumberjack] Falha no crédito aust_banking v3 para cid %s (opId: %s). Abortando para evitar inconsistência contábil.'):format(cid, tostring(opId)))
            return false
        end

        -- Fallback qbx_core APENAS se aust_banking estiver explicitamente desligado em config
        return p.Functions.AddMoney('bank', cleanAmount, safeReason) and true or false
    end

    -- Dinheiro físico (item 'money' do ox_inventory) com verificação de capacidade segura
    if type(GetResourceState) == 'function' and GetResourceState('ox_inventory') == 'started' then
        local okCarry, canCarry = pcall(function()
            return exports.ox_inventory:CanCarryItem(src, 'money', cleanAmount)
        end)
        if not okCarry or not canCarry then
            lib.print.warn(('[vp_lumberjack] Jogador src=%s não possui capacidade no inventário para carregar $%s em espécie.'):format(src, cleanAmount))
            return false
        end

        local okAdd, resAdd = pcall(function()
            return exports.ox_inventory:AddItem(src, 'money', cleanAmount)
        end)
        if okAdd and resAdd then return true end
        return false
    end

    -- Fallback core para cash
    return p.Functions.AddMoney('cash', cleanAmount, safeReason) and true or false
end

--- Débito de taxa/caução server-side com fail-closed
--- @param src number
--- @param amount number
--- @param account? 'bank'|'cash'
--- @param reason? string
--- @param customRef? string
--- @return boolean
function VPL.RemoveMoney(src, amount, account, reason, customRef)
    local cleanAmount = normalizeAmount(amount, 1000000)
    if not cleanAmount then return false end

    local p = VPL.GetPlayer(src)
    if not p then return false end

    account = account or (Config.PayoutAccount or 'bank')
    if account ~= 'bank' and account ~= 'cash' then
        lib.print.error(('[vp_lumberjack] Conta de débito inválida: %s'):format(tostring(account)))
        return false
    end

    local cid = p.PlayerData and p.PlayerData.citizenid
    local safeReason = cleanReason(reason or 'Taxa da Serraria (vp_lumberjack)')

    if account == 'bank' then
        if not cid then
            lib.print.error(('[vp_lumberjack] Débito bancário rejeitado por ausência de citizenid. src=%s'):format(src))
            return false
        end

        local useAust = not Config.Integrations or Config.Integrations.aust_banking ~= false
        if useAust then
            if type(GetResourceState) ~= 'function' or GetResourceState('aust_banking') ~= 'started' then
                lib.print.error(('[vp_lumberjack] aust_banking ativo em config mas offline para débito. cid %s.'):format(cid))
                return false
            end

            local opId = makeOpId('debit', cid, customRef)
            local ok, res = pcall(function()
                return exports['aust_banking']:Debit({
                    citizenid = cid,
                    amount = cleanAmount,
                    reason = safeReason,
                    operationId = opId,
                    source = 'vp_lumberjack'
                })
            end)

            if ok and (res == true or (type(res) == 'table' and (res.ok == true or res.success == true))) then
                return true
            end
            return false
        end

        return p.Functions.RemoveMoney('bank', cleanAmount, safeReason) and true or false
    end

    -- Dinheiro físico (item 'money' do ox_inventory)
    if type(GetResourceState) == 'function' and GetResourceState('ox_inventory') == 'started' then
        local okCount, currentCount = pcall(function()
            return exports.ox_inventory:GetItem(src, 'money', nil, true)
        end)
        currentCount = (okCount and type(currentCount) == 'number') and currentCount or 0
        if currentCount < cleanAmount then return false end

        local okRemove, resRemove = pcall(function()
            return exports.ox_inventory:RemoveItem(src, 'money', cleanAmount)
        end)
        return okRemove and resRemove and true or false
    end

    return p.Functions.RemoveMoney('cash', cleanAmount, safeReason) and true or false
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
