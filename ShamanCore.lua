-- ShamanCore v0.4.15
-- Press-driven shaman rotation, buff, and emergency-heal helper
-- for Turtle WoW / Vanilla 1.12.

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local VERSION = "0.4.15"
local PRIORITY_LOOKAHEAD = 0.8
local ICON_PATH = "Interface\\Icons\\"
local DEFAULT_ICON = "Spell_Nature_Lightning"
local WAIT_ICON = "INV_Misc_PocketWatch_01"
local ACCENT = "|cff0070de"

local ATTACK_SPELLS = {
    ["Lightning Bolt"] = true, ["Chain Lightning"] = true,
    ["Earth Shock"] = true, ["Flame Shock"] = true, ["Frost Shock"] = true,
    ["Stormstrike"] = true, ["Lava Burst"] = true,
    ["Lightning Strike"] = true, ["Molten Blast"] = true,
    ["Totemic Slam"] = true
}

local HEAL_SPELLS = {
    ["Healing Wave"] = true, ["Lesser Healing Wave"] = true,
    ["Chain Heal"] = true
}

local BUFF_SPELLS = {
    ["Lightning Shield"] = true, ["Water Shield"] = true,
    ["Earth Shield"] = true,
    ["Rockbiter Weapon"] = true, ["Flametongue Weapon"] = true,
    ["Frostbrand Weapon"] = true, ["Windfury Weapon"] = true
}

local WEAPON_BUFFS = {
    ["Rockbiter Weapon"] = true, ["Flametongue Weapon"] = true,
    ["Frostbrand Weapon"] = true, ["Windfury Weapon"] = true
}

local spellBookIndex = {}
local rotationSpells = { "None" }
local rotationMenuGroups = {}
local buffSpells = { "None" }
local healSpells = { "None" }
local menuFrame
local minimapButton
local rotationMacroIcon
local buffMacroIcon
local updateElapsed = 0
local lastMacroIcons = {}
local recentlyCastRotationSpells = {}
local lastRotationAttempt
local lockedRotationPreview
local lockedRotationPreviewUntil = 0

local DEFAULTS = {
    Rotation1 = "Flame Shock",
    Rotation2 = "Earth Shock",
    Rotation3 = "Stormstrike",
    Rotation4 = "Chain Lightning",
    Rotation5 = "Lightning Bolt",
    Buff1 = "Lightning Shield",
    Buff2 = "Windfury Weapon",
    Buff3 = "None", Buff4 = "None", Buff5 = "None",
    Buff1Combat = false, Buff2Combat = false, Buff3Combat = false,
    Buff4Combat = false, Buff5Combat = false,
    HealSpell = "Lesser Healing Wave",
    HealThreshold = 35,
    AutoHeal = true,
    AutoBuff = true,
    SmartTarget = true,
    MinimapPos = 120,
    Debug = false
}

local function Debug(message)
    if ShamanCore_Config and ShamanCore_Config.Debug then
        DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "[ShamanCore]|r " .. tostring(message))
    end
end

local function CopyDefaults()
    if type(ShamanCore_Config) ~= "table" then ShamanCore_Config = {} end
    local key, value
    for key, value in pairs(DEFAULTS) do
        if ShamanCore_Config[key] == nil then ShamanCore_Config[key] = value end
    end
    -- Rotation slot 6 was retired in v0.2.4.
    ShamanCore_Config.Rotation6 = nil
    -- Totem management was retired in v0.3.0.
    ShamanCore_Config.EarthTotem = nil
    ShamanCore_Config.FireTotem = nil
    ShamanCore_Config.WaterTotem = nil
    ShamanCore_Config.AirTotem = nil
    ShamanCore_Config.TotemRefresh = nil
    ShamanCore_Config.AutoTotems = nil
    -- Migrate the former Water Shield-only combat toggle to its configured
    -- buff slot, then retire the old setting.
    if ShamanCore_Config.CombatWaterShield then
        local i
        for i = 1, 5 do
            if ShamanCore_Config["Buff" .. i] == "Water Shield" then
                ShamanCore_Config["Buff" .. i .. "Combat"] = true
                break
            end
        end
    end
    ShamanCore_Config.CombatWaterShield = nil
end

local function TextureName(texture)
    if not texture then return nil end
    local _, _, name = string.find(texture, "([^\\/]+)$")
    return name or texture
end

local function GetSpellIndex(spellName)
    if not spellName or spellName == "None" then return nil end
    return spellBookIndex[spellName]
end

local function GetSpellIcon(spellName)
    local index = GetSpellIndex(spellName)
    if index then return TextureName(GetSpellTexture(index, BOOKTYPE_SPELL)) end
    return DEFAULT_ICON
end

local function AddUnique(list, seen, spellName)
    if not seen[spellName] then
        seen[spellName] = true
        table.insert(list, spellName)
    end
end

