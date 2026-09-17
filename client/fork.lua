-- vp_lumberjack v3 — Operação de garfo REUTILIZÁVEL (telehandler / empilhadeira).
-- Resmon 0.00ms em repouso: Tick rate dinâmico (acorda para Wait(0) apenas na zona ativa).
-- Integração nativa com lation_ui e ox_lib.

VPL = VPL or {}

--- Posição mundial da ponta do garfo + índice do bone (fallback p/ offset do config).
--- @param veh number
--- @return vector3 pos, number boneIdx
function VPL.ForkTip(veh)
    local idx = GetEntityBoneIndexByName(veh, Config.Fork.forkBone)
    if idx and idx ~= -1 then
        return GetWorldPositionOfEntityBone(veh, idx), idx
    end
    local o = Config.Fork.forkOffset
    return GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z), 0
end

--- Veículo de trabalho atual SE o jogador estiver nele. @return number|nil
function VPL.InForkVehicle()
    local veh = VPL.GetJobVehicle()
    if veh and GetVehiclePedIsIn(cache.ped, false) == veh then return veh end
    return nil
end

--- Desenha o marcador da zona (chão) com interpolação suave.
function VPL.DrawForkZone(coords)
    local m, c = Config.Fork.markerSize, Config.Fork.markerColor
    DrawMarker(1, coords.x, coords.y, coords.z - 0.95, 0, 0, 0, 0, 0, 0,
        m.x, m.y, m.z, c.r, c.g, c.b, c.a, false, false, 2, false, nil, nil, false)
end

--- Gruda a carga no garfo do veículo.
function VPL.ForkAttach(veh, load)
    local _, b = VPL.ForkTip(veh)
    local a = Config.Fork.loadAttach
    AttachEntityToEntity(load, veh, b, a.x, a.y, a.z, 0.0, 0.0, 0.0, false, false, false, false, 1, true)
end

--- Solta a carga e a posiciona/congela no destino.
function VPL.ForkPlace(load, coords, heading)
    if not DoesEntityExist(load) then return end
    DetachEntity(load, true, true)
    SetEntityCoords(load, coords.x, coords.y, coords.z, false, false, false, false)
    if heading then SetEntityHeading(load, heading) end
    FreezeEntityPosition(load, true)
end

--- Carrega `load` do ponto de coleta até o drop com tick rate dinâmico (0.00ms idle).
--- @param load number
--- @param pickupCoords vector3
--- @param drop table { coords=vector3, heading=number, radius=number }
--- @param onDropped fun()|nil
--- @return boolean delivered
function VPL.ForkCarry(load, pickupCoords, drop, onDropped)
    local attached = false
    local textShown = false

    -- 1. Fase de Coleta (Pickup)
    while VPL.CurrentJob() and not attached do
        local ped = cache.ped
        local pCoords = GetEntityCoords(ped)
        local dist = #(pCoords - pickupCoords)

        if dist > 25.0 then
            Wait(1000)
        elseif dist > 8.0 then
            Wait(250)
        else
            Wait(0)
            local veh = VPL.InForkVehicle()
            if veh then
                VPL.DrawForkZone(pickupCoords)
                local tip = VPL.ForkTip(veh)
                if #(tip - pickupCoords) <= Config.Fork.alignDistance then
                    if not textShown then
                        VPL.UI.ShowText(locale('fork_grab'), 'fas fa-truck-ramp-box', 'E')
                        textShown = true
                    end
                    if IsControlJustReleased(0, Config.Fork.grabKey) then
                        VPL.ForkAttach(veh, load)
                        attached = true
                        VPL.UI.HideText()
                        textShown = false
                        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    end
                elseif textShown then
                    VPL.UI.HideText()
                    textShown = false
                end
            elseif textShown then
                VPL.UI.HideText()
                textShown = false
            end
        end
    end

    -- 2. Fase de Descarregamento (Drop)
    while VPL.CurrentJob() and attached do
        local ped = cache.ped
        local pCoords = GetEntityCoords(ped)
        local dist = #(pCoords - drop.coords)

        if dist > 25.0 then
            Wait(1000)
        elseif dist > 8.0 then
            Wait(250)
        else
            Wait(0)
            local veh = VPL.InForkVehicle()
            if veh then
                VPL.DrawForkZone(drop.coords)
                local tip = VPL.ForkTip(veh)
                local aligned = #(tip - drop.coords) <= drop.radius
                    and VPL.HeadingDiff(GetEntityHeading(veh), drop.heading) <= Config.Fork.alignHeading

                if aligned then
                    if not textShown then
                        VPL.UI.ShowText(locale('fork_drop'), 'fas fa-check', 'E')
                        textShown = true
                    end
                    if IsControlJustReleased(0, Config.Fork.grabKey) then
                        VPL.ForkPlace(load, drop.coords, drop.heading)
                        VPL.UI.HideText()
                        textShown = false
                        PlaySoundFrontend(-1, 'Object_Dropped_Remote', 'GTAO_FM_Events_Soundset', true)
                        if onDropped then onDropped() end
                        return true
                    end
                elseif textShown then
                    VPL.UI.HideText()
                    textShown = false
                end
            elseif textShown then
                VPL.UI.HideText()
                textShown = false
            end
        end
    end

    if textShown then
        VPL.UI.HideText()
    end
    if DoesEntityExist(load) then
        DetachEntity(load, true, true)
        if DoesEntityExist(load) then DeleteEntity(load) end
    end
    return false
end
