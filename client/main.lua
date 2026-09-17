-- vp_lumberjack v2 — Client: capataz (NPC), painel ox_lib, roupa de trabalho e
-- zona de devolução do veículo (finaliza o job e recebe o acumulado).

local foreman = nil
local savedOutfit = nil   -- componentes originais p/ restaurar a roupa casual

--------------------------------------------------------------------------------
-- Roupa de trabalho
--------------------------------------------------------------------------------
local function applyWorkwear()
    local set = IsPedMale(cache.ped) and Config.Workwear.male or Config.Workwear.female
    if not savedOutfit then
        savedOutfit = {}
        for _, c in ipairs(set) do
            savedOutfit[c.component] = {
                d = GetPedDrawableVariation(cache.ped, c.component),
                t = GetPedTextureVariation(cache.ped, c.component),
            }
        end
    end
    for _, c in ipairs(set) do
        SetPedComponentVariation(cache.ped, c.component, c.drawable, c.texture, 0)
    end
    VPL.Notify('inform', 'wear_work')
end

local function applyCasual()
    if not savedOutfit then return end
    for comp, v in pairs(savedOutfit) do
        SetPedComponentVariation(cache.ped, comp, v.d, v.t, 0)
    end
    savedOutfit = nil
    VPL.Notify('inform', 'wear_casual')
end

--------------------------------------------------------------------------------
-- Ações do painel
--------------------------------------------------------------------------------
local function getChainsaw()
    local ok, reason = lib.callback.await('vp_lumberjack:getTool', false)
    if ok then
        VPL.Notify('success', 'tool_received')
    else
        VPL.Notify('error', VPL.Err(reason, {
            have_already = 'tool_have_already',
            no_job       = 'no_job',
            too_far      = 'center_far',
        }))
    end
end

local function buildJobOptions()
    -- ordena os jobs por .order
    local list = {}
    for key, job in pairs(Config.Jobs) do list[#list + 1] = { key = key, job = job } end
    table.sort(list, function(a, b) return (a.job.order or 99) < (b.job.order or 99) end)

    local opts = {}
    for _, e in ipairs(list) do
        opts[#opts + 1] = {
            title       = e.job.label,
            description = e.job.comment,
            icon        = 'tree',
            onSelect    = function() VPL.StartJob(e.key) end,
        }
    end
    return opts
end

local function openMenu()
    local opts = buildJobOptions()
    opts[#opts + 1] = { title = locale('menu_get_chainsaw'), icon = 'screwdriver-wrench', onSelect = getChainsaw }
    opts[#opts + 1] = { title = locale('menu_wear_work'),    icon = 'helmet-safety',     onSelect = applyWorkwear }
    opts[#opts + 1] = { title = locale('menu_wear_casual'),  icon = 'shirt',             onSelect = applyCasual }
    if VPL.CurrentJob() then
        opts[#opts + 1] = { title = locale('menu_cancel_job'), icon = 'ban', onSelect = function() VPL.CancelJob('manual') end }
    end

    VPL.UI.OpenMenu('vp_lumberjack_menu', locale('menu_title'), opts)
end

--------------------------------------------------------------------------------
-- Capataz + blip + zona de devolução
--------------------------------------------------------------------------------
local function setup()
    local c = Config.JobCenter.coords
    local model = type(Config.JobCenter.ped) == 'string' and joaat(Config.JobCenter.ped) or Config.JobCenter.ped
    if lib.requestModel(model, 10000) then
        foreman = CreatePed(0, model, c.x, c.y, c.z - 1.0, c.w, false, true)
        SetEntityInvincible(foreman, true)
        FreezeEntityPosition(foreman, true)
        SetBlockingOfNonTemporaryEvents(foreman, true)
        SetModelAsNoLongerNeeded(model)

        exports.ox_target:addLocalEntity(foreman, {
            { name = 'vp_lumberjack_foreman', icon = 'fas fa-tree', label = locale('foreman_target'), distance = 2.5, onSelect = openMenu },
        })
    end

    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, Config.JobCenter.blip.sprite)
    SetBlipColour(blip, Config.JobCenter.blip.color)
    SetBlipScale(blip, Config.JobCenter.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.JobCenter.blip.label)
    EndTextCommandSetBlipName(blip)

    -- zona de devolução: só aparece quando há job em andamento
    local rz = Config.JobCenter.returnZone
    exports.ox_target:addSphereZone({
        coords = rz.coords,
        radius = rz.radius,
        debug  = Config.Debug,
        options = {
            {
                name        = 'vp_lumberjack_return',
                icon        = 'fas fa-flag-checkered',
                label       = locale('return_target'),
                canInteract = function() return VPL.CurrentJob() ~= nil end,
                onSelect    = function() VPL.FinishJob() end,
            },
        },
    })
end

CreateThread(function()
    if not foreman then setup() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if foreman and DoesEntityExist(foreman) then DeleteEntity(foreman) end
end)
