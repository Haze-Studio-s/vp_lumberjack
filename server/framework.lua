-- vp_lumberjack v2 — Sessão de trabalho (server-authoritative).
-- O pagamento ACUMULA durante o job e só é creditado quando o jogador
-- DEVOLVE o veículo. Cancelar (morte/distância/dano) descarta o acumulado.

-- Sessions[src] = { job, earnings, vehicle, vehicleType, spawnIndex, finishing }
local Sessions = {}
local SpawnLocks = {}

--- @param src number
--- @return table|nil
function VPL.GetSession(src)
    return Sessions[src]
end

local function maxEarningsForSession(jobKey)
    if jobKey == 'cutting' then
        return (Config.Jobs.cutting.pay.perTree or 800) * 50
    elseif jobKey == 'stacking' then
        return #Config.Stacking.trailerSpawns * Config.Stacking.palletsPerTrailer * (Config.Jobs.stacking.pay.perPallet or 600) * 2
    elseif jobKey == 'delivery' then
        return (#Config.Delivery.sites * Config.Delivery.truckCapacity * ((Config.Jobs.delivery.pay.perDelivery or 700) + (Config.Jobs.delivery.pay.perKm or 400) * 30))
    end
    return 100000
end

--- Soma ao acumulado do job atual (chamado pelos modulos cutting/stacking/delivery).
--- @param src number
--- @param amount number
--- @param breakdown? table  ex.: { km = 7.8 } p/ relatorio
function VPL.AddEarning(src, amount, breakdown)
    local s = Sessions[src]
    if not s or amount <= 0 or s.finishing then return end
    local cap = maxEarningsForSession(s.job)
    s.earnings = math.min((s.earnings or 0) + amount, cap)
    if breakdown and breakdown.km then s.travelKm = (s.travelKm or 0) + breakdown.km end
end

--- @param src number
--- @return string|nil jobKey
function VPL.GetJobOf(src)
    local s = Sessions[src]
    return s and s.job
end

--------------------------------------------------------------------------------
-- Escolha de ponto de spawn livre
--------------------------------------------------------------------------------
local function freeSpawnIndex()
    local used = {}
    for _, s in pairs(Sessions) do
        if s.spawnIndex then used[s.spawnIndex] = true end
    end
    for idx in pairs(SpawnLocks) do
        used[idx] = true
    end
    for i = 1, #Config.JobCenter.vehicleSpawns do
        if not used[i] then return i end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Iniciar job
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:startJob', function(src, jobKey)
    if not Security.IsValidSource(src) then return false end
    if Security.IsOnCooldown(src, 'startJob', Config.Cooldowns.startJob) then return false, 'cooldown' end
    if Sessions[src] then return false, 'already_working' end
    if not VPL.CanWork(src) then return false, 'no_job' end

    local job = Config.Jobs[jobKey]
    if not job then
        Security.LogSuspicious(src, 'startJob', 'jobKey=' .. tostring(jobKey))
        return false, 'badjob'
    end
    if Security.DistanceTo(src, Config.JobCenter.coords) > 25.0 then return false, 'too_far' end

    local idx = freeSpawnIndex()
    if not idx then return false, 'spawns_full' end

    -- Trava imediatamente o ponto de spawn contra race condition de multiplos spawns
    SpawnLocks[idx] = src

    local model = Config.Assets.vehicles[job.vehicle]
    local veh = VPL.SpawnVehicle(src, model, Config.JobCenter.vehicleSpawns[idx])
    SpawnLocks[idx] = nil

    if not veh then return false, 'spawnfail' end

    Sessions[src] = {
        job         = jobKey,
        earnings    = 0,
        travelKm    = 0,
        vehicle     = veh,
        vehicleType = job.vehicle,
        spawnIndex  = idx,
    }
    -- netId p/ o watchdog do client checar dano do veiculo de trabalho
    return true, { job = jobKey, netId = NetworkGetNetworkIdFromEntity(veh) }
end)

--------------------------------------------------------------------------------
-- Devolver veiculo e finalizar (paga o acumulado)
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:returnVehicle', function(src)
    if not Security.IsValidSource(src) then return false end
    if Security.IsOnCooldown(src, 'returnVehicle', Config.Cooldowns.returnVehicle) then return false, 'cooldown' end

    local s = Sessions[src]
    if not s or s.finishing then return false, 'no_session' end

    -- jogador e veiculo precisam estar na zona de devolucao (proximity server-side)
    local rz = Config.JobCenter.returnZone
    if Security.DistanceTo(src, rz.coords) > rz.radius + 1.0 then return false, 'return_far' end
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        Sessions[src] = nil
        Security.ClearPlayer(src)
        TriggerEvent('vp_lumberjack:server:onSessionEnd', src, s.job)
        return false, 'vehicle_gone'
    end
    if #(GetEntityCoords(s.vehicle) - rz.coords) > rz.radius + 2.0 then return false, 'return_far' end

    -- Previne reentrancia de pagamento: marca e retira a sessao ANTES do pagamento
    s.finishing = true
    local earnings = s.earnings
    local km = s.travelKm or 0
    local jobName = s.job
    local veh = s.vehicle

    Sessions[src] = nil
    Security.ClearPlayer(src)
    TriggerEvent('vp_lumberjack:server:onSessionEnd', src, jobName)

    if veh and DoesEntityExist(veh) then
        DeleteEntity(veh)
    end

    if earnings > 0 then
        VPL.Pay(src, earnings, 'vp_lumberjack-' .. jobName)
    end

    return true, { earnings = earnings, km = km, job = jobName }
end)

--------------------------------------------------------------------------------
-- Cancelar job — sem pagamento
--------------------------------------------------------------------------------
local function endSession(src, deleteVeh)
    local s = Sessions[src]
    if not s then return end
    s.finishing = true
    local job = s.job
    local veh = s.vehicle
    Sessions[src] = nil
    Security.ClearPlayer(src)
    TriggerEvent('vp_lumberjack:server:onSessionEnd', src, job)

    if deleteVeh and veh and DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
end

RegisterNetEvent('vp_lumberjack:cancelJob', function()
    local src = source
    if not Security.IsValidSource(src) then return end
    endSession(src, true)
end)

--------------------------------------------------------------------------------
-- Watchdog Server-Side (independente do client)
--------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.Cancel and Config.Cancel.checkInterval or 2000)
        for src, s in pairs(Sessions) do
            if not s.finishing then
                local ped = GetPlayerPed(src)
                if ped == 0 or not GetPlayerName(src) then
                    endSession(src, true)
                elseif Config.Cancel and Config.Cancel.cancelOnDeath and IsEntityDead(ped) then
                    endSession(src, true)
                elseif not s.vehicle or not DoesEntityExist(s.vehicle) then
                    endSession(src, false)
                else
                    local dist = #(GetEntityCoords(ped) - GetEntityCoords(s.vehicle))
                    if Config.Cancel and dist > Config.Cancel.maxDistanceFromVehicle then
                        endSession(src, true)
                    elseif Config.Cancel and (GetVehicleEngineHealth(s.vehicle) < Config.Cancel.engineHealthMin or GetVehicleBodyHealth(s.vehicle) < Config.Cancel.bodyHealthMin) then
                        endSession(src, true)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Limpeza
--------------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    endSession(source, true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Sessions) do endSession(src, true) end
end)
