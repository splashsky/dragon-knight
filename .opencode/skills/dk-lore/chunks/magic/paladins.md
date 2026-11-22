---
id: magic/paladins
summary: The Paladin's oath and prayers: the Midworld chapel, the temples that teach them, and the ladder from Mend to Dawn.
related: [magic/elements, magic/mages, magic/warriors, magic/allies, magic/afflictions, things/gear, monsters/undead, monsters/demons, monsters/people, towns/midworld, towns/bris, towns/gilead, towns/hambry]
sources: [app/content/classes/paladin.lua, app/content/spells/mend.lua, app/content/spells/mercy.lua, app/content/spells/dawn.lua, app/content/spells/dawnstrike.lua, app/content/spells/judgement.lua, app/content/spells/radiance.lua, app/content/spells/consecrate.lua, app/content/spells/iron_vigil.lua, app/content/spells/cleanse.lua, app/content/spells/tithe.lua, app/content/spells/reaver.lua, app/content/fields/consecrated.lua, app/content/items/blessed_mace.lua, app/content/items/dawn_mace.lua, app/content/items/vigil_cuirass.lua, app/content/items/halo_charm.lua]
---

# Paladins

"The Paladins keep an oath sworn before the first dragon fell: to carry light into every dark place
on the map. Their prayers are slower than a Mage's words and their arms slower than a Warrior's
blade, but they rarely fall, and they never leave a companion behind."

They level slowly, with medium hit points and magic, low strength and high dexterity. They start
with 15 hit points, no magic and no spell: the first prayer, Heal, comes at level 2 and Cleanse at
level 3. The Order keeps a page for every field it has held in **the oath book at the Midworld
chapel**, where the Dawn prayer is also written out; the Paladins hold their morning prayers on the
chapel steps when the day is fine.

## Where it is taught

- **The Midworld chapel**: the oath book and the Dawn prayer. Midworld's priests teach the plain
	defending prayer (Defense Up) for little coin and bless graves for a few gold.
- **Bris**: the priests who teach Dawnstrike with its warning, Tithe ("the cheapest mana in the realm"),
	Radiance at 58, Consecrate ("the ground's own blessing"), clerics who teach Life for free.
- **Roma**: Dawnstrike ("the sun rises for the one who is still standing"), Mend (innkeepers say a Paladin
	who can cast it needs fewer rooms).
- **Hambry**: the healers who judge Mercy ("wasted on a scratch"), and the temple that blesses the Blessed Mace.
- **Gilead**: Iron Vigil (priests say faith, mercenaries say the prayer and the cold), Judgement ("the honest spell"), the
	temple smiths who forge the Dawn Mace and bless the Vigil Cuirass.
- **Narcissa**: the priests who say a spirit is someone who has not finished (Call Spirit).

## The ladder

- **Healing, with cures**: Heal 2, Cleanse 3 (three MP; cheaper than the Roma antidote), Mend 9
	(closes a small wound and washes out what the monster left), Revive 11, Mercy 20 (half of what is
	missing), Life 29, Breath 45, Renewal 72, Wellspring 76, **Dawn 90** (a large share of life and
	every harmful effect: "the Paladin's answer to the long wars the Demon King started").
- **Holy strikes**: Dawnstrike 16 (harder when you are below half life), Radiance 58 (the whole
	field; burns hardest on consecrated ground), **Judgement** 64 (gather a turn, then strike and heal a
	little).
- **Ground**: **Consecrate** 30 (holy +25, shadow -25 for most of a minute; drives out Brimstone and
	Miasma: `magic/elements.md`). Priests say the blessing "lasts most of a minute, which is long
	enough for most demons to notice".
- **Wards**: Ward 18, Fire Ward 21, Frost Ward 24, Storm Ward 26, Fend 38, Iron Vigil 48 (the
	night's watch said standing; softer blows and the cuts stop oozing), Last Stand 96.
- **Cries and strikes**: Craze 25, Reaver 31, Rage 60, Finishing Blow 84. "A Paladin pays for
	everything": Tithe 36 hands a little blood back as mana.
- **Afflictions**: Enfeeble 12, Pain 14, Maim 34, Withering 53, Rend 56, Curse 80. Sleep 8, Dream 22, Nightmare 51. No Paladin learns Venom.
- **Allies**: Call Bear 27, Call Spirit 41, Raise Golem 68; Paladins use the golem "to hold a line while the rest
	of the party recovers, and then they thank it" (`magic/allies.md`).

## What people say

- A Paladin who stands in Brimstone too long "starts coughing up old prayers" (`monsters/demons.md`).
- Shadow creatures do not like to stand in the light; those that do squint
	(`monsters/undead.md`, `monsters/fey-and-spirits.md`).
- A Paladin's gear is holy: Blessed Mace (Hambry, Gilead), Dawn Mace (Gilead), Vigil Cuirass, the
	Halo Charm, the Silver Shield (`things/gear.md`, `things/legendary-sets.md`). The knights in
	`monsters/people.md` who fight as Paladins (the Pale Knight, the Serafiend) pray the same prayers.
