-- vp_lumberjack v2 — ESTÁGIO Empilhamento (server): validação do drop de pallet no trailer.
-- Fills por SESSÃO (cada empilhador tem seus trailers). Earning por pallet, pago na devolução.

local function isStacking(src)
    return VPL.GetJobOf(src) == 'stacking'
end

--- Registra o recolhimento de um pallet no garfo (autorizacao de transporte)
lib.callback.register('vp_lumberjack:stacking:pickup', function(src)
    if not Security.IsValidSource(src) or not isStacking(src) then return false, 'no_session' end
    local s = VPL.GetSession(src)
    if not s then return false, 'no_session' end

    -- Fail-closed se a empilhadeira nao existir
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    s.carryingPallet = true
    s.pickupTime = GetGameTimer()
    return true
end)

lib.callback.register('vp_lumberjack:stacking:drop', function(src, trailerIndex)
    if not Security.IsValidSource(src) or not isStacking(src) then return false, 'no_session' end
    if type(trailerIndex) ~= 'number' or trailerIndex % 1 ~= 0 then
        Security.LogSuspicious(src, 'stacking:drop', 'bad trailerIndex=' .. tostring(trailerIndex))
        return false, 'failed'
    end
    if Security.IsOnCooldown(src, 'stackDrop', Config.Cooldowns.action) then return false, 'cooldown' end

    local s = VPL.GetSession(src)
    if not s then return false, 'no_session' end

    -- Fail-closed se a empilhadeira nao existir
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        return false, 'vehicle_gone'
    end

    -- Prova de carga: exige que tenha pego pallet previamente
    if not s.carryingPallet then
        Security.LogSuspicious(src, 'stacking:drop', 'drop sem carregar pallet')
        return false, 'no_pallet'
    end

    -- Duracao minima de transporte (anti-instant injection)
    if (GetGameTimer() - (s.pickupTime or 0)) < 2500 then
        Security.LogSuspicious(src, 'stacking:drop', 'transporte rapido demais')
        return false, 'too_fast'
    end

    local trailer = Config.Stacking.trailerSpawns[trailerIndex]
    if not trailer then
        Security.LogSuspicious(src, 'stacking:drop', 'idx=' .. tostring(trailerIndex))
        return false, 'failed'
    end
    -- proximidade server-side (jogador perto do trailer)
    if Security.DistanceTo(src, trailer) > 14.0 then return false, 'too_far' end

    s.trailerFill = s.trailerFill or {}

    local cap  = Config.Stacking.palletsPerTrailer
    local fill = s.trailerFill[trailerIndex] or 0
    if fill >= cap then return false, 'full' end

    s.carryingPallet = false
    s.trailerFill[trailerIndex] = fill + 1
    local pay = Config.Jobs.stacking.pay.perPallet
    VPL.AddEarning(src, pay)

    return true, { fill = fill + 1, cap = cap, full = (fill + 1 >= cap), pay = pay }
end)

AddEventHandler('vp_lumberjack:server:onSessionEnd', function(src, job)
    local s = VPL.GetSession(src)
    if s then s.carryingPallet = false end
end)
