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
maintained by Rotation during combat before attacking. The Rotation macro
continues to display only the next offensive ability. Its icon dims while that
ability is unavailable and reveals clockwise with a radial cooldown sweep.
ShamanCore does not add numeric countdown text.

Configured Shock spells are skipped while their corresponding effect is
already visible on the target.

Rotation uses a 0.8-second priority lookahead. A higher-priority ability due
inside that window is preferred over a lower-priority ready ability. When
nothing is ready, the ability with the shortest remaining cooldown is shown.
The chosen preview is held briefly while Vanilla transitions from global to
real cooldown data, preventing rapid icon flicker.

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
