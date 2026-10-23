-- Experimental standalone add-on. See README.md for known session-state issues.

local BankSwitch = {}
ParagonBankSwitchBeta.BankSwitch = BankSwitch

local T = ParagonBankSwitchBeta.Text
local EVENT_NAMESPACE = ParagonBankSwitchBeta.name
local OPENING_UPDATE_NAMESPACE = EVENT_NAMESPACE .. "Opening"
local RELOAD_UPDATE_NAMESPACE = EVENT_NAMESPACE .. "Reload"
local CLOSING_UPDATE_NAMESPACE = EVENT_NAMESPACE .. "Closing"
local SERVICE_ACTION_LAYER = "SI_KEYBINDINGS_LAYER_PARAGON_BANK_SWITCH_BETA"
local serviceOrder = { "bank", "guildBank" }
-- Bindings belong to this add-on and preserve later user assignments.
local services = {
    bank = { indexKey = "bankIndex", interactionType = INTERACTION_BANK, event = EVENT_OPEN_BANK,
        textKey = "INV_BANK_SWITCH_PERSONAL", action = "PARAGON_BANK_SWITCH_BETA_PERSONAL", key = KEY_1 },
    guildBank = { indexKey = "guildBankIndex", interactionType = INTERACTION_GUILDBANK, event = EVENT_OPEN_GUILD_BANK,
        textKey = "INV_BANK_SWITCH_GUILD", action = "PARAGON_BANK_SWITCH_BETA_GUILD_BANK", key = KEY_2 },
}

local function IsGuildBankBusy()
    local guildBank = ParagonUI and ParagonUI.GuildBank
    return guildBank and guildBank:WorkInProgress() or false
end

local function IsServiceOption(sceneName, optionType)
    if sceneName == "bank" then return optionType == CHATTER_START_BANK end
    if sceneName == "guildBank" then
        return optionType == CHATTER_START_GUILDBANK or optionType == CHATTER_OPEN_GUILDBANK
    end
    return false
end

