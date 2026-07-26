# ShamanCore

ShamanCore is a keypress-driven rotation, buff, and emergency-healing
helper for Turtle WoW / Vanilla 1.12.

## First use

1. Enable ShamanCore on the character-selection AddOns screen.
2. Log into a Shaman and type `/shc`.
3. Configure the Rotation, Buffs, and Options tabs.
4. Open the Info tab and drag Rotation and Buffs onto an action bar.

The Rotation button chooses one action per press:

1. Emergency self-heal when enabled and below the configured health threshold.
2. While out of combat with no target or yourself targeted, the first missing
   configured self-buff.
3. With an enemy targeted, buffs are skipped and the first ready spell in the
   five rotation slots is used.

Every Buff slot has an **Upkeep during combat** checkbox. Checked slots are
maintained by Rotation during combat before attacking, and the Rotation macro
shows the selected buff's icon when it is the next action.

Each rotation dropdown is populated with learned offensive Shaman abilities.
Passive spells, buffs, heals, weapon imbues, totems, and everything in the
General tab are excluded.

## Commands

- `/shc` or `/shamancore` — toggle the settings window.
- `/shc minimap` — restore the minimap button to its default position.
- `/shc reset` — restore all default settings.

## Notes

- Every spell cast requires a hardware keypress. ShamanCore does not run a
  background combat bot.
- Totem management is intentionally left to a dedicated totem addon.
- Spell lists contain only supported abilities currently learned by the
  character. The highest learned rank is cast automatically.
