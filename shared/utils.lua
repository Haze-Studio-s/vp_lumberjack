-- vp_lumberjack — Funções puras compartilhadas (client + server)
-- Namespace único p/ não poluir o global.

VPL = VPL or {}

lib.locale()  -- convar setr ox:locale pt; fallback en

--- Inteiro aleatório [min, max].
function VPL.RandInt(min, max)
    if max < min then min, max = max, min end
    return math.random(min, max)
end

--- Formata dinheiro
function VPL.Money(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return '$' .. out
end

--- Menor diferença angular (0..180) entre dois headings.
function VPL.HeadingDiff(a, b)
    local d = math.abs((a - b) % 360)
    if d > 180 then d = 360 - d end
    return d
end

--- Resolve o asset apropriado (Custom Stream vs Native Fallback)
--- @param category 'vehicles'|'props'
--- @param key string
--- @return string modelName
function VPL.GetAsset(category, key)
    if not Config or not Config.Assets then return nil end
    if Config.UseCustomStreams and Config.Assets.custom and Config.Assets.custom[category] then
        local customModel = Config.Assets.custom[category][key]
        if customModel then
            if IsModelInCdimage then
                if IsModelInCdimage(GetHashKey(customModel)) then
                    return customModel
                end
            else
                return customModel
            end
        end
    end
    if Config.Assets.native and Config.Assets.native[category] then
        return Config.Assets.native[category][key]
    end
    return nil
end
