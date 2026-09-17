-- vp_lumberjack v3 — ESTÁGIO Empilhamento (client):
-- 1. Pegar pallets de madeira no pátio com o garfo da empilhadeira.
-- 2. Encaixar nos trailers com alinhamento visual e sonoro.
-- 3. Controle de rampas da carreta (ox_target) e fixação da empilhadeira para transporte.
-- 4. Resmon 0.00ms em repouso com tick rate dinâmico e interface lation_ui.

local active = false
local pallets = {}     -- { ent, coords, slot }
local placed = {}      -- entidades já encaixadas nos trailers
local trailers = {}    -- { ent, coords, heading, index, fill, full, rampsDown }
local carrying = nil   -- entidade do pallet no garfo
local dropped, totalCap = 0, 0
local yardBlip = nil
local textShown = false

local function showPrompt(text)
    if text and not textShown then
        VPL.UI.ShowText(text, 'fas fa-truck-ramp-box', 'E')
        textShown = true
    elseif not text and textShown then
        VPL.UI.HideText()
        textShown = false
    end
end

--------------------------------------------------------------------------------
-- Spawns de Pallets e Trailers
--------------------------------------------------------------------------------
local function spawnPallet(slot)
    local sp = Config.Stacking.palletSpawns[slot]
    local model = Config.Assets.props.woodpile
    if not lib.requestModel(model, 5000) then return end
    local ent = CreateObject(model, sp.x, sp.y, sp.z, false, false, false)
    PlaceObjectOnGroundProperly(ent)
    SetEntityHeading(ent, sp.w)
    FreezeEntityPosition(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetModelAsNoLongerNeeded(model)
    pallets[#pallets + 1] = { ent = ent, coords = GetEntityCoords(ent), slot = slot }
end

local function occupiedSlots()
    local set = {}
    for _, p in ipairs(pallets) do set[p.slot] = true end
    return set
end

local function refillPallets()
    local target = math.min(#Config.Stacking.palletSpawns, totalCap - dropped - (carrying and 1 or 0))
    local occ = occupiedSlots()
    for slot = 1, #Config.Stacking.palletSpawns do
        if #pallets >= target then break end
        if not occ[slot] then
            spawnPallet(slot)
            occ[slot] = true
        end
    end
end

local function toggleRamps(t)
    if not t or not DoesEntityExist(t.ent) then return end
    t.rampsDown = not t.rampsDown
    local door = Config.Stacking.ramp and Config.Stacking.ramp.doorIndex or 5
    if t.rampsDown then
        SetVehicleDoorOpen(t.ent, door, false, false)
        PlaySoundFrontend(-1, 'RAMP_DOWN', 'DLC_HEIST_FLEECA_SOUNDSET', true)
        VPL.Notify('inform', 'ramp_down')
    else
        SetVehicleDoorShut(t.ent, door, false)
        PlaySoundFrontend(-1, 'RAMP_UP', 'DLC_HEIST_FLEECA_SOUNDSET', true)
        VPL.Notify('inform', 'ramp_up')
    end
end

local function spawnTrailer(index)
    local sp = Config.Stacking.trailerSpawns[index]
    local model = Config.Assets.vehicles.trailer
    if not lib.requestModel(model, 7000) then return end
    local ent = CreateVehicle(GetHashKey(model), sp.x, sp.y, sp.z, sp.w, false, false)
    FreezeEntityPosition(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetVehicleDoorsLocked(ent, 2)
    SetModelAsNoLongerNeeded(model)

    local trailerData = {
        ent = ent,
        coords = vector3(sp.x, sp.y, sp.z),
        heading = sp.w,
        index = index,
        fill = 0,
        full = false,
        rampsDown = false
    }

    -- Suporte a controle de rampas no reboque
    exports.ox_target:addLocalEntity(ent, {
        {
            name = 'vp_lumberjack_trailer_ramp_' .. index,
            icon = 'fas fa-trailer',
            label = locale('ramp_toggle'),
            distance = 3.5,
            onSelect = function() toggleRamps(trailerData) end
        }
    })

    trailers[#trailers + 1] = trailerData
end

--------------------------------------------------------------------------------
-- Loop de Operação com Tick Rate Dinâmico (0.00ms idle)
--------------------------------------------------------------------------------
local function nearestPallet(tip)
    local best, bestD
    for _, p in ipairs(pallets) do
        local d = #(tip - p.coords)
        if d <= Config.Fork.alignDistance and (not bestD or d < bestD) then
            best, bestD = p, d
        end
    end
    return best
end

local function nearestTrailer(veh, tip)
    local best, bestD
    for _, t in ipairs(trailers) do
        if not t.full then
            local d = #(tip - t.coords)
            if d <= Config.Fork.alignDistance + 1.8
               and VPL.HeadingDiff(GetEntityHeading(veh), t.heading) <= Config.Fork.alignHeading
               and (not bestD or d < bestD) then
                best, bestD = t, d
            end
        end
    end
    return best
end

local function runLoop()
    CreateThread(function()
        while active do
            local ped = cache.ped
            local pCoords = GetEntityCoords(ped)
            local yardCoords = Config.Stacking.yard.coords
            local dist = #(pCoords - yardCoords)

            -- Resmon 0.00ms: Se longe do pátio, dorme
            if dist > Config.Stacking.yard.radius + 35.0 then
                showPrompt(nil)
                Wait(1000)
            elseif dist > Config.Stacking.yard.radius + 5.0 then
                showPrompt(nil)
                Wait(250)
            else
                local veh = VPL.InForkVehicle()
                if not veh then
                    showPrompt(nil)
                    Wait(300)
                else
                    Wait(0)
                    if not carrying then
                        for _, p in ipairs(pallets) do
                            VPL.DrawForkZone(p.coords)
                        end
                        local tip = VPL.ForkTip(veh)
                        local np = nearestPallet(tip)
                        if np then
                            showPrompt(locale('fork_grab'))
                            if IsControlJustReleased(0, Config.Fork.grabKey) then
                                VPL.ForkAttach(veh, np.ent)
                                carrying = np.ent
                                showPrompt(nil)
                                PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                                for i, p in ipairs(pallets) do
                                    if p == np then
                                        table.remove(pallets, i)
                                        break
                                    end
                                end
                            end
                        else
                            showPrompt(nil)
                        end
                    else
                        for _, t in ipairs(trailers) do
                            if not t.full then
                                VPL.DrawForkZone(t.coords)
                            end
                        end
                        local tip = VPL.ForkTip(veh)
                        local nt = nearestTrailer(veh, tip)
                        if nt then
                            showPrompt(locale('fork_drop'))
                            if IsControlJustReleased(0, Config.Fork.grabKey) then
                                local ok, res = lib.callback.await('vp_lumberjack:stacking:drop', false, nt.index)
                                if ok then
                                    nt.fill = res.fill
                                    nt.full = res.full
                                    dropped = dropped + 1

                                    -- Calcula posição no trailer (empilhamento gradual)
                                    local slotOffset = (nt.fill - 1) * 1.5 - 1.5
                                    local dropC = GetOffsetFromEntityInWorldCoords(nt.ent, 0.0, slotOffset, 0.6)
                                    VPL.ForkPlace(carrying, dropC, nt.heading)
                                    placed[#placed + 1] = carrying
                                    carrying = nil
                                    showPrompt(nil)
                                    PlaySoundFrontend(-1, 'Object_Dropped_Remote', 'GTAO_FM_Events_Soundset', true)

                                    VPL.Notify('success', 'stack_paid', VPL.Money(res.pay))
                                    if dropped >= totalCap then
                                        VPL.Notify('inform', 'stack_done')
                                    else
                                        refillPallets()
                                    end
                                else
                                    VPL.Notify('error', VPL.Err(res, { full = 'stack_full' }))
                                end
                            end
                        else
                            showPrompt(nil)
                        end
                    end
                end
            end
        end
        showPrompt(nil)
    end)
end

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------
local function setupStacking()
    if active then return end
    active = true
    pallets, placed, trailers = {}, {}, {}
    carrying = nil
    dropped = 0
    totalCap = #Config.Stacking.trailerSpawns * Config.Stacking.palletsPerTrailer

    local yc = Config.Stacking.yard.coords
    yardBlip = AddBlipForCoord(yc.x, yc.y, yc.z)
    SetBlipSprite(yardBlip, 478)
    SetBlipColour(yardBlip, 3)
    SetBlipScale(yardBlip, 0.8)
    SetBlipAsShortRange(yardBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Pátio de Empilhamento')
    EndTextCommandSetBlipName(yardBlip)

    for i = 1, #Config.Stacking.trailerSpawns do
        spawnTrailer(i)
    end
    refillPallets()
    runLoop()
end

local function teardownStacking()
    active = false
    showPrompt(nil)
    if yardBlip and DoesBlipExist(yardBlip) then
        RemoveBlip(yardBlip)
        yardBlip = nil
    end
    for _, p in ipairs(pallets) do
        if DoesEntityExist(p.ent) then DeleteEntity(p.ent) end
    end
    pallets = {}
    for _, ent in ipairs(placed) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    placed = {}
    for _, t in ipairs(trailers) do
        exports.ox_target:removeLocalEntity(t.ent, 'vp_lumberjack_trailer_ramp_' .. t.index)
        if DoesEntityExist(t.ent) then DeleteEntity(t.ent) end
    end
    trailers = {}
    if carrying and DoesEntityExist(carrying) then
        DetachEntity(carrying, true, true)
        DeleteEntity(carrying)
        carrying = nil
    end
end

RegisterNetEvent('vp_lumberjack:client:jobStarted', function(jobKey)
    if jobKey == 'stacking' then setupStacking() else teardownStacking() end
end)

RegisterNetEvent('vp_lumberjack:client:jobEnded', function(jobKey)
    if jobKey == 'stacking' then teardownStacking() end
end)
