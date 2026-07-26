# ShamanCore

ShamanCore is a keypress-driven rotation, self-buff, and emergency-healing
helper for Shaman characters on Turtle WoW and other Vanilla 1.12 clients.
It provides two draggable macro buttons and a small configuration window while
leaving every cast under the player's control.

## Features

- Five configurable offensive abilities in priority order
- Five configurable self-buffs, each with optional in-combat upkeep
- Configurable emergency self-healing
- Optional nearest-enemy targeting
- Dynamic macro icons with cooldown and unavailable-state feedback
- Automatic detection of learned Shaman spells and highest learned ranks
- Movable minimap button with a rested-XP tooltip
- Account-wide saved settings
- No dependencies

Totem management is intentionally outside ShamanCore's scope so it can be
handled by a dedicated totem add-on.

## Installation

1. Copy the `ShamanCore` folder into:
   `World of Warcraft/Interface/AddOns/`
2. Confirm that the final path is
   `Interface/AddOns/ShamanCore/ShamanCore.toc`.
3. Enable ShamanCore on the character-selection **AddOns** screen.
4. Log into a Shaman. ShamanCore prints its version in chat when it has loaded.

ShamanCore exits immediately on non-Shaman characters.

## Quick start

1. Type `/shc` or left-click the minimap button.
2. Choose up to five abilities on the **Rotation** tab.
3. Choose up to five self-buffs on the **Buffs** tab.
4. Configure targeting and healing on the **Options** tab.
5. Open the **Info** tab.
6. Drag the **Rotation** and **Buffs** buttons onto an action bar.
7. Bind those action-bar slots to keys as normal.

If a macro with the same name already exists, ShamanCore reuses it. The
generated character macros are named `Shaman Rot` and `Shaman Buff`.

## Rotation button

Each press performs at most one action, using this order:

1. Cast the configured emergency heal on the player when emergency healing is
   enabled and health is at or below the selected threshold.
2. In combat, apply the first missing configured buff whose **Upkeep during
   combat** box is checked.
3. Out of combat, with no target or the player targeted, apply the first
   missing configured self-buff when **Auto Buff** is enabled.
4. Acquire a nearby enemy when **Smart Target** is enabled and there is no
   living hostile target.
5. Cast the first eligible offensive ability in the five rotation slots.

An existing hostile target skips the out-of-combat automatic buff cycle and
goes directly to the offensive rotation.

### Priority and cooldown preview

Rotation slots are evaluated from top to bottom. ShamanCore uses a 0.8-second
lookahead: a higher-priority ability that will become ready inside that window
is preferred over a lower-priority ability that is ready now. If no configured
ability is ready, the icon previews the one with the shortest remaining
cooldown.

The Rotation macro always displays an offensive ability, even when the next
keypress will heal or buff first. Its icon dims while the previewed spell is
unavailable and displays a clockwise radial cooldown sweep when timing data is
available. ShamanCore does not add numeric countdown text.

The preview is held briefly while the Vanilla client changes from global-
cooldown data to the spell's real cooldown, which prevents rapid icon flicker.
Configured Earth Shock, Flame Shock, and Frost Shock spells are also skipped
while their corresponding effect is already visible on the target.

## Buffs button

Each press applies the first missing and ready self-buff in slot order. This
button works independently of the **Auto Buff** and **Upkeep during combat**
settings, making it useful for manually stepping through the complete buff
list.

Weapon imbues are detected through the main-hand temporary enchant. Regular
self-buffs are detected from the player's active buff icons.

## Configuration

### Rotation

The five slots form a top-to-bottom priority list. Dropdowns include learned
offensive Shaman abilities only. Passive abilities, heals, buffs, weapon
imbues, totems, and spells from the General spellbook tab are excluded.

### Buffs

The five slots form a top-to-bottom self-buff priority list. Enable **Upkeep
during combat** beside a slot to let the Rotation button restore that buff
before attacking.

### Options

| Option | Behavior |
| --- | --- |
| **Smart Target** | Targets the nearest enemy when no living hostile target is selected. |
| **Auto Buff** | Lets Rotation apply missing buffs out of combat when no target or the player is selected. |
| **Emergency Heal** | Lets Rotation heal the player before any other action. |
| **Emergency heal spell** | Selects which learned healing spell to use. |
| **Emergency heal below (%)** | Sets the healing trigger from 1% to 95%. |
| **Debug Messages** | Prints attempted casts to chat for troubleshooting. |

### Defaults

| Setting | Default |
| --- | --- |
| Rotation | Flame Shock, Earth Shock, Stormstrike, Chain Lightning, Lightning Bolt |
| Buffs | Lightning Shield, Windfury Weapon, three empty slots |
| In-combat buff upkeep | Disabled for every slot |
| Emergency heal | Lesser Healing Wave at 35% health |
| Smart Target | Enabled |
| Auto Buff | Enabled |
| Debug Messages | Disabled |

Only currently learned, supported spells appear in dropdowns. ShamanCore casts
the highest learned rank automatically. A configured ability that has not been
learned yet remains saved and becomes available after it is learned.

## Minimap button

- Left-click to toggle the configuration window.
- Drag to reposition the button around the minimap.
- Hover to see the ShamanCore version and rested-XP percentage.
- Use `/shc minimap` if the button needs to be restored to its default
  position.

## Commands

- `/shc` or `/shamancore` - toggle the configuration window.
- `/shc minimap` - show the minimap button and restore its default position.
- `/shc reset` - restore all default settings and reload the UI.

## Important limitations

- Every spell cast requires a hardware keypress. ShamanCore is not a background
  combat bot.
- Vanilla 1.12 does not expose the modern spell-usability API. Rotation
  eligibility is based primarily on spellbook cooldown data; a cast can still
  fail because of range, mana, facing, movement, or another game restriction.
- The add-on cannot choose targets strategically. Smart Target only asks the
  client for the nearest enemy.
- Totems are not selected, placed, or refreshed by ShamanCore.
- Settings use `ShamanCore_Config` as an account-wide saved variable.

## Troubleshooting

### The buttons are missing

Open `/shc`, select the **Info** tab, and drag the buttons onto an action bar
again. Ensure character-specific macros are available.

### Rotation does not attack

Check that at least one configured rotation spell is learned. If **Smart
Target** is disabled, select a living hostile target before pressing Rotation.
Range, mana, facing, and movement restrictions are still enforced by the game.

### Rotation buffs instead of attacking

Out of combat, automatic buffs run only when there is no target or the player
is targeted. Select a hostile target to go directly to the offensive rotation.
In combat, uncheck **Upkeep during combat** for any buff that should not take
priority over attacks.

### A setting behaves unexpectedly

Enable **Debug Messages** to see attempted casts in chat. If necessary, use
`/shc reset` to restore defaults; this reloads the UI and replaces the saved
configuration.