function BankSwitch:Trace(event)
    local request = self.pending or self.closeRequest or self.reloadRequest
    if not request then return end
    local function SceneState(name)
        return tostring(SCENE_MANAGER:GetScene(name):GetState())
    end
    local interactionType = GetInteractionType()
    local interactionName = interactionType == INTERACTION_BANK and "bank"
        or interactionType == INTERACTION_GUILDBANK and "guild"
        or interactionType == INTERACTION_CONVERSATION and "conversation" or tostring(interactionType)
    local line = string.format("%dms %s phase=%s type=%s busy=%s bank=%s/%s guild=%s/%s dialogue=%s options=%s/%s npc=%s",
        GetFrameTimeMilliseconds() - request.startedAt, event, request.phase,
        interactionName, tostring(IsInteractionPending()),
        tostring(IsBankOpen()), SceneState("bank"), tostring(IsGuildBankOpen()), SceneState("guildBank"),
        SceneState(self.dialogueSceneName),
        tostring(self.bankIndex), tostring(self.guildBankIndex),
        tostring(GetUnitName("interact") == request.bankerName))
    -- Only the latest attempt is retained in memory, including its terminal state.
    if #request.trace == 60 then table.remove(request.trace, 1) end
    request.trace[#request.trace + 1] = line
end

function BankSwitch:PrintDebug()
    local trace = self.lastRequest and self.lastRequest.trace
    if not trace then
        d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_SWITCH_NO_TRACE"))
        return
    end
    for _, line in ipairs(trace) do
        d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_SWITCH_TRACE", line))
    end
end

function BankSwitch:CheckForStuckSessions(closeFailed)
    local bankOpen, guildOpen = IsBankOpen(), IsGuildBankOpen()
    if not bankOpen and not guildOpen then
        self.recoveryHintState = nil
        return
    end
    if self.pending or self.closeRequest or self.reloadRequest then return end
    -- An open flag during a live service is expected; warn after exit or failed cleanup.
    if not closeFailed and (IsInteractionPending() or GetInteractionType() ~= INTERACTION_NONE) then return end
    local recoveryState = bankOpen and (guildOpen and "both" or "bank") or "guild"
    if self.recoveryHintState == recoveryState then return end
    self.recoveryHintState = recoveryState
    local hints = {}
    if bankOpen then
        hints[#hints + 1] = T("INV_BANK_RECOVERY_PERSONAL", T("INV_BANK_DEBUG_CLOSE_BANK"))
    end
    if guildOpen then
        hints[#hints + 1] = T("INV_BANK_RECOVERY_GUILD")
    end
    d("|cFFCC66[PBS Beta]|r " .. table.concat(hints, " "))
end

function BankSwitch:PrintState()
    d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_DEBUG_STATE_FORMAT",
        tostring(IsBankOpen()), tostring(IsGuildBankOpen()), tostring(GetInteractionType())))
    self:CheckForStuckSessions()
end

function BankSwitch:CreateDebugButtons()
    local window = WINDOW_MANAGER:CreateTopLevelWindow("ParagonBankSwitchBetaDebug")
    window:SetAnchor(TOPRIGHT, GuiRoot, TOPRIGHT, -20, 300)
    window:SetClampedToScreen(true)
    window:SetDrawTier(DT_HIGH)
    -- Keep the commands accessible after the bank scenes close with a stale flag.
    window:SetHidden(false)
    self.debugWindow = window
    self.debugButtons = {}
    local actions = {
        { "CloseBank", "INV_BANK_DEBUG_CLOSE_BANK", function() EndInteraction(INTERACTION_BANK) end },
        { "CloseGuild", "INV_BANK_DEBUG_CLOSE_GUILD", function() EndInteraction(INTERACTION_GUILDBANK) end },
        { "State", "INV_BANK_DEBUG_STATE", function() self:PrintState() end },
        { "ReloadUI", "INV_BANK_DEBUG_RELOAD_UI", function() ReloadUI("ingame") end },
    }
    window:SetDimensions(230, #actions * 32 - 4)
    for index, action in ipairs(actions) do
        local button = CreateControlFromVirtual("$(parent)" .. action[1], window, "ZO_DefaultButton")
        button:SetDimensions(230, 28)
        button:SetAnchor(TOPLEFT, window, TOPLEFT, 0, (index - 1) * 32)
        button:SetFont("ZoFontGame")
        button:SetHandler("OnClicked", action[3])
        self.debugButtons[index] = { control = button, textKey = action[2] }
    end
    self:RefreshLocalization()
end

function BankSwitch:CaptureOptions()
    -- A fresh dialogue belongs to a new user interaction, even at the same NPC.
    self:CancelCloseSessions("new-banker-dialogue")
    local request = self.pending
    local bankerName = GetUnitName("interact")
    if bankerName == "" then return end
    if request and request.bankerName ~= bankerName then
        self:CancelSwitch("different-npc")
        return
    end
    self.bankIndex, self.guildBankIndex = nil, nil
    self.bankerName = bankerName
    for index = 1, GetChatterOptionCount() do
        local _, optionType = GetChatterOption(index)
        if optionType == CHATTER_START_BANK then
            self.bankIndex = index
        elseif optionType == CHATTER_START_GUILDBANK or optionType == CHATTER_OPEN_GUILDBANK then
            self.guildBankIndex = index
        end
    end
    if request and request.phase == "dialogue" then request.optionsReady = true end
    self:Trace("options-ready")
    self:Refresh()
    zo_callLater(function() self:AdvanceSwitch() end, 0)
end

function BankSwitch:GetCurrentService()
    if IsInGamepadPreferredMode() then return end
    local scene = SCENE_MANAGER:GetCurrentScene()
    local name = scene and scene:GetName()
    if services[name] and scene:GetState() ~= SCENE_HIDDEN then return name end
end

function BankSwitch:GetTarget(sceneName)
    local service = services[sceneName]
    if service then return self[service.indexKey], service.event end
end

function BankSwitch:CanSwitch(sceneName)
    local current = self:GetCurrentService()
    local index = self:GetTarget(sceneName)
    if not current or current == sceneName or not index
        or SCENE_MANAGER:GetCurrentScene():GetState() ~= SCENE_SHOWN then return false end
    if GetInteractionType() ~= services[current].interactionType then return false end
    if current == "bank" and (not IsBankOpen() or GetBankingBag() ~= BAG_BANK) then return false end
    if current == "guildBank" and not IsGuildBankOpen() then return false end
    return self.bankerName ~= nil and self.bankerName ~= "" and self.bankerName == GetUnitName("interact")
        and not self.pending and not self.closeRequest and not self.reloadRequest and not IsInteractionPending()
        and not IsGuildBankBusy()
end

function BankSwitch:AdjustDepositActions(inventorySlot, slotActions)
    if IsInGamepadPreferredMode() or not IsBankOpen() or not IsGuildBankOpen()
        or ZO_InventorySlot_GetType(inventorySlot) ~= SLOT_TYPE_ITEM then return end
    local bagId = ZO_Inventory_GetBagAndIndex(inventorySlot)
    if bagId ~= BAG_BACKPACK then return end
    local interactionType = GetInteractionType()
    local guildActive = interactionType == INTERACTION_GUILDBANK and SCENE_MANAGER:IsShowing("guildBank")
    local bankActive = interactionType == INTERACTION_BANK and SCENE_MANAGER:IsShowing("bank")
    if not guildActive and not bankActive then return end

    -- Native discovery adds bank_deposit before guild_bank_deposit. Both have the
    -- same label/type, but the first action is used by double-click and keybinds.
    local depositName = GetString(SI_ITEM_ACTION_BANK_DEPOSIT)
    local bankAction, guildAction
    for index = 1, slotActions:GetNumSlotActions() do
        local action = slotActions:GetSlotAction(index)
        if action[1] == depositName and action[3] == "primary" then
            if not bankAction then
                bankAction = action
            else
                guildAction = action
                break
            end
        end
    end
    if not bankAction or not guildAction then return end
    local activeAction = guildActive and guildAction or bankAction
    local inactiveAction = guildActive and bankAction or guildAction
    local previousCallback = inactiveAction[2]
    if previousCallback == activeAction[2] then return end
    -- Reuse the native closure after discovery has returned. Wrapping discovery
    -- or the callback would put addon code on the private bank-action call stack.
    inactiveAction[2] = activeAction[2]
    if slotActions.m_contextMenuMode then
        for _, entry in ipairs(ZO_Menu.items) do
            local menuItem = entry.item
            if menuItem and menuItem.OnSelect == previousCallback then
                menuItem.OnSelect = activeAction[2]
            end
        end
    end
end

function BankSwitch:AdvanceSwitch()
    local request = self.pending
    if not request then return end
    if IsInGamepadPreferredMode() then self:CancelSwitch("input-mode-changed"); return end
    if request.phase == "dialogue" then
        if not request.optionsReady then return end
        if SCENE_MANAGER:GetScene(request.sourceScene):GetState() ~= SCENE_HIDDEN then return end
        local dialogue = SCENE_MANAGER:GetScene(self.dialogueSceneName)
        if SCENE_MANAGER:GetCurrentScene() ~= dialogue or dialogue:GetState() ~= SCENE_SHOWN then return end
        if GetUnitName("interact") ~= request.bankerName then self:CancelSwitch("different-npc"); return end
        local index = self:GetTarget(request.targetScene)
        if not index then return end
        local _, optionType = GetChatterOption(index)
        if not IsServiceOption(request.targetScene, optionType) then return end
        local interaction = SYSTEMS:GetObjectBasedOnCurrentScene(ZO_INTERACTION_SYSTEM_NAME)
        local option = interaction and interaction.optionControls and interaction.optionControls[index]
        if not option or option.optionIndex ~= index or not option.enabled then return end
        -- Without a close event the old search context can remain active too.
        -- Clear it while both banking scenes are hidden, before native activation.
        PLAYER_INVENTORY:DeactivateBankSearch()
        PLAYER_INVENTORY:DeactivateGuildBankSearch()
        -- The native menu selects a populated option without waiting for bank-open
        -- flags to clear. Requiring both flags here can deadlock at the banker menu.
        request.phase = "opening"
        self:Trace("select-option")
        -- Re-entering an already-open bank can change GetInteractionType without
        -- another EVENT_OPEN_*. Check only during this request, bounded by its timeout.
        EVENT_MANAGER:RegisterForUpdate(OPENING_UPDATE_NAMESPACE, 50, function() self:AdvanceSwitch() end)
        INTERACT_WINDOW:SelectChatterOptionByIndex(index)
        return
    end
    local targetOpen = request.targetScene == "bank" and IsBankOpen()
        or request.targetScene == "guildBank" and IsGuildBankOpen()
    local scene = SCENE_MANAGER:GetScene(request.targetScene)
    local targetActive = targetOpen and GetInteractionType() == request.targetType and not IsInteractionPending()
        and (request.targetType ~= INTERACTION_BANK or GetBankingBag() == BAG_BANK)
    if targetActive then
        if SCENE_MANAGER:GetCurrentScene() == scene and scene:GetState() == SCENE_SHOWN then
            self:Trace("complete")
            EVENT_MANAGER:UnregisterForUpdate(OPENING_UPDATE_NAMESPACE)
            self.pending = nil
        elseif not request.sceneRequested and scene:GetState() == SCENE_HIDDEN
            and SCENE_MANAGER:GetNextScene() ~= scene then
            local now = GetFrameTimeMilliseconds()
            request.targetReadyAt = request.targetReadyAt or now
            -- Let a normal open event show its scene first. A cached bank session
            -- needs the same UI/search setup even when that event is not repeated.
            if now - request.targetReadyAt >= 100 then
                request.sceneRequested = true
                self:Trace("restore-target-scene")
                if request.targetType == INTERACTION_BANK then
                    PLAYER_INVENTORY:ActivateBankSearch()
                    SCENE_MANAGER:Show("bank")
                else
                    PLAYER_INVENTORY:OpenGuildBank()
                end
            end
        end
    else
        request.targetReadyAt = nil
    end
    self:Refresh()
end

function BankSwitch:CancelSwitch(reason)
    EVENT_MANAGER:UnregisterForUpdate(OPENING_UPDATE_NAMESPACE)
    if not self.pending then return end
    self:Trace(reason or "cancelled")
    self.pending = nil
    -- Keep the native dialogue/bank usable on failure instead of forcibly ending everything.
    self:Refresh()
end

function BankSwitch:CancelCloseSessions(reason)
    if not self.closeRequest then return end
    self:Trace(reason)
    EVENT_MANAGER:UnregisterForUpdate(CLOSING_UPDATE_NAMESPACE)
    self.closeRequest = nil
    -- Do not end the scene owner here: it may already own the newly opened bank.
    self:Refresh()
end

function BankSwitch:FinishCloseSessions(completed)
    local request = self.closeRequest
    if not request then return end
    self:Trace(completed and "sessions-closed" or "sessions-close-timeout")
    EVENT_MANAGER:UnregisterForUpdate(CLOSING_UPDATE_NAMESPACE)
    self.closeRequest = nil
    -- Release the Lua interaction owner whose OnSceneHidden was deferred below.
    for _, name in ipairs(serviceOrder) do
        INTERACT_WINDOW:EndInteraction(SCENE_MANAGER:GetScene(name):GetInteractionInfo())
    end
    if completed then
        PLAYER_INVENTORY:DeactivateBankSearch()
        PLAYER_INVENTORY:CloseGuildBank()
        PLAYER_INVENTORY:RefreshPlayerInventorySearchContext()
    end
    self:Refresh()
    if not completed and not self.reloadRequest then
        d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_CLOSE_TIMEOUT"))
    end
    self:PrintState()
    if not completed then self:CheckForStuckSessions(true) end
    zo_callLater(function() self:ResumeReload() end, 0)
end

function BankSwitch:AdvanceCloseSessions()
    local request = self.closeRequest
    if not request then return end
    if request.phase == "closing" and not IsBankOpen() and not IsGuildBankOpen() then
        self:FinishCloseSessions(true)
        return
    end
    if request.phase == "activate-bank" then
        if IsInGamepadPreferredMode() or GetUnitName("interact") ~= request.bankerName then
            self:FinishCloseSessions(false)
            return
        end
        if GetInteractionType() ~= INTERACTION_BANK or not IsBankOpen()
            or GetBankingBag() ~= BAG_BANK or IsInteractionPending() then return end
        request.phase = "closing"
        self:Trace("end-active-bank")
        -- End the personal service only after the engine confirms it is active.
        -- Success still requires both flags to clear; Guild Bank may remain orphaned.
        EndInteraction(INTERACTION_BANK)
    end
    if not IsBankOpen() and not IsGuildBankOpen() then self:FinishCloseSessions(true) end
end

function BankSwitch:StartCloseSessions()
    if self.closeRequest then return true end
    if IsInGamepadPreferredMode() then return false end
    if not IsBankOpen() or not IsGuildBankOpen() then return false end
    local interactionType = GetInteractionType()
    if interactionType == INTERACTION_BANK and GetBankingBag() ~= BAG_BANK then return false end
    if interactionType ~= INTERACTION_BANK then
        if interactionType ~= INTERACTION_GUILDBANK and interactionType ~= INTERACTION_CONVERSATION then return false end
        if not self.bankIndex or not self.bankerName or self.bankerName == ""
            or self.bankerName ~= GetUnitName("interact") then return false end
    end
    local reload = self.reloadRequest
    local request = { phase = "activate-bank", trace = reload and reload.trace or {},
        startedAt = reload and reload.startedAt or GetFrameTimeMilliseconds(),
        bankerName = GetUnitName("interact") }
    self.closeRequest = request
    self.lastRequest = reload or request
    self:Trace("close-sessions")
    EVENT_MANAGER:RegisterForUpdate(CLOSING_UPDATE_NAMESPACE, 50, function() self:AdvanceCloseSessions() end)
    if interactionType ~= INTERACTION_BANK then
        self:Trace("activate-bank-before-close")
        -- Cached service choices remain valid while this banker interaction lives.
        SelectChatterOption(self.bankIndex)
    end
    zo_callLater(function() self:AdvanceCloseSessions() end, 0)
    zo_callLater(function()
        if self.closeRequest ~= request then return end
        self:AdvanceCloseSessions()
        if self.closeRequest == request then self:FinishCloseSessions(false) end
    end, 5000)
    self:Refresh()
    return true
end

function BankSwitch:ResumeReload()
    local request = self.reloadRequest
    if not request or self.closeRequest then return end
    local bankOpen, guildOpen = IsBankOpen(), IsGuildBankOpen()
    if not bankOpen then request.endRequested[INTERACTION_BANK] = nil end
    if not guildOpen then request.endRequested[INTERACTION_GUILDBANK] = nil end
    if bankOpen or guildOpen then
        local interactionType = GetInteractionType()
        local activeBank = interactionType == INTERACTION_BANK and bankOpen
            or interactionType == INTERACTION_GUILDBANK and guildOpen
        if activeBank then
            if request.endRequested[interactionType] ~= interactionType then
                request.endRequested[interactionType] = interactionType
                self:Trace("reload-end-active")
                EndInteraction(interactionType)
            end
            return
        end
        -- A switched-away session may outlive the active service. End it on a
        -- later pass, after the active interaction has finished, not in parallel.
        local remainingType
        if bankOpen and not request.endRequested[INTERACTION_BANK] then
            remainingType = INTERACTION_BANK
        elseif guildOpen and not request.endRequested[INTERACTION_GUILDBANK] then
            remainingType = INTERACTION_GUILDBANK
        end
        if remainingType then
            request.endRequested[remainingType] = interactionType
            self:Trace("reload-end-background")
            EndInteraction(remainingType)
        end
        return
    end
    for _, name in ipairs({ "bank", "guildBank" }) do
        if SCENE_MANAGER:GetScene(name):GetState() ~= SCENE_HIDDEN then
            SCENE_MANAGER:Hide(name)
            return
        end
    end
    self:Trace("reload-ready")
    EVENT_MANAGER:UnregisterForUpdate(RELOAD_UPDATE_NAMESPACE)
    self.reloadRequest = nil
    self.originalReloadUI(request.guiName)
end

function BankSwitch:PrepareReload(guiName)
    if self.reloadRequest then return true end
    if not self.pending and not self.closeRequest and not IsBankOpen() and not IsGuildBankOpen() then return false end
    self:CancelSwitch("reload")
    local closing = self.closeRequest
    local request = { guiName = guiName, phase = "reload", endRequested = {},
        trace = closing and closing.trace or {}, startedAt = closing and closing.startedAt or GetFrameTimeMilliseconds(),
        bankerName = GetUnitName("interact") }
    self.reloadRequest = request
    self.lastRequest = request
    self:Trace("reload-request")
    self:Refresh()
    if IsInteractionPending() then EndPendingInteraction() end
    self:StartCloseSessions()
    -- As with opening a cached bank, closing it need not repeat the native event.
    -- Poll only for this reload request, until completion or the existing timeout.
    EVENT_MANAGER:RegisterForUpdate(RELOAD_UPDATE_NAMESPACE, 50, function() self:ResumeReload() end)
    zo_callLater(function() self:ResumeReload() end, 0)
    zo_callLater(function()
        if self.reloadRequest ~= request then return end
        self:ResumeReload()
        if self.reloadRequest ~= request then return end
        self:Trace("reload-timeout")
        EVENT_MANAGER:UnregisterForUpdate(RELOAD_UPDATE_NAMESPACE)
        self.reloadRequest = nil
        self:Refresh()
        d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_RELOAD_TIMEOUT"))
    end, 5000)
    return true
end

function BankSwitch:Switch(targetScene)
    if self.pending then
        if self.pending.targetScene == targetScene then self:CancelSwitch("cancelled") end
        return
    end
    if not self:CanSwitch(targetScene) then return end
    local _, event = self:GetTarget(targetScene)
    local request = { event = event, phase = "dialogue", bankerName = self.bankerName,
        trace = {}, startedAt = GetFrameTimeMilliseconds(),
        targetType = services[targetScene].interactionType,
        sourceScene = self:GetCurrentService(), targetScene = targetScene }
    self.pending = request
    self.lastRequest = request
    self:Trace("reset-chatter")
    self:Refresh()
    -- Return to the banker's root dialogue first so service choices are rebuilt.
    ResetChatter()
    zo_callLater(function()
        if self.pending ~= request then return end
        self:AdvanceSwitch()
        if self.pending ~= request then return end
        self:CancelSwitch("timeout")
        d("|c88CCFF[PBS Beta]|r " .. T("INV_BANK_SWITCH_TIMEOUT"))
    end, 5000)
end

function BankSwitch:Refresh()
    if not self.keybinds then return end
    local count = 0
    for _, name in ipairs(serviceOrder) do
        if self[services[name].indexKey] then count = count + 1 end
    end
    local visible = self:GetCurrentService() ~= nil and count > 1
        and self.bankerName ~= nil and self.bankerName ~= "" and self.bankerName == GetUnitName("interact")
    self.servicesVisible = visible
    self.actionLayerFragment:SetHiddenForReason("services-unavailable", not visible)
    local added = KEYBIND_STRIP:HasKeybindButtonGroup(self.keybinds)
    if visible then
        if added then
            KEYBIND_STRIP:UpdateKeybindButtonGroup(self.keybinds)
        else
            KEYBIND_STRIP:AddKeybindButtonGroup(self.keybinds)
        end
    elseif added then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(self.keybinds)
    end
end

function BankSwitch:Initialize()
    self.dialogueSceneName = SYSTEMS:GetRootSceneName(ZO_INTERACTION_SYSTEM_NAME)
    self.actionLayerFragment = ZO_ActionLayerFragment:New(SERVICE_ACTION_LAYER)
    self.actionLayerFragment:SetHiddenForReason("services-unavailable", true)
    self.keybinds = { alignment = KEYBIND_STRIP_ALIGN_CENTER }
    for _, name in ipairs(serviceOrder) do
        local sceneName, service = name, services[name]
        CreateDefaultActionBind(service.action, service.key, KEY_INVALID, KEY_INVALID, KEY_INVALID, KEY_INVALID)
        self.keybinds[#self.keybinds + 1] = {
            name = function()
                return T(self.pending and self.pending.targetScene == sceneName and "INV_BANK_SWITCH_CANCEL" or service.textKey)
            end,
            keybind = service.action,
            callback = function() self:Switch(sceneName) end,
            enabled = function()
                return self.pending ~= nil and self.pending.targetScene == sceneName or self:CanSwitch(sceneName)
            end,
            disabledDuringSceneHiding = true,
        }
        SCENE_MANAGER:GetScene(sceneName):AddFragment(self.actionLayerFragment)
    end
    SecurePostHook("ZO_InventorySlot_DiscoverSlotActionsFromActionList", function(inventorySlot, slotActions)
        self:AdjustDepositActions(inventorySlot, slotActions)
    end)
    -- Activating the personal bank for shutdown must not reopen its window.
    ZO_PreHook(PLAYER_INVENTORY, "GetBankInventoryType", function()
        return self.closeRequest ~= nil and self.closeRequest.phase == "activate-bank"
    end)
    for _, name in ipairs(serviceOrder) do
        ZO_PreHook(SCENE_MANAGER:GetScene(name), "OnSceneHidden", function()
            -- Keep the banker context alive until both services have been ended.
            return self.closeRequest ~= nil
        end)
    end
    -- "Shown" fires inside InitializeInteractWindow, before UpdateChatterOptions.
    -- Capture only after the native keyboard menu has finished populating its rows.
    SecurePostHook(ZO_Interaction, "UpdateChatterOptions", function()
        if not IsInGamepadPreferredMode() then self:CaptureOptions() end
    end)
    local bankEvents = {
        [EVENT_OPEN_BANK] = "open-bank", [EVENT_OPEN_GUILD_BANK] = "open-guild",
        [EVENT_CLOSE_BANK] = "close-bank", [EVENT_CLOSE_GUILD_BANK] = "close-guild",
    }
    for event, name in pairs(bankEvents) do
        local eventName = name
        local openedType = event == EVENT_OPEN_BANK and INTERACTION_BANK
            or event == EVENT_OPEN_GUILD_BANK and INTERACTION_GUILDBANK
        EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, event, function()
            local closing = self.closeRequest
            if closing and openedType
                and (closing.phase ~= "activate-bank" or openedType ~= INTERACTION_BANK) then
                self:CancelCloseSessions("new-bank-open")
            end
            if self.reloadRequest and openedType then
                self.reloadRequest.endRequested[openedType] = nil
            end
            self:Trace(eventName)
            -- Native scene and interaction handlers must finish before checking the transition.
            zo_callLater(function()
                self:AdvanceCloseSessions()
                self:AdvanceSwitch()
                self:ResumeReload()
            end, 0)
            if not openedType then
                zo_callLater(function() self:CheckForStuckSessions() end, 500)
            end
            self:Refresh()
        end)
    end
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_GUILD_BANK_OPEN_ERROR, function()
        self:CancelSwitch("guild-open-error")
        self:Refresh()
    end)
    for _, sceneName in ipairs({ "bank", "guildBank", self.dialogueSceneName }) do
        local name = sceneName
        local isDialogue = sceneName == self.dialogueSceneName
        SCENE_MANAGER:GetScene(sceneName):RegisterCallback("StateChange", function(_, state)
            self:Trace(name .. ":" .. tostring(state))
            if state == SCENE_HIDDEN then
                zo_callLater(function() self:CheckForStuckSessions() end, 500)
            end
            if not isDialogue and state == SCENE_HIDING
                and not self.pending and not self.reloadRequest then
                local nextScene = SCENE_MANAGER:GetNextScene()
                if not nextScene or not nextScene.GetInteractionInfo then self:StartCloseSessions() end
            end
            if isDialogue and state == SCENE_HIDING and self.pending and self.pending.phase == "dialogue" then
                self:CancelSwitch("dialogue-closed")
            elseif not isDialogue and state == SCENE_HIDING and self.pending
                and self.pending.phase == "opening" and name == self.pending.targetScene then
                self:CancelSwitch("target-closed")
            end
            self:Refresh()
            zo_callLater(function()
                if not self.pending and not IsBankOpen() and not IsGuildBankOpen()
                    and GetInteractionType() == INTERACTION_NONE
                    and not INTERACT_WINDOW:IsShowingInteraction() then
                    self.bankIndex, self.guildBankIndex, self.bankerName = nil, nil, nil
                end
                self:AdvanceSwitch()
                self:Refresh()
                self:ResumeReload()
            end, 0)
        end)
    end
    local guildBankUI = ParagonUI and ParagonUI.GuildBankUI
    if guildBankUI then
        SecurePostHook(guildBankUI, "Refresh", function() self:Refresh() end)
    end
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_GAMEPAD_PREFERRED_MODE_CHANGED, function()
        self:CancelSwitch("input-mode-changed")
        self:Refresh()
    end)
    -- Keep ReloadUI native; bank flags must not delay or cancel a user reload.
    self.originalReloadUI = ReloadUI
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_PLAYER_DEACTIVATED, function()
        self:CancelSwitch("player-deactivated")
        EVENT_MANAGER:UnregisterForUpdate(CLOSING_UPDATE_NAMESPACE)
        self.closeRequest = nil
        EVENT_MANAGER:UnregisterForUpdate(RELOAD_UPDATE_NAMESPACE)
        self.reloadRequest = nil
        self.bankIndex, self.guildBankIndex, self.bankerName, self.pending = nil, nil, nil, nil
        self.servicesVisible = false
        self.actionLayerFragment:SetHiddenForReason("services-unavailable", true)
        KEYBIND_STRIP:RemoveKeybindButtonGroup(self.keybinds)
    end)
    self:CreateDebugButtons()
    self:CaptureOptions()
end

function BankSwitch:RefreshLocalization()
    if _G[SERVICE_ACTION_LAYER] then SafeAddString(_G[SERVICE_ACTION_LAYER], T("INV_BANK_SERVICES_LAYER"), 1)
    else ZO_CreateStringId(SERVICE_ACTION_LAYER, T("INV_BANK_SERVICES_LAYER")) end
    for _, name in ipairs(serviceOrder) do
        local service = services[name]
        local stringName = "SI_BINDING_NAME_" .. service.action
        if _G[stringName] then SafeAddString(_G[stringName], T(service.textKey), 1)
        else ZO_CreateStringId(stringName, T(service.textKey)) end
    end
    for _, button in ipairs(self.debugButtons or {}) do
        button.control:SetText(T(button.textKey))
    end
    self:Refresh()
end
