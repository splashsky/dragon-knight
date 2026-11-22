-- app/content/items/ember_staff.lua :: the Ember Staff (a staff that casts Ember).
return {
	name = "Ember Staff",
	description = "A black staff tipped with a brass cup of oil. Equipped, it casts Ember in a fight without costing MP, one charge at a time. Rest at an inn to recharge it.",
	lore = [[
Narcissa's fire-mages keep a brass cup of lamp oil on the head of every staff they sell,
which is the only thing about the design that anyone has ever explained. The oil does
nothing for the spell, the masters say, but a student who can see the flame feels braver.
Most of them learn to leave the cup off by their second winter.]],
	icon = "ember_staff",
	category = "weapon",
	price = 1100,
	attack = 6,
	casts = "ember",                -- the spell it casts (app/content/spells/ember.lua)
	charges = 6,                    -- charges when full
}
