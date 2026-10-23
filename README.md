# Paragon Bank Switch (Beta)

Standalone experimental ESO add-on for keyboard/mouse, API 101051.

## Installation and control

Download the code from [bank-switcher](https://github.com/Nick-Novos/bank-switcher)
and extract it. Rename the extracted directory to `ParagonBankSwitchBeta` so
`ParagonBankSwitchBeta.txt` is directly inside it.

Copy this entire `ParagonBankSwitchBeta` directory directly into ESO's
`live/AddOns/` directory, beside `ParagonUI`, not inside it. Restart ESO so it can
discover the new folder. Enable **Paragon Bank Switch (Beta)** in the add-on list.
It can be enabled or disabled separately from ParagonUI and also runs without it.
There are no required add-on libraries or saved variables.

The standalone repository contains only this add-on. A development copy is also
kept in the ParagonUI repository under `OptionalAddOns/ParagonBankSwitchBeta/`.
The installed `AddOns/ParagonBankSwitchBeta/` directory is a copy; copy subsequent
source edits there before loading the updated add-on.

## Controls

- **1**: Personal Bank.
- **2**: Guild Bank.
- **3**: Guild Store.
- The keybind strip also provides clickable service buttons at bankers offering
  multiple services. The current service and unavailable services are disabled.
- A separate debug button panel on the right, 300 UI units below the top edge,
  closes Personal Bank, Guild Bank, or Guild Store, prints the current state to
  chat, or reloads the UI through the native `ReloadUI("ingame")` call.
- `/pbsb state`: current bank flags, active store interaction and interaction type.
- `/pbsb log`: the latest service-switch/closure trace, up to 60 lines in memory.
- `/pbsb`: help.

Bindings can be reassigned under **Paragon Bank Switch (Beta)**. English and
Russian text follow the game's language. The add-on owns the global namespace
`ParagonBankSwitchBeta`; it does not add a module to `ParagonUI.modules`.

When leaving Guild Bank with both bank flags open, cleanup attempts to activate
Personal Bank and close it. Guild Store exit uses the same sequence when a Bank
option is available from the same NPC, even if Guild Bank was never opened.
The existing experimental transition and cleanup behavior is preserved.

## Known Beta limitation

If a bank flag remains open after interaction ends, or session cleanup fails,
the add-on chooses the recovery hint from the remaining flags. For Personal Bank,
it asks you to talk to a banker, select Personal Bank and press **ESC**. Only if
the interface freezes does it suggest the add-on's **Close personal bank** button.
For Guild Bank, it asks you to select Guild Bank or Guild Store and press **ESC**;
if the interface freezes, enter `/reloadui`. If both flags remain, both instructions are shown,
Personal Bank first. The hint repeats only if the remaining flags change or clear
and get stuck again.
The same check runs with `/pbsb state`. This advice does not reset engine flags
or guarantee recovery.

The banker-service switching sequence has previously left an orphaned banking
state and caused a native inventory initialization error after ReloadUI. Extraction
into a separate add-on does not fix that issue or establish an isolated minimal
reproduction. This extracted version has not yet been validated in ESO.

Disable the Beta in the add-on list to prevent its hooks and events from loading
in the next UI session. To recover an already affected banking session, log out
to character selection and back in with the Beta disabled. A separate add-on is
not a sandbox: all add-ons use the game's shared UI and interaction state.
ReloadUI is not intercepted by this add-on.

ParagonUI is only an optional integration: when present, the Beta avoids starting
a service switch while ParagonUI's guild-bank work queue is running. ParagonUI's
inventory filters, master-writ tracking and bank restacking remain in ParagonUI.
