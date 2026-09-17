-- vp_lumberjack v3 — Camada de Interface Visual Unificada (UI Bridge)
-- Padrao obrigatorio: lation_ui com fallback automatico para ox_lib.
-- Garante zero erros de export e integracao nativa com o ecossistema visual.

VPL = VPL or {}
VPL.UI = {}

local isLationActive = GetResourceState('lation_ui') == 'started'
local textProvider = nil

AddEventHandler('onResourceStart', function(resName)
    if resName == 'lation_ui' then
        isLationActive = true
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName == 'lation_ui' then
        isLationActive = false
        textProvider = nil
    elseif resName == GetCurrentResourceName() then
        VPL.UI.HideText()
    end
end)

--- Exibe notificacao formatada
--- @param ntype 'success'|'error'|'inform'|'warning'
--- @param message string
--- @param title? string
function VPL.UI.Notify(ntype, message, title)
    title = title or 'Serraria'
    if isLationActive then
        local lationType = ntype == 'inform' and 'info' or ntype
        local ok = pcall(function()
            exports.lation_ui:notify({
                type = lationType,
                title = title,
                description = message,
                position = 'top-right'
            })
        end)
        if ok then return end
    end
    lib.notify({
        type = ntype,
        title = title,
        description = message
    })
end

--- Exibe TextUI na tela
--- @param text string
--- @param icon? string
--- @param keybind? string
function VPL.UI.ShowText(text, icon, keybind)
    if isLationActive then
        local ok = pcall(function()
            exports.lation_ui:showText({
                title = 'Lenhador',
                description = text,
                icon = icon or 'fas fa-tree',
                keybind = keybind,
                position = 'right-center'
            })
        end)
        if ok then
            textProvider = 'lation'
            return
        end
    end
    lib.showTextUI(text, {
        icon = icon or 'tree',
        position = 'right-center'
    })
    textProvider = 'ox'
end

--- Oculta TextUI da tela
function VPL.UI.HideText()
    if textProvider == 'lation' and isLationActive then
        pcall(function()
            exports.lation_ui:hideText()
        end)
    elseif textProvider == 'ox' then
        lib.hideTextUI()
    else
        -- Fallback seguro
        if isLationActive then
            pcall(function() exports.lation_ui:hideText() end)
        end
        lib.hideTextUI()
    end
    textProvider = nil
end

--- Executa barra de progresso com timeout de seguranca (anti-freeze)
--- @param data table
--- @return boolean success
function VPL.UI.ProgressBar(data)
    if isLationActive then
        local success = false
        local finished = false
        local ok = pcall(function()
            exports.lation_ui:progressBar({
                duration = data.duration or 5000,
                label = data.label or 'Trabalhando...',
                icon = data.icon,
                useWhileDead = data.useWhileDead or false,
                canCancel = data.canCancel ~= false,
                disable = data.disable,
                anim = data.anim,
                prop = data.prop
            }, function(cancelled)
                success = not cancelled
                finished = true
            end)
        end)
        if ok then
            local started = GetGameTimer()
            local duration = data.duration or 5000
            local timeout = duration + 3000
            while not finished do
                if GetGameTimer() - started > timeout then
                    return false
                end
                Wait(100)
            end
            return success
        end
    end
    return lib.progressBar(data) == true
end

--- Abre menu de contexto
--- @param menuId string
--- @param menuTitle string
--- @param menuOptions table
function VPL.UI.OpenMenu(menuId, menuTitle, menuOptions)
    lib.registerContext({
        id = menuId,
        title = menuTitle,
        options = menuOptions
    })
    lib.showContext(menuId)
end
