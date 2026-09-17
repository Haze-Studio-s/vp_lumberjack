-- vp_lumberjack v2 — Controlador de sessão no client.
-- Inicia/finaliza/cancela o job e roda o WATCHDOG (morte / distância / dano do veículo),
-- Os módulos cutting/stacking/delivery escutam os eventos
-- 'vp_lumberjack:client:jobStarted' / ':jobEnded' p/ montar/desmontar seus objetivos.

local current = nil   -- { job, netId }
local watchdog = false

--- Notificação curta.
function VPL.Notify(ntype, key, ...)
    VPL.UI.Notify(ntype, locale(key, ...))
end

function VPL.Err(reason, map)
    if reason and map[reason] then return map[reason] end
    if reason == 'cooldown' then return 'cooldown' end
    return 'action_failed'
end

--- @return number|nil entity  veículo de trabalho atual (resolvido pelo netId)
function VPL.GetJobVehicle()
    if not current or not current.netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(current.netId)
    if ent ~= 0 and DoesEntityExist(ent) then return ent end
    return nil
end

--- @return string|nil jobKey
function VPL.CurrentJob()
    return current and current.job
end

--------------------------------------------------------------------------------
-- Watchdog: morte / distância / dano
--------------------------------------------------------------------------------
local function startWatchdog()
    if watchdog then return end
    watchdog = true
    CreateThread(function()
        local lastDistWarn, lastDmgWarn = 0, 0
        while current do
            Wait(Config.Cancel.checkInterval)
            if not current then break end

            -- morte
            if Config.Cancel.cancelOnDeath and IsEntityDead(cache.ped) then
                VPL.CancelJob('died')
                break
            end

            -- leash pelo VEÍCULO de trabalho (libera a entrega ir longe, mas não largar a
            -- máquina). Se o veículo não está streamado, pula a checagem (sem falso cancel).
            local veh = VPL.GetJobVehicle()
            if veh then
                local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(veh))
                if dist > Config.Cancel.maxDistanceFromVehicle then
                    VPL.CancelJob('away')
                    break
                elseif dist > Config.Cancel.warnDistanceFromVehicle then
                    local t = GetGameTimer()
                    if t - lastDistWarn > 5000 then
                        lastDistWarn = t
                        VPL.Notify('warning', 'warn_distance')
                    end
                end

                -- dano do veículo de trabalho
                local engine = GetVehicleEngineHealth(veh)
                local body   = GetVehicleBodyHealth(veh)
                if engine < Config.Cancel.engineHealthMin or body < Config.Cancel.bodyHealthMin then
                    VPL.CancelJob('damage')
                    break
                elseif engine < Config.Cancel.warnHealth or body < Config.Cancel.warnHealth then
                    local t = GetGameTimer()
                    if t - lastDmgWarn > 5000 then
                        lastDmgWarn = t
                        VPL.Notify('warning', 'warn_damage')
                    end
                end
            end
        end
        watchdog = false
    end)
end

--------------------------------------------------------------------------------
-- Início / fim / cancelamento
--------------------------------------------------------------------------------
function VPL.StartJob(jobKey)
    if current then VPL.Notify('error', 'already_working'); return end

    local ok, data = lib.callback.await('vp_lumberjack:startJob', false, jobKey)
    if not ok then
        VPL.Notify('error', VPL.Err(data, {
            already_working = 'already_working',
            no_job          = 'no_job',
            too_far         = 'center_far',
            spawns_full     = 'spawns_full',
        }))
        return
    end

    current = { job = jobKey, netId = data.netId }
    startWatchdog()
    VPL.Notify('inform', 'job_started_' .. jobKey)
    TriggerEvent('vp_lumberjack:client:jobStarted', jobKey)
end

function VPL.FinishJob()
    if not current then return end
    local ok, data = lib.callback.await('vp_lumberjack:returnVehicle', false)
    if not ok then
        VPL.Notify('error', VPL.Err(data, {
            no_session   = 'no_session',
            return_far   = 'return_far',
            vehicle_gone = 'vehicle_gone',
        }))
        if data == 'vehicle_gone' then
            -- server já encerrou a sessão; limpa o client
            local job = current.job
            current = nil
            TriggerEvent('vp_lumberjack:client:jobEnded', job)
        end
        return
    end

    local job = current.job
    current = nil
    TriggerEvent('vp_lumberjack:client:jobEnded', job)

    if data.earnings > 0 then
        VPL.Notify('success', 'job_paid', VPL.Money(data.earnings))
    else
        VPL.Notify('inform', 'job_no_earn')
    end
end

function VPL.CancelJob(reason)
    if not current then return end
    local job = current.job
    current = nil
    TriggerServerEvent('vp_lumberjack:cancelJob')
    TriggerEvent('vp_lumberjack:client:jobEnded', job)
    VPL.Notify('error', VPL.Err(reason, {
        died   = 'cancel_died',
        away   = 'cancel_away',
        damage = 'cancel_damage',
    }))
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and current then
        TriggerServerEvent('vp_lumberjack:cancelJob')
        current = nil
    end
end)
