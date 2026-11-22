-- content/kinds/summons.lua :: summons (app/content/summons/<key>.lua) -> the summons
-- table. A summon is an ally that fights alongside the player for a while (a spell's
-- s:summon("wolf", { turns = 5 })). Its numbers and message strings are data, synced and
-- overridable; what it does on its turn is its act function (plus the optional
-- on_summon, on_death, on_expire), which stays in the file. See app/fight/engine.lua.
local scripted = require("lib.content.scripted")
local schema = require("lib.content.schema")

local summons = { name = "summons", table = "summons", dir = "content.summons", label = "summon" }

summons.FUNCTIONS = { { "act", true }, { "on_summon", false }, { "on_death", false }, { "on_expire", false } }
summons.extra_keys = scripted.extra_keys(summons.FUNCTIONS)

summons.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page." },
	schema.lore_field(),
	{ name = "icon", type = "icon", dir = "images/summons", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/summons/, without \".png\" (wolf: wolf.png); empty: none." },
	{ name = "hp", type = "int", required = true, min = 1, max = 1000000, admin = true, label = "Hit points" },
	{ name = "attack", type = "int", default = 0, min = 0, max = 1000000, admin = true, label = "Attack" },
	{ name = "defense", type = "int", default = 0, min = 0, max = 1000000, admin = true, label = "Defense",
		help = "Takes the place of the player's defense power when a monster attacks it." },
	{ name = "dexterity", type = "int", default = 0, min = 0, max = 1000000, admin = true, label = "Dexterity",
		help = "Its chance to dodge a monster's attack, like the player's dexterity." },
	{ name = "turns", type = "int", default = 0, min = 0, max = 10000, admin = true, label = "Turns",
		help = "How many rounds it stays when summoned without a duration; 0: until the end of the fight." },
}

local by_name = {}
for _, f in ipairs(summons.fields) do by_name[f.name] = f end

function summons.field(name)
	return by_name[name] or scripted.field(name)
end

function summons.validate_extra(data, flat, err)
	scripted.validate(data, flat, err, summons.FUNCTIONS)
	if data.messages ~= nil and type(data.messages) == "table" and data.messages.enemy ~= nil then
		err("field 'messages.enemy': summons fight for the player and have no monster wording")
	end
end

function summons.write_children(id, flat)
	scripted.write("summons", id, flat)
end

function summons.admin_fields(flat)
	local out = {}
	for _, f in ipairs(summons.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return summons
