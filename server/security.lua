-- vp_lumberjack — Camada de segurança server-side (SEMPRE presente — CLAUDE.md)
-- Princípio: o client nunca envia valor de pagamento nem confirma progresso. O server decide.

Security = {}

-- cooldowns[src][action] = expiresAtMs (GetGameTimer)
local cooldowns = {}
-- authTokens[src] = { action, refId, readyAt } — padrão token+timestamp (anti instant/auto-clicker)
local authTokens = {}

--- Valida que o source é um jogador real e carregado no qbx.
--- @param src number
--- @return boolean
function Security.IsValidSource(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    if not GetPlayerName(src) then return false end
    return exports.qbx_core:GetPlayer(src) ~= nil
end

--- true se a ação ainda está em cooldown; caso contrário registra e retorna false.
--- @param src number
--- @param action string
--- @param ms number
--- @return boolean onCooldown
function Security.IsOnCooldown(src, action, ms)
    local now = GetGameTimer()
    local bucket = cooldowns[src]
    if not bucket then bucket = {}; cooldowns[src] = bucket end
    local expires = bucket[action]
    if expires and now < expires then return true end
    bucket[action] = now + ms
    return false
end

--- Abre um token single-use com tempo mínimo. Server valida proximidade ANTES de chamar.
--- @param src number
--- @param action string
--- @param refId any        identificador da coisa (árvore, caminhão, obra)
--- @param minDurationMs number
function Security.BeginAuth(src, action, refId, minDurationMs)
    authTokens[src] = {
        action  = action,
        refId   = refId,
        readyAt = GetGameTimer() + minDurationMs,
    }
end

--- Consome o token: só true se existe, mesma ação/ref e o tempo mínimo já passou. Single-use.
--- @param src number
--- @param action string
--- @param refId any
--- @return boolean ok
function Security.ConsumeAuth(src, action, refId)
    local token = authTokens[src]
    authTokens[src] = nil
    if not token then return false end
    if token.action ~= action then return false end
    if token.refId ~= refId then return false end
    if GetGameTimer() < token.readyAt then return false end
    return true
end

--- Distância 3D do jogador a uma coord. Proximity check é SEMPRE server-side.
--- @param src number
--- @param coords vector3
--- @return number
function Security.DistanceTo(src, coords)
    local ped = GetPlayerPed(src)
    if ped == 0 then return math.huge end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
end

--- Limpa registros e tokens do jogador (usado no teardown de sessao).
--- @param src number
function Security.ClearPlayer(src)
    cooldowns[src]  = nil
    authTokens[src] = nil
end

--- Limpa apenas tokens pendentes de autorizacao.
--- @param src number
function Security.ClearAuth(src)
    authTokens[src] = nil
end

--- Loga atividade suspeita no console e (se configurado) num webhook Discord.
--- @param src number
--- @param event string
--- @param info string|nil
function Security.LogSuspicious(src, event, info)
    local name = GetPlayerName(src) or 'desconhecido'
    lib.print.warn(('[vp_lumberjack] SUSPEITO src=%s (%s) event=%s info=%s')
        :format(tostring(src), name, event, info or '-'))

    if Config.Webhook and Config.Webhook ~= '' then
        PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
            username = 'vp_lumberjack',
            content  = ('⚠️ **%s** | src `%s` (%s) | %s'):format(event, tostring(src), name, info or '-'),
        }), { ['Content-Type'] = 'application/json' })
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    Security.ClearPlayer(src)
end)
