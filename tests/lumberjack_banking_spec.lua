-- tests/lumberjack_banking_spec.lua
-- Suíte de testes unitários para a integração canônica aust_banking v3 e fail-closed em vp_lumberjack

local totalTests = 0
local passedTests = 0

local function assertEqual(expected, actual, testName)
    totalTests = totalTests + 1
    if expected == actual then
        passedTests = passedTests + 1
        print(string.format('  [PASS] %s', testName))
    else
        print(string.format('  [FAIL] %s: esperado %s, obtido %s', testName, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(condition, testName)
    assertEqual(true, condition, testName)
end

local function assertFalse(condition, testName)
    assertEqual(false, condition, testName)
end

print('=== INICIANDO TESTES UNITÁRIOS: VP_LUMBERJACK BANKING INTEGRATION ===')

-- Mock global environment
_G.Config = {
    PayoutAccount = 'bank',
    Integrations = {
        aust_banking = true,
    }
}

_G.VPL = {}
_G.lib = {
    print = {
        error = function(...) end,
        warn = function(...) end,
        info = function(...) end,
    },
    locale = function() end,
    callback = {
        register = function() end,
    }
}

local mockBankBalance = 5000
local mockCashCount = 200
local mockCanCarry = true
local mockAustStarted = true
local mockOxStarted = true
local mockAustCreditResult = { ok = true, success = true }
local mockAustDebitResult = { ok = true, success = true }
local lastAustCreditPayload = nil
local lastAustDebitPayload = nil
local lastCoreAddCalls = {}
local lastCoreRemoveCalls = {}
local lastOxAddCalls = {}
local lastOxRemoveCalls = {}

_G.GetResourceState = function(res)
    if res == 'aust_banking' then
        return mockAustStarted and 'started' or 'stopped'
    elseif res == 'ox_inventory' then
        return mockOxStarted and 'started' or 'stopped'
    elseif res == 'qbx_vehiclekeys' then
        return 'started'
    end
    return 'missing'
end

local function getArg(a1, a2)
    if type(a1) == 'table' and a2 ~= nil then return a2 end
    return a1
end

local function getArgs(a1, a2, a3, a4)
    if type(a1) == 'table' and a2 ~= nil then
        return a2, a3, a4
    end
    return a1, a2, a3, a4
end

_G.exports = {
    ['aust_banking'] = {
        GetBankBalance = function(...)
            local cid = getArg(...)
            return mockBankBalance
        end,
        Credit = function(...)
            local params = getArg(...)
            lastAustCreditPayload = params
            return mockAustCreditResult
        end,
        Debit = function(...)
            local params = getArg(...)
            lastAustDebitPayload = params
            return mockAustDebitResult
        end,
    },
    ['ox_inventory'] = {
        GetItem = function(...)
            local src, item, metadata, countOnly = getArgs(...)
            if item == 'money' then return mockCashCount end
            return 0
        end,
        CanCarryItem = function(...)
            local src, item, count = getArgs(...)
            return mockCanCarry
        end,
        AddItem = function(...)
            local src, item, count = getArgs(...)
            table.insert(lastOxAddCalls, { src = src, item = item, count = count })
            return true
        end,
        RemoveItem = function(...)
            local src, item, count = getArgs(...)
            table.insert(lastOxRemoveCalls, { src = src, item = item, count = count })
            return true
        end,
        GetItemCount = function(...)
            return 1
        end,
    },
    ['qbx_core'] = {
        GetPlayer = function(...)
            local src = getArg(...)
            if src == 1 then
                return {
                    PlayerData = {
                        citizenid = 'CID_LUMBER_999',
                        money = {
                            bank = 1000,
                            cash = 50,
                        },
                        job = {
                            name = 'lumberjack',
                        }
                    },
                    Functions = {
                        AddMoney = function(account, amount, reason)
                            table.insert(lastCoreAddCalls, { account = account, amount = amount, reason = reason })
                            return true
                        end,
                        RemoveMoney = function(account, amount, reason)
                            table.insert(lastCoreRemoveCalls, { account = account, amount = amount, reason = reason })
                            return true
                        end,
                    }
                }
            end
            return nil
        end,
    }
}

-- Load server/main.lua
local mainChunk = loadfile('resources/[standalone]/vp_lumberjack/server/main.lua')
if not mainChunk then
    error('Falha ao carregar server/main.lua')
end
mainChunk()

print('\n-- Testes de Consulta de Saldo (VPL.GetMoney) --')
do
    mockAustStarted = true
    Config.Integrations.aust_banking = true
    local bankBal = VPL.GetMoney(1, 'bank')
    assertEqual(5000, bankBal, 'GetMoney bank via aust_banking')

    mockAustStarted = false
    local coreBal = VPL.GetMoney(1, 'bank')
    assertEqual(1000, coreBal, 'GetMoney bank fallback para core quando aust offline')

    local cashBal = VPL.GetMoney(1, 'cash')
    assertEqual(200, cashBal, 'GetMoney cash via ox_inventory')
end

print('\n-- Testes de Pagamento Bancário (VPL.Pay - bank) --')
do
    mockAustStarted = true
    Config.Integrations.aust_banking = true
    Config.PayoutAccount = 'bank'
    lastAustCreditPayload = nil
    mockAustCreditResult = { ok = true, success = true }

    -- 1. Pagamento válido
    local ok = VPL.Pay(1, 1500, 'Entrega de Madeiras', 'delivery_pallet_123')
    assertTrue(ok, 'VPL.Pay com sucesso via aust_banking v3')
    assertTrue(lastAustCreditPayload ~= nil, 'Payload foi passado para aust_banking')
    assertEqual('CID_LUMBER_999', lastAustCreditPayload.citizenid, 'Chave citizenid usada corretamente')
    assertEqual(1500, lastAustCreditPayload.amount, 'Valor normalizado passado')
    assertEqual('vp_lumberjack', lastAustCreditPayload.source, 'Source identificado')
    assertEqual('lumberjack:pay:CID_LUMBER_999:delivery_pallet_123', lastAustCreditPayload.operationId, 'OperationId estritamente determinístico com ref')

    -- Idempotência estrita: segunda chamada com mesmo ref gera EXATAMENTE o mesmo operationId
    VPL.Pay(1, 1500, 'Entrega de Madeiras', 'delivery_pallet_123')
    assertEqual('lumberjack:pay:CID_LUMBER_999:delivery_pallet_123', lastAustCreditPayload.operationId, 'Idempotência comprovada: mesmo ref gera mesmo opId')

    -- Suporte a retorno booleano true
    mockAustCreditResult = true
    local okBool = VPL.Pay(1, 500, 'Pagamento retorno booleano', 'bool_test')
    assertTrue(okBool, 'VPL.Pay aceita retorno booleano true do aust_banking')
    mockAustCreditResult = { ok = true, success = true }

    -- Rejeição de conta inválida
    Config.PayoutAccount = 'invalid_acc'
    assertFalse(VPL.Pay(1, 100, 'Conta invalida'), 'Rejeita conta inexistente (não cai para cash)')
    Config.PayoutAccount = 'bank'

    -- 2. Valores inválidos
    assertFalse(VPL.Pay(1, -100, 'Invalido'), 'Rejeita valor negativo')
    assertFalse(VPL.Pay(1, 0, 'Invalido'), 'Rejeita valor zero')
    assertFalse(VPL.Pay(1, 0/0, 'Invalido'), 'Rejeita NaN')
    assertFalse(VPL.Pay(1, 150.75, 'Invalido'), 'Rejeita valor fracionado')
    assertFalse(VPL.Pay(1, 2000000, 'Invalido'), 'Rejeita valor acima do teto de 1M')
    assertFalse(VPL.Pay(999, 500, 'Invalido'), 'Rejeita player inexistente')

    -- 3. Fail-Closed quando aust_banking rejeita
    mockAustCreditResult = { ok = false, error = 'DATABASE_TIMEOUT' }
    lastCoreAddCalls = {}
    local okFail = VPL.Pay(1, 800, 'Falha no banco')
    assertFalse(okFail, 'VPL.Pay fail-closed quando aust_banking retorna ok=false')
    assertEqual(0, #lastCoreAddCalls, 'Não deve fazer fallback silencioso para qbx_core se aust ativo')

    -- 4. Fail-Closed quando aust_banking resource está parado
    mockAustStarted = false
    local okOffline = VPL.Pay(1, 800, 'Banco desligado')
    assertFalse(okOffline, 'VPL.Pay fail-closed quando resource aust_banking parado')

    -- 5. Fallback permitido apenas quando explicitamente desativado em config
    mockAustStarted = false
    Config.Integrations.aust_banking = false
    lastCoreAddCalls = {}
    local okConfigOff = VPL.Pay(1, 750, 'Config desligada')
    assertTrue(okConfigOff, 'VPL.Pay recorre a qbx_core se aust_banking = false na config')
    assertEqual(1, #lastCoreAddCalls, 'Core AddMoney chamado')
    assertEqual(750, lastCoreAddCalls[1].amount, 'Valor correto passado ao core')
end

print('\n-- Testes de Pagamento em Espécie (VPL.Pay - cash) --')
do
    Config.PayoutAccount = 'cash'
    mockOxStarted = true
    mockCanCarry = true
    lastOxAddCalls = {}

    -- 1. Sucesso quando cabe no bolso
    local okCash = VPL.Pay(1, 350, 'Pagamento em mãos')
    assertTrue(okCash, 'VPL.Pay cash sucesso')
    assertEqual(1, #lastOxAddCalls, 'ox_inventory AddItem chamado')
    assertEqual(350, lastOxAddCalls[1].count, 'Quantidade correta de notas')

    -- 2. Fail-Closed quando inventário cheio (CanCarryItem = false)
    mockCanCarry = false
    lastOxAddCalls = {}
    local okFull = VPL.Pay(1, 350, 'Sem espaço')
    assertFalse(okFull, 'VPL.Pay cash fail-closed quando sem espaço no inventário')
    assertEqual(0, #lastOxAddCalls, 'Não chama AddItem se não couber')
end

print('\n-- Testes de Débito de Taxas/Caução (VPL.RemoveMoney) --')
do
    mockAustStarted = true
    Config.Integrations.aust_banking = true
    Config.PayoutAccount = 'bank'
    lastAustDebitPayload = nil
    mockAustDebitResult = { ok = true, success = true }

    -- 1. Débito bancário válido
    local okDebit = VPL.RemoveMoney(1, 200, 'bank', 'Caução de Motosserra', 'tool_deposit')
    assertTrue(okDebit, 'VPL.RemoveMoney sucesso via aust_banking Debit')
    assertTrue(lastAustDebitPayload ~= nil, 'Payload debit enviado')
    assertEqual('CID_LUMBER_999', lastAustDebitPayload.citizenid, 'citizenid no Debit')
    assertEqual(200, lastAustDebitPayload.amount, 'Valor de débito correto')
    assertEqual('lumberjack:debit:CID_LUMBER_999:tool_deposit', lastAustDebitPayload.operationId, 'OperationId de débito determinístico')

    -- 2. Débito bancário com saldo insuficiente no banco
    mockAustDebitResult = { ok = false, error = 'INSUFFICIENT_FUNDS' }
    local okNoFunds = VPL.RemoveMoney(1, 99999, 'bank', 'Taxa alta')
    assertFalse(okNoFunds, 'VPL.RemoveMoney falha se saldo insuficiente')

    -- 3. Débito em espécie
    mockOxStarted = true
    mockCashCount = 500
    lastOxRemoveCalls = {}
    local okCashRemove = VPL.RemoveMoney(1, 100, 'cash', 'Taxa em mãos')
    assertTrue(okCashRemove, 'VPL.RemoveMoney cash sucesso')
    assertEqual(1, #lastOxRemoveCalls, 'ox_inventory RemoveItem executado')

    -- 4. Débito em espécie com saldo insuficiente
    mockCashCount = 50
    local okCashShort = VPL.RemoveMoney(1, 100, 'cash', 'Taxa maior que saldo')
    assertFalse(okCashShort, 'VPL.RemoveMoney cash bloqueia se dinheiro insuficiente')
end

print(string.format('\n=== RESULTADO FINAL: %d/%d TESTES PASSARAM (%.1f%%) ===', passedTests, totalTests, (passedTests / totalTests) * 100))
if passedTests < totalTests then
    os.exit(1)
end
