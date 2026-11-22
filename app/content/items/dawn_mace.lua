-- app/content/items/dawn_mace.lua :: the Dawn Mace (a holy mace that casts Judgement for Paladins).
return {
	name = "Dawn Mace",
	description = "A flanged mace of white steel. Equipped, it casts Judgement in a fight without costing MP, one charge at a time. You must recharge on the next turn unless the blow slays the monster. Rest at an inn to recharge it.",
	lore = [[
Gilead's temple smiths forge these from the silver of a sunken bell, and every head carries
a small sun cut into the flange. Paladins who swear to the temple carry one in place of
a sword, on the grounds that a holy man should hit things he has blessed. The priests
point out that the mace is heavy and the sun is not, so the blessing is the easy part.]],
	icon = "dawn_mace",
	category = "weapon",
	price = 7000,
	attack = 110,
	element = "holy",               -- its blows strike with holy light, like the spell it casts
	casts = "judgement",           -- the spell it casts (app/content/spells/judgement.lua)
	charges = 3,                    -- charges when full
}