local function SortSpellLists()
    table.sort(rotationSpells, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
    table.sort(buffSpells, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
    table.sort(healSpells, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
end

local function RefreshSpellBook()
    spellBookIndex = {}
    rotationSpells = { "None" }
    rotationMenuGroups = {}
    buffSpells = { "None" }
    healSpells = { "None" }
    local rotationSeen, buffSeen, healSeen = {}, {}, {}
    local groupedSpells = {}
    local groupOrder = {}
    local function AddSpell(spellIndex, groupName)
        local spellName = GetSpellName(spellIndex, BOOKTYPE_SPELL)
        if not spellName then return end
        local passiveValue = IsPassiveSpell
            and IsPassiveSpell(spellIndex, BOOKTYPE_SPELL)
        local passive = passiveValue and passiveValue ~= 0
        if not passive then
            -- Iteration is rank-ascending, so this retains the highest rank.
            spellBookIndex[spellName] = spellIndex
            -- Rotation contains learned offensive abilities only. Buffs,
            -- weapon imbues, heals, and totems are excluded.
            if ATTACK_SPELLS[spellName] and not rotationSeen[spellName] then
                AddUnique(rotationSpells, rotationSeen, spellName)
                groupName = groupName or "Shaman"
                if not groupedSpells[groupName] then
                    groupedSpells[groupName] = {}
                    table.insert(groupOrder, groupName)
                end
                table.insert(groupedSpells[groupName], spellName)
            end
            if HEAL_SPELLS[spellName] then
                AddUnique(healSpells, healSeen, spellName)
            end
            if BUFF_SPELLS[spellName] then
                AddUnique(buffSpells, buffSeen, spellName)
            end
        end
    end

    local tabCount = GetNumSpellTabs and GetNumSpellTabs()
    local i
    if tabCount and tabCount > 1 and GetSpellTabInfo then
        local tab
        for tab = 2, tabCount do
            local tabName, _, offset, spellCount = GetSpellTabInfo(tab)
            tabName = tabName or ("Shaman " .. tab)
            if offset and spellCount then
                for i = offset + 1, offset + spellCount do
                    AddSpell(i, tabName)
                end
            end
        end
    else
        -- Compatibility fallback: only admit recognized Shaman spells when
        -- the legacy client does not expose spellbook tabs.
        for i = 1, 300 do
            local spellName = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            if ATTACK_SPELLS[spellName] or HEAL_SPELLS[spellName]
                or BUFF_SPELLS[spellName] then
                AddSpell(i, "Shaman")
            end
        end
    end
    SortSpellLists()

    -- Remove learned non-attack spells saved by versions that exposed every
    -- class ability in Rotation. Preserve unlearned choices for later ranks.
    for i = 1, 5 do
        local key = "Rotation" .. i
        local selected = ShamanCore_Config and ShamanCore_Config[key]
        if selected and selected ~= "None" and spellBookIndex[selected]
            and not rotationSeen[selected] then
            ShamanCore_Config[key] = "None"
        end
    end

    -- Vanilla's UIDropDownMenu has a small global button pool. Keep every
    -- submenu comfortably below that limit, even on custom Turtle spellbooks.
    local _, groupName
    local groupNumber = 0
    for _, groupName in ipairs(groupOrder) do
        local spells = groupedSpells[groupName]
        table.sort(spells)
        local first = 1
        while first <= table.getn(spells) do
            groupNumber = groupNumber + 1
            local last = math.min(first + 23, table.getn(spells))
            local label = groupName
            if table.getn(spells) > 24 then
                label = groupName .. " (" .. first .. "-" .. last .. ")"
            end
            local group = {
                key = "SHC_ROTATION_GROUP_" .. groupNumber,
                label = label,
                spells = {}
            }
            for i = first, last do table.insert(group.spells, spells[i]) end
            table.insert(rotationMenuGroups, group)
            first = last + 1
        end
    end
end

local function IsSpellReady(spellName)
    local index = GetSpellIndex(spellName)
    if not index then return false end
    local start, duration, enabled = GetSpellCooldown(index, BOOKTYPE_SPELL)
    if enabled == 0 then return false end
    if not start or not duration or start == 0 or duration == 0 then return true end
    -- Turtle WoW's Vanilla client does not expose IsUsableSpell. As in the
    -- other class cores, use the spellbook cooldown and ignore the shared GCD.
    return duration <= 1.5
end

local function UnitHasAuraTexture(unit, spellName, harmful)
    local index = GetSpellIndex(spellName)
    if not index then return false end
    local wanted = TextureName(GetSpellTexture(index, BOOKTYPE_SPELL))
    if not wanted then return false end
    wanted = string.lower(wanted)
    local i
    for i = 1, 32 do
        local texture
        if harmful then texture = UnitDebuff(unit, i) else texture = UnitBuff(unit, i) end
        if not texture then break end
        local current = TextureName(texture)
        if current and string.lower(current) == wanted then return true end
    end
    return false
end

local function PlayerHasConfiguredBuff(spellName)
    if WEAPON_BUFFS[spellName] then
        -- Weapon imbues are temporary enchants, not UnitBuff entries.
        local hasMainHandEnchant = GetWeaponEnchantInfo()
        return hasMainHandEnchant and true or false
    end
    return UnitHasAuraTexture("player", spellName, false)
end

local function HasLivingEnemy()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
end

local function AcquireTarget()
    if HasLivingEnemy() then return true end
    if ShamanCore_Config.SmartTarget then
        TargetNearestEnemy()
    end
    return HasLivingEnemy()
end

local function PlayerHealthPercent()
    local maximum = UnitHealthMax("player")
    if not maximum or maximum <= 0 then return 100 end
    return (UnitHealth("player") / maximum) * 100
end

local function GetRestedString()
    local restedXP = GetXPExhaustion() or 0
    local maximumXP = UnitXPMax("player")
    if not maximumXP or maximumXP <= 0 then return "0%" end
    local percent = math.floor(100 * restedXP / maximumXP)
    if percent >= 112 then return "MAX" end
    return percent .. "%"
end

local function CastSelf(spellName)
    if not IsSpellReady(spellName) then return false end
    Debug("Casting " .. spellName .. " on self")
    CastSpellByName(spellName, true)
    return true
end

local function GetNextMissingBuff(readyOnly)
    local i
    for i = 1, 5 do
        local spellName = ShamanCore_Config["Buff" .. i]
        if spellName and spellName ~= "None" and GetSpellIndex(spellName)
            and not PlayerHasConfiguredBuff(spellName)
            and (not readyOnly or IsSpellReady(spellName)) then
            return spellName
        end
    end
    return nil
end

local function RotationSpellEffectIsActive(spellName)
    return (spellName == "Earth Shock" or spellName == "Flame Shock"
        or spellName == "Frost Shock")
        and UnitHasAuraTexture("target", spellName, true)
end

local function GetRotationSpellRemaining(spellName)
    if not spellName or spellName == "None" or not GetSpellIndex(spellName) then
        return nil
    end
    if RotationSpellEffectIsActive(spellName) then return nil end

    local now = GetTime()
    local manualRemaining = 0
    local blockedUntil = recentlyCastRotationSpells[spellName]
    if blockedUntil then
        if spellName == "Earth Shock" or spellName == "Flame Shock"
            or spellName == "Frost Shock" then
            -- Once the GCD has passed, Turtle exposes the real shared Shock
            -- cooldown. Replace our six-second fallback with that exact,
            -- talent-adjusted expiry instead of letting the icon bounce back.
            local index = GetSpellIndex(spellName)
            if index then
                local start, duration = GetSpellCooldown(
                    index, BOOKTYPE_SPELL)
                if start and duration and duration > 1.5 then
                    blockedUntil = start + duration
                    recentlyCastRotationSpells[spellName] = blockedUntil
                end
            end
        end
        if now < blockedUntil then
            manualRemaining = blockedUntil - now
        else
            recentlyCastRotationSpells[spellName] = nil
        end
    end

    local index = GetSpellIndex(spellName)
    local start, duration, enabled = GetSpellCooldown(
        index, BOOKTYPE_SPELL)
    if enabled == 0 then return 999999 end

    local cooldownRemaining = 0
    -- Durations at or below 1.5 seconds are the shared GCD. Treat the spell
    -- as the next usable action while still dimming its icon separately.
    if start and duration and duration > 1.5 then
        cooldownRemaining = math.max(0, start + duration - now)
    end
    return math.max(manualRemaining, cooldownRemaining)
end

local function GetNextRotationSpell(readyOnly, includeSoonest)
    local first
    local soonest
    local soonestRemaining = 999999
    local i
    for i = 1, 5 do
        local spellName = ShamanCore_Config["Rotation" .. i]
        local remaining = GetRotationSpellRemaining(spellName)
        if remaining ~= nil then
            if not first then first = spellName end
            if readyOnly then
                -- Slot order wins when an ability is ready now or inside the
                -- short lookahead window.
                if remaining <= PRIORITY_LOOKAHEAD then return spellName end
                if remaining < soonestRemaining then
                    soonest = spellName
                    soonestRemaining = remaining
                end
            end
        end
    end
    if not readyOnly then return first end
    if includeSoonest then return soonest end
    return nil
end

local function RotationContainsSpell(spellName)
    local i
    for i = 1, 5 do
        if ShamanCore_Config["Rotation" .. i] == spellName then return true end
    end
    return false
end

local function GetRotationPreviewSpell()
    local now = GetTime()
    if lockedRotationPreview
        and now < lockedRotationPreviewUntil
        and RotationContainsSpell(lockedRotationPreview)
        and GetRotationSpellRemaining(lockedRotationPreview) ~= nil then
        return lockedRotationPreview
    end

    lockedRotationPreview = nil
    lockedRotationPreviewUntil = 0
    local spellName = GetNextRotationSpell(true, true)
        or GetNextRotationSpell(false)
    if spellName then
        local remaining = GetRotationSpellRemaining(spellName) or 0
        lockedRotationPreview = spellName
        if remaining > 0 and remaining <= PRIORITY_LOOKAHEAD then
            lockedRotationPreviewUntil =
                now + math.max(0.35, remaining + 0.15)
        else
            -- Bridge the Vanilla GCD-to-real-cooldown reporting transition.
            lockedRotationPreviewUntil = now + 0.75
        end
    end
    return spellName
end

local function TryEmergencyHeal()
    if not ShamanCore_Config.AutoHeal then return false end
    if PlayerHealthPercent() > (ShamanCore_Config.HealThreshold or 35) then return false end
    local spellName = ShamanCore_Config.HealSpell
    return CastSelf(spellName)
end

local function ShouldRunAutomaticBuffs()
    local selfOrNoTarget = not UnitExists("target")
        or UnitIsUnit("target", "player")
    return ShamanCore_Config.AutoBuff
        and not UnitAffectingCombat("player")
        and selfOrNoTarget
end

local function GetNextCombatBuff(readyOnly)
    if not UnitAffectingCombat("player") then return nil end
    local i
    for i = 1, 5 do
        local spellName = ShamanCore_Config["Buff" .. i]
        if ShamanCore_Config["Buff" .. i .. "Combat"]
            and spellName and spellName ~= "None"
            and GetSpellIndex(spellName)
            and not PlayerHasConfiguredBuff(spellName)
            and (not readyOnly or IsSpellReady(spellName)) then
            return spellName
        end
    end
    return nil
end

function ShamanCore_Buff()
    local spellName = GetNextMissingBuff(true)
    if spellName then CastSelf(spellName) end
end

function ShamanCore_Rotate()
    if TryEmergencyHeal() then return end

    local combatBuff = GetNextCombatBuff(true)
    if combatBuff and CastSelf(combatBuff) then return end

    -- Only run the automatic buff cycle while safely out of combat with no
    -- target or the player targeted. An existing enemy target always goes
    -- directly to the offensive rotation.
    if ShouldRunAutomaticBuffs() then
        local buff = GetNextMissingBuff(true)
        if buff and CastSelf(buff) then return end
    end

    if not AcquireTarget() then return end

    local spellName = GetNextRotationSpell(true, false)
    if spellName then
        Debug("Casting " .. spellName)
        local blockedUntil = GetTime() + 1.7
        recentlyCastRotationSpells[spellName] = blockedUntil
        -- All Shocks share a cooldown, but the Vanilla client initially
        -- reports only their global cooldown. Block the family until the real
        -- shared cooldown becomes visible through GetSpellCooldown.
        if spellName == "Earth Shock" or spellName == "Flame Shock"
            or spellName == "Frost Shock" then
            blockedUntil = GetTime() + 6
            recentlyCastRotationSpells["Earth Shock"] = blockedUntil
            recentlyCastRotationSpells["Flame Shock"] = blockedUntil
            recentlyCastRotationSpells["Frost Shock"] = blockedUntil
        end
        lastRotationAttempt = spellName
        lockedRotationPreview = nil
        lockedRotationPreviewUntil = 0
        CastSpellByName(spellName)
        -- Force the next OnUpdate pass to repaint the macro immediately.
        updateElapsed = 0.5
    end
end

local function FindAnyMacro(name)
    local generalCount, characterCount = GetNumMacros()
    local i
    for i = 1, generalCount do
        if GetMacroInfo(i) == name then return i end
    end
    local characterStart = (MAX_ACCOUNT_MACROS or 18) + 1
    for i = characterStart, characterStart + characterCount - 1 do
        if GetMacroInfo(i) == name then return i end
    end
    return nil
end

local function FindCharacterMacro(name)
    local _, characterCount = GetNumMacros()
    local characterStart = (MAX_ACCOUNT_MACROS or 18) + 1
    local i
    for i = characterStart, characterStart + characterCount - 1 do
        if GetMacroInfo(i) == name then return i end
    end
    return nil
end

local function CreateCharacterMacro(name, icon, body)
    local existing = FindCharacterMacro(name)
    if not existing then existing = FindAnyMacro(name) end
    if existing then
        EditMacro(existing, name, icon, body, nil, 1)
        return FindCharacterMacro(name) or FindAnyMacro(name)
    end
    local _, characterCount = GetNumMacros()
    if characterCount >= 18 then
        DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "[ShamanCore]|r Character macro slots are full.")
        return nil
    end
    return CreateMacro(name, icon, body, nil, 1)
end

local function UpdateMacroIcon(name, spellName, fallback)
    local icon = spellName and GetSpellIcon(spellName) or fallback
    if not icon then icon = fallback end
    if lastMacroIcons[name] == icon then return end

    -- Update every matching macro. Older ShamanCore builds could create
    -- duplicates because they searched the wrong Vanilla macro index range.
    local generalCount, characterCount = GetNumMacros()
    local characterStart = (MAX_ACCOUNT_MACROS or 18) + 1
    local found = false
    local function UpdateAt(index)
        local macroName, _, body = GetMacroInfo(index)
        if macroName == name then
            EditMacro(index, macroName, icon, body, nil, nil)
            found = true
        end
    end
    local i
    for i = 1, generalCount do UpdateAt(i) end
    for i = characterStart, characterStart + characterCount - 1 do
        UpdateAt(i)
    end
    if found then
        lastMacroIcons[name] = icon
    end
end

local function GetActionButtons()
    if AllButtons then return AllButtons end
    if AllActionButtons then return AllActionButtons end
    local buttons = {}
    local prefixes = {
        "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton"
    }
    local _, prefix
    for _, prefix in ipairs(prefixes) do
        local i
        for i = 1, 12 do
            local button = getglobal(prefix .. i)
            if button then table.insert(buttons, button) end
        end
    end
    return buttons
end

local function GetSpellReadyState(spellName)
    local index = GetSpellIndex(spellName)
    if not index then return false, 0, 0, 0 end
    local start, duration, enabled = GetSpellCooldown(index, BOOKTYPE_SPELL)
    start = start or 0
    duration = duration or 0
    enabled = enabled or 0
    local ready = enabled ~= 0
        and (start == 0 or duration == 0
            or start + duration <= GetTime())
    return ready, start, duration, enabled
end

local function SuppressCooldownText(cooldown)
    if not cooldown then return end
    cooldown.noCooldownCount = true
    cooldown.noOCC = true
    cooldown.pfCooldownStyleText = 0
    if cooldown.cooldowntext then cooldown.cooldowntext:Hide() end
    if cooldown.pfCooldownText then cooldown.pfCooldownText:Hide() end
end

local function UpdateRotationReadyState(spellName)
    local ready, start, duration, enabled = GetSpellReadyState(spellName)
    local previewColor = ready and 1 or 0.42
    local hasTimedSweep = not ready and start > 0 and duration > 0

    if rotationMacroIcon then
        rotationMacroIcon:SetVertexColor(
            previewColor, previewColor, previewColor)
    end

    local _, button
    for _, button in ipairs(GetActionButtons()) do
        local actionSlot = ActionButton_GetPagedID(button)
        if actionSlot and GetActionText(actionSlot) == "Shaman Rot" then
            local icon = button.icon or button.iconTexture
                or getglobal(button:GetName() .. "Icon")
            -- Keep the action icon at full color. The native radial sweep
            -- provides timed dimming; the shade below is only a fallback.
            if icon then icon:SetVertexColor(1, 1, 1) end
            SuppressCooldownText(
                button.cd or getglobal(button:GetName() .. "Cooldown"))

            -- Bartender can repaint macro vertex colors. A separate shade
            -- keeps the unavailable state visible without a cooldown sweep.
            if not button.ShamanCoreReadyShade and icon then
                local shade = button:CreateTexture(nil, "OVERLAY")
                shade:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
                shade:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
                shade:SetTexture(0, 0, 0)
                shade:SetAlpha(0.55)
                shade:Hide()
                button.ShamanCoreReadyShade = shade
            end

            if not button.ShamanCoreCooldownSweep and icon then
                local sweep = CreateFrame(
                    "Model", nil, button, "CooldownFrameTemplate")
                sweep:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
                sweep:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
                sweep:SetFrameLevel(button:GetFrameLevel() + 3)
                -- Common cooldown-number addons honor one of these flags.
                -- ShamanCore itself never creates numeric countdown text.
                SuppressCooldownText(sweep)
                button.ShamanCoreCooldownSweep = sweep
            end

            if button.ShamanCoreReadyShade then
                if ready or hasTimedSweep then
                    button.ShamanCoreReadyShade:Hide()
                else
                    button.ShamanCoreReadyShade:Show()
                end
            end
            if button.ShamanCoreCooldownSweep then
                local sweep = button.ShamanCoreCooldownSweep
                SuppressCooldownText(sweep)
                if not hasTimedSweep then
                    if sweep.shamanCoreTimerActive then
                        CooldownFrame_SetTimer(sweep, 0, 0, 0)
                        sweep.shamanCoreTimerActive = nil
                        sweep.shamanCoreStart = nil
                        sweep.shamanCoreDuration = nil
                        sweep.shamanCoreEnabled = nil
                    end
                else
                    if not sweep.shamanCoreTimerActive
                        or sweep.shamanCoreStart ~= start
                        or sweep.shamanCoreDuration ~= duration
                        or sweep.shamanCoreEnabled ~= enabled then
                        CooldownFrame_SetTimer(
                            sweep, start, duration, enabled)
                        sweep.shamanCoreTimerActive = true
                        sweep.shamanCoreStart = start
                        sweep.shamanCoreDuration = duration
                        sweep.shamanCoreEnabled = enabled
                    end
                end
                SuppressCooldownText(sweep)
            end
        end
    end
end

local function UpdateIcons()
    -- Keep the Rotation macro focused on offensive priority. Buffs and
    -- emergency healing may still be cast by ShamanCore_Rotate, but they do
    -- not replace the displayed rotation ability.
    local rotation = GetRotationPreviewSpell()
    local buff = GetNextMissingBuff(true)
    if rotationMacroIcon then
        rotationMacroIcon:SetTexture(ICON_PATH .. (rotation and GetSpellIcon(rotation) or WAIT_ICON))
    end
    if buffMacroIcon then
        buffMacroIcon:SetTexture(ICON_PATH .. (buff and GetSpellIcon(buff) or WAIT_ICON))
    end
    UpdateMacroIcon("Shaman Rot", rotation, WAIT_ICON)
    UpdateMacroIcon("Shaman Buff", buff, WAIT_ICON)
    UpdateRotationReadyState(rotation)
end

local function StyleButton(button)
    button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
end

local function AddLabel(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function MakeDropdown(parent, key, values, x, y, width)
    local name = "ShamanCoreDrop_" .. key
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(width or 145, dropdown)
    UIDropDownMenu_Initialize(dropdown, function()
        local _, value
        for _, value in ipairs(values()) do
            local capturedValue = value
            local info = {}
            info.text = capturedValue
            info.value = capturedValue
            info.checked = ShamanCore_Config[key] == capturedValue
            info.func = function()
                ShamanCore_Config[key] = capturedValue
                UIDropDownMenu_SetSelectedValue(dropdown, capturedValue)
                UIDropDownMenu_SetText(capturedValue, dropdown)
                UpdateIcons()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    local selected = ShamanCore_Config[key] or "None"
    UIDropDownMenu_SetSelectedValue(dropdown, selected)
    UIDropDownMenu_SetText(selected, dropdown)
    return dropdown
end

local function MakeRotationDropdown(parent, key, x, y, width)
    local name = "ShamanCoreDrop_" .. key
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(width or 145, dropdown)

    local function SelectSpell(spellName)
        ShamanCore_Config[key] = spellName
        UIDropDownMenu_SetSelectedValue(dropdown, spellName)
        UIDropDownMenu_SetText(spellName, dropdown)
        UpdateIcons()
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local level = UIDROPDOWNMENU_MENU_LEVEL or 1
        if level == 1 then
            local noneInfo = {}
            noneInfo.text = "None"
            noneInfo.value = "None"
            noneInfo.checked = ShamanCore_Config[key] == "None"
            noneInfo.func = function() SelectSpell("None") end
            UIDropDownMenu_AddButton(noneInfo, level)

            local _, group
            for _, group in ipairs(rotationMenuGroups) do
                local capturedKey = group.key
                local groupInfo = {}
                groupInfo.text = group.label
                groupInfo.value = capturedKey
                groupInfo.hasArrow = true
                groupInfo.notCheckable = true
                UIDropDownMenu_AddButton(groupInfo, level)
            end
        elseif level == 2 then
            local wantedGroup = UIDROPDOWNMENU_MENU_VALUE
            local _, group
            for _, group in ipairs(rotationMenuGroups) do
                if group.key == wantedGroup then
                    local _, spellName
                    for _, spellName in ipairs(group.spells) do
                        local capturedSpell = spellName
                        local spellInfo = {}
                        spellInfo.text = capturedSpell
                        spellInfo.value = capturedSpell
                        spellInfo.checked =
                            ShamanCore_Config[key] == capturedSpell
                        spellInfo.func = function()
                            SelectSpell(capturedSpell)
                        end
                        UIDropDownMenu_AddButton(spellInfo, level)
                    end
                    break
                end
            end
        end
    end)

    local selected = ShamanCore_Config[key] or "None"
    UIDropDownMenu_SetSelectedValue(dropdown, selected)
    UIDropDownMenu_SetText(selected, dropdown)
    return dropdown
end

local function MakeToggle(parent, labelText, key, x, y, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width or 150)
    button:SetHeight(28)
    button:SetPoint("TOPLEFT", x, y)
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)

    local label = button:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 9, 0)
    label:SetText(labelText)
    label:SetTextColor(0.88, 0.90, 0.94)

    local state = button:CreateFontString(
        nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("RIGHT", -9, 0)
    local function Refresh()
        if ShamanCore_Config[key] then
            state:SetText("ON")
            state:SetTextColor(0.20, 1.00, 0.35)
            button:SetBackdropColor(0.00, 0.20, 0.36, 0.94)
            button:SetBackdropBorderColor(0.12, 0.55, 0.85, 1.00)
        else
            state:SetText("OFF")
            state:SetTextColor(1.00, 0.28, 0.22)
            button:SetBackdropColor(0.04, 0.05, 0.07, 0.92)
            button:SetBackdropBorderColor(0.25, 0.28, 0.32, 1.00)
        end
    end
    button:SetScript("OnClick", function()
        ShamanCore_Config[key] = not ShamanCore_Config[key]
        Refresh()
    end)
    Refresh()
    return button
end

local function MakeSlider(parent, labelText, key, minimum, maximum, x, y)
    AddLabel(parent, labelText, x, y)
    local slider = CreateFrame("Slider", "ShamanCoreSlider_" .. key, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetWidth(260)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(1)
    slider:SetValue(ShamanCore_Config[key] or minimum)
    getglobal(slider:GetName() .. "Low"):SetText(minimum)
    getglobal(slider:GetName() .. "High"):SetText(maximum)
    getglobal(slider:GetName() .. "Text"):SetText(ShamanCore_Config[key] or minimum)
    slider:SetScript("OnValueChanged", function()
        local value = math.floor(this:GetValue() + 0.5)
        ShamanCore_Config[key] = value
        getglobal(this:GetName() .. "Text"):SetText(value)
    end)
    return slider
end

local function MakeMacroButton(parent, x, y, labelText, macroName, body, iconKind)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(50)
    button:SetHeight(50)
    button:SetPoint("TOPLEFT", x, y)
    StyleButton(button)
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(ICON_PATH .. DEFAULT_ICON)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        local spellName
        if iconKind == "rotation" then
            spellName = GetRotationPreviewSpell()
        elseif iconKind == "buff" then spellName = GetNextMissingBuff(false) end
        local macro = CreateCharacterMacro(macroName,
            spellName and GetSpellIcon(spellName) or DEFAULT_ICON, body)
        if macro then PickupMacro(macro) end
    end)
    AddLabel(parent, labelText, x - 3, y - 56, "GameFontNormalSmall")
    return icon
end

local function CreateMenu()
    if menuFrame then return end
    local frame = CreateFrame("Frame", "ShamanCoreMenuFrame", UIParent)
    menuFrame = frame
    frame:SetWidth(410)
    frame:SetHeight(490)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    frame:Hide()

    AddLabel(frame, "ShamanCore " .. VERSION, 22, -18, "GameFontNormalLarge")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local panels = {}
    local tabButtons = {}
    local tabs = { "Rotation", "Buffs", "Options", "Info" }
    local function ShowPanel(wanted)
        local name, panel
        for name, panel in pairs(panels) do
            if name == wanted then panel:Show() else panel:Hide() end
        end
        for name, button in pairs(tabButtons) do
            if name == wanted then
                button:SetBackdropColor(0.00, 0.32, 0.65, 0.95)
                button:SetBackdropBorderColor(0.20, 0.70, 1.00, 1.00)
                button.label:SetTextColor(1.00, 1.00, 1.00)
            else
                button:SetBackdropColor(0.04, 0.05, 0.07, 0.90)
                button:SetBackdropBorderColor(0.25, 0.28, 0.32, 1.00)
                button.label:SetTextColor(0.72, 0.76, 0.82)
            end
        end
    end
    local i, tabName
    for i, tabName in ipairs(tabs) do
        local button = CreateFrame("Button", nil, frame)
        button:SetWidth(88)
        button:SetHeight(28)
        button:SetPoint("TOPLEFT", 20 + ((i - 1) * 88), -48)
        button:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 9,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetPoint("TOPLEFT", 3, -3)
        highlight:SetPoint("BOTTOMRIGHT", -3, 3)
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 0)
        text:SetText(tabName)
        button.label = text
        tabButtons[tabName] = button
        local captured = tabName
        button:SetScript("OnClick", function() ShowPanel(captured) end)

        local panel = CreateFrame("Frame", nil, frame)
        panel:SetWidth(374)
        panel:SetHeight(390)
        panel:SetPoint("TOPLEFT", 18, -82)
        panel:Hide()
        panels[tabName] = panel
    end

    local rotation = panels.Rotation
    AddLabel(rotation, "Priority (first ready spell wins)", 8, 0)
    AddLabel(rotation, "Learned offensive spells - General excluded",
        8, -18, "GameFontHighlightSmall")
    for i = 1, 5 do
        AddLabel(rotation, "Slot " .. i, 8, -48 - ((i - 1) * 48), "GameFontNormalSmall")
        MakeRotationDropdown(rotation, "Rotation" .. i,
            60, -36 - ((i - 1) * 48), 220)
    end

    local buffs = panels.Buffs
    AddLabel(buffs, "Self-buff priority", 8, 0)
    for i = 1, 5 do
        local slotY = -28 - ((i - 1) * 67)
        AddLabel(buffs, "Slot " .. i, 8, slotY, "GameFontNormalSmall")
        MakeDropdown(buffs, "Buff" .. i, function() return buffSpells end,
            60, slotY + 12, 220)

        local combatCheck = CreateFrame(
            "CheckButton", "ShamanCoreBuff" .. i .. "CombatCheck",
            buffs, "UICheckButtonTemplate")
        combatCheck:SetWidth(20)
        combatCheck:SetHeight(20)
        combatCheck:SetPoint("TOPLEFT", 60, slotY - 34)
        combatCheck:SetChecked(
            ShamanCore_Config["Buff" .. i .. "Combat"] and 1 or nil)
        local slot = i
        combatCheck:SetScript("OnClick", function()
            ShamanCore_Config["Buff" .. slot .. "Combat"] =
                this:GetChecked() and true or false
            UpdateIcons()
        end)

        local combatLabel = buffs:CreateFontString(
            nil, "OVERLAY", "GameFontNormalSmall")
        combatLabel:SetPoint("LEFT", combatCheck, "RIGHT", 3, 0)
        combatLabel:SetText("Upkeep during combat")
    end

    local options = panels.Options
    MakeToggle(options, "Smart Target", "SmartTarget", 8, 0, 165)
    MakeToggle(options, "Auto Buff", "AutoBuff", 190, 0, 165)
    MakeToggle(options, "Emergency Heal", "AutoHeal", 8, -36, 165)
    AddLabel(options, "Emergency heal spell", 8, -86)
    MakeDropdown(options, "HealSpell", function() return healSpells end, 0, -98, 220)
    MakeSlider(options, "Emergency heal below (%)", "HealThreshold", 1, 95, 8, -160)
    MakeToggle(options, "Debug Messages", "Debug", 8, -235, 165)

    local info = panels.Info
    AddLabel(info, "Drag these buttons to an action bar:", 8, 0)
    rotationMacroIcon = MakeMacroButton(info, 18, -35, "Rotation",
        "Shaman Rot", "/script ShamanCore_Rotate()", "rotation")
    buffMacroIcon = MakeMacroButton(info, 100, -35, "Buffs",
        "Shaman Buff", "/script ShamanCore_Buff()", "buff")
    AddLabel(info,
        "Rotation checks emergency healing first. Out of combat with\n" ..
        "no target or yourself targeted, it applies missing buffs.\n" ..
        "An enemy target skips buffs and uses the five attack slots.\n" ..
        "Checked buff slots are also maintained during combat.\n\n" ..
        "Totems are intentionally left to your dedicated totem addon.\n\n" ..
        "Commands: /shc, /shc reset, /shc minimap",
        8, -125, "GameFontHighlightSmall")

    ShowPanel("Rotation")
    UpdateIcons()
end

local function GetMinimapButtonRadius()
    local minimapSize = Minimap:GetWidth() or 140
    return math.max(70, math.min(90, minimapSize / 2 + 8))
end

function ShamanCore_Minimap_UpdatePosition()
    if not ShamanCoreMinimapButton or not ShamanCore_Config
        or not ShamanCore_Config.MinimapPos then return end
    local angle = math.rad(ShamanCore_Config.MinimapPos)
    local radius = GetMinimapButtonRadius()
    ShamanCoreMinimapButton:ClearAllPoints()
    ShamanCoreMinimapButton:SetPoint("CENTER", "Minimap", "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

function ShamanCore_Minimap_OnUpdate()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
    x = x / scale
    y = y / scale
    local centerX = left + Minimap:GetWidth() / 2
    local centerY = bottom + Minimap:GetHeight() / 2
    local deltaX, deltaY = x - centerX, y - centerY
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local maxDistance = GetMinimapButtonRadius()
    if distance > maxDistance then
        local distanceScale = maxDistance / distance
        deltaX = deltaX * distanceScale
        deltaY = deltaY * distanceScale
    end
    ShamanCore_Config.MinimapPos = math.deg(math.atan2(deltaY, deltaX))
    ShamanCore_Minimap_UpdatePosition()
end

local function CreateMinimapButton()
    if ShamanCoreMinimapButton then
        minimapButton = ShamanCoreMinimapButton
        ShamanCoreMinimapButton:Show()
        ShamanCore_Minimap_UpdatePosition()
        return
    end

    ShamanCoreMinimapButton =
        CreateFrame("Button", "ShamanCoreMinimapButton", Minimap)
    minimapButton = ShamanCoreMinimapButton
    ShamanCoreMinimapButton:SetWidth(32)
    ShamanCoreMinimapButton:SetHeight(32)
    ShamanCoreMinimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    ShamanCoreMinimapButton:EnableMouse(true)
    ShamanCoreMinimapButton:SetMovable(true)
    ShamanCoreMinimapButton:RegisterForDrag("LeftButton")

    local icon = ShamanCoreMinimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_PATH .. DEFAULT_ICON)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = ShamanCoreMinimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(52)
    border:SetHeight(52)
    border:SetPoint("TOPLEFT", 0, 0)

    ShamanCoreMinimapButton:SetScript("OnClick", function()
        CreateMenu()
        if menuFrame:IsShown() then menuFrame:Hide() else menuFrame:Show() end
    end)
    ShamanCoreMinimapButton:SetScript("OnDragStart", function()
        this:StartMoving()
        this:SetScript("OnUpdate", ShamanCore_Minimap_OnUpdate)
    end)
    ShamanCoreMinimapButton:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        this:SetScript("OnUpdate", nil)
    end)
    ShamanCoreMinimapButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine(ACCENT .. "ShamanCore v" .. VERSION .. "|r")
        GameTooltip:AddLine(
            "Currently |cff00ff00" .. GetRestedString() .. "|r Rested",
            1, 1, 1)
        GameTooltip:AddLine("Left-Click to toggle menu", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    ShamanCoreMinimapButton:SetScript(
        "OnLeave", function() GameTooltip:Hide() end)

    local angle = math.rad(ShamanCore_Config.MinimapPos or 120)
    ShamanCoreMinimapButton:SetPoint("CENTER", "Minimap", "CENTER",
        math.cos(angle) * 80, math.sin(angle) * 80)
    ShamanCoreMinimapButton:Show()
end

local function HandleSlash(message)
    local command = string.lower(message or "")
    if command == "reset" then
        ShamanCore_Config = {}
        CopyDefaults()
        DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "[ShamanCore]|r Settings reset. Reloading UI.")
        ReloadUI()
    elseif command == "minimap" then
        ShamanCore_Config.MinimapPos = DEFAULTS.MinimapPos
        CreateMinimapButton()
        ShamanCoreMinimapButton:Show()
        ShamanCore_Minimap_UpdatePosition()
        DEFAULT_CHAT_FRAME:AddMessage(
            ACCENT .. "[ShamanCore]|r Minimap button restored.")
    else
        CreateMenu()
        if menuFrame:IsShown() then menuFrame:Hide() else menuFrame:Show() end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("SPELLCAST_FAILED")
eventFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("SPELLCAST_STOP")
eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        CopyDefaults()
        RefreshSpellBook()
        SLASH_SHAMANCORE1 = "/shc"
        SLASH_SHAMANCORE2 = "/shamancore"
        SlashCmdList.SHAMANCORE = HandleSlash
    elseif event == "PLAYER_LOGIN" then
        RefreshSpellBook()
        CreateMinimapButton()
        DEFAULT_CHAT_FRAME:AddMessage(
            ACCENT .. "[ShamanCore]|r v" .. VERSION .. " loaded. Type /shc.")
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        RefreshSpellBook()
        UpdateIcons()
    elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        if lastRotationAttempt then
            recentlyCastRotationSpells[lastRotationAttempt] = nil
            if lastRotationAttempt == "Earth Shock"
                or lastRotationAttempt == "Flame Shock"
                or lastRotationAttempt == "Frost Shock" then
                recentlyCastRotationSpells["Earth Shock"] = nil
                recentlyCastRotationSpells["Flame Shock"] = nil
                recentlyCastRotationSpells["Frost Shock"] = nil
            end
            lastRotationAttempt = nil
            updateElapsed = 0.5
        end
    elseif event == "SPELLCAST_STOP" then
        -- Keep the short preview block, but no longer associate later,
        -- unrelated spell failures with this successful rotation cast.
        lastRotationAttempt = nil
    end
end)

eventFrame:SetScript("OnUpdate", function()
    updateElapsed = updateElapsed + arg1
    if updateElapsed >= 0.5 and ShamanCore_Config then
        updateElapsed = 0
        UpdateIcons()
    end
end)
