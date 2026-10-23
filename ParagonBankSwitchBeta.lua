local ADDON_NAME = "ParagonBankSwitchBeta"

ParagonBankSwitchBeta = { name = ADDON_NAME, strings = {} }

function ParagonBankSwitchBeta.Text(key, ...)
    local language = string.lower(GetCVar("language.2") or "en")
    local strings = ParagonBankSwitchBeta.strings[language] or ParagonBankSwitchBeta.strings.en
    local text = strings[key] or ParagonBankSwitchBeta.strings.en[key] or key
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
end

local function Print(message)
    d("|cFFCC66[PBS Beta]|r " .. message)
end

local function HandleCommand(text)
    local command = string.lower(string.match(text or "", "^%s*(.-)%s*$"))
    if command == "log" then
        ParagonBankSwitchBeta.BankSwitch:PrintDebug()
    elseif command == "state" then
        ParagonBankSwitchBeta.BankSwitch:PrintState()
    else
        Print(ParagonBankSwitchBeta.Text("BETA_HELP"))
    end
end

local function OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED)
    Print(ParagonBankSwitchBeta.Text("BETA_LOADED"))
    zo_callLater(function() ParagonBankSwitchBeta.BankSwitch:CheckForStuckSessions() end, 500)
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)
    SLASH_COMMANDS["/pbsb"] = HandleCommand
    ParagonBankSwitchBeta.BankSwitch:Initialize()
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
