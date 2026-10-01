-- vp_lumberjack v3 — ESTÁGIO Corte (server):
-- Estado autoritativo das árvores, validação de derrubada e entrega de toras.
-- Proteção estrita anti-exploit e fail-closed.

local Trees = {}

for id, coords in ipairs(Config.Cutting.trees) do
    Trees[id] = { coords = coords, cuttable = true }
end

local function broadcast(id, cuttable)
    TriggerClientEvent('vp_lumberjack:cutting:update', -1, id, cuttable)
end

local function isCutting(src)
    return VPL.GetJobOf(src) == 'cutting'
end

lib.callback.register('vp_lumberjack:cutting:getState', function(src)
    if not Security.IsValidSource(src) then return {} end
    local out = {}
    for id, t in pairs(Trees) do out[#out + 1] = { id = id, cuttable = t.cuttable } end
    return out
end)

--------------------------------------------------------------------------------
-- Derrubada Autoritativa
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:cutting:beginFell', function(src, id)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if type(id) ~= 'number' or id % 1 ~= 0 then
        Security.LogSuspicious(src, 'beginFell', 'bad id type=' .. type(id))
        return false, 'failed'
    end
    if Security.IsOnCooldown(src, 'fell', Config.Cooldowns.action) then return false, 'cooldown' end

    local t = Trees[id]
    if not t then
        Security.LogSuspicious(src, 'beginFell', 'id=' .. tostring(id))
        return false, 'not_cuttable'
    end
    if not t.cuttable then return false, 'not_cuttable' end
    if t.reservedBy and t.reservedBy ~= src then return false, 'not_cuttable' end
    if not VPL.HasChainsaw(src) then return false, 'need_chainsaw' end
    if Security.DistanceTo(src, t.coords) > Config.Cutting.interactRadius then return false, 'too_far' end

    t.reservedBy = src
    t.reserveExp = GetGameTimer() + Config.Cutting.fellDuration + 6000
    Security.BeginAuth(src, 'fell', id, Config.Cutting.fellMin)
    return true
end)

RegisterNetEvent('vp_lumberjack:cutting:cancelFell', function(id)
    local src = source
    if not Security.IsValidSource(src) or type(id) ~= 'number' then return end
    local t = Trees[id]
    if t and t.reservedBy == src then
        t.reservedBy = nil
        t.reserveExp = nil
    end
end)

lib.callback.register('vp_lumberjack:cutting:finishFell', function(src, id)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if type(id) ~= 'number' or id % 1 ~= 0 then
        Security.LogSuspicious(src, 'finishFell', 'bad id type=' .. type(id))
        return false, 'failed'
    end
    if not Security.ConsumeAuth(src, 'fell', id) then
        Security.LogSuspicious(src, 'finishFell', 'sem token/instant id=' .. tostring(id))
        return false, 'failed'
    end
    local t = Trees[id]
    if not t or not t.cuttable or t.reservedBy ~= src then return false, 'not_cuttable' end
    if not VPL.HasChainsaw(src) then return false, 'need_chainsaw' end
    if Security.DistanceTo(src, t.coords) > Config.Cutting.interactRadius + 2.5 then return false, 'too_far' end

    t.cuttable   = false
    t.reservedBy = nil
    t.reserveExp = nil
    t.respawnAt  = GetGameTimer() + (Config.Cutting.respawnMinutes * 60000)
    broadcast(id, false)

    -- Registra carga pendente de toras na sessao
    local s = VPL.GetSession(src)
    if s then
        s.cutPending = (s.cutPending or 0) + 1
    end

    -- Integração com vp_needs (Força, Estamina e Desgaste de Higiene)
    if GetResourceState('vp_needs') == 'started' then
        pcall(function()
            local completionId = ('lumber_fell_%d_%d_%d'):format(id, src, os.time())
            exports.vp_needs:HandleLumberjack(src, completionId)
        end)
    end

    return true
end)

--------------------------------------------------------------------------------
-- Entrega das Toras ao Stand
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:cutting:deliver', function(src)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'cutDeliver', Config.Cooldowns.action) then return false, 'cooldown' end

    local s = VPL.GetSession(src)
    if not s or (s.cutPending or 0) <= 0 then return false, 'no_load' end

    -- Fail-closed se o veiculo nao existir
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    local stand = Config.Cutting.stand
    if Security.DistanceTo(src, stand.coords) > stand.radius + 3.0 then return false, 'stand_far' end

    s.cutPending = s.cutPending - 1
    local pay = Config.Jobs.cutting.pay.perTree
    VPL.AddEarning(src, pay)

    -- Integração com vp_needs (Força, Desgaste Físico & Estamina)
    if GetResourceState('vp_needs') == 'started' then
        pcall(function()
            local completionId = ('lumber_deliver_%d_%d_%d'):format(src, s.cutPending, os.time())
            exports.vp_needs:HandleIntegration(src, 'lumberjack', completionId)
        end)
    end

    return true, { pay = pay }
end)

--------------------------------------------------------------------------------
-- Limpeza de reservas no cancelamento/fim da sessao
--------------------------------------------------------------------------------
AddEventHandler('vp_lumberjack:server:onSessionEnd', function(src, job)
    for _, t in pairs(Trees) do
        if t.reservedBy == src then
            t.reservedBy = nil
            t.reserveExp = nil
        end
    end
end)

--------------------------------------------------------------------------------
-- Thread de Respawn e Limpeza de Reservas
--------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for id, t in pairs(Trees) do
            if not t.cuttable and t.respawnAt and now >= t.respawnAt then
                t.cuttable  = true
                t.respawnAt = nil
                broadcast(id, true)
            end
            if t.reservedBy and t.reserveExp and now >= t.reserveExp then
                t.reservedBy = nil
                t.reserveExp = nil
            end
        end
    end
end)
