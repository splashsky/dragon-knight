-- content/kinds/spells.lua :: spells (app/content/spells/<key>.lua) -> the spells table.
-- A spell file is scripted (docs/APP.md "Scripting spells and items"): its numbers
-- (mp, power, data) and message strings are data, synced and overridable; what it does is
-- its cast function (and the optional can_cast), which stays in the file. See
-- lib/content/schema.lua for the kind interface and lib/content/scripted.lua for the
-- scripted parts.
local scripted = require("lib.content.scripted")

local spells = { name = "spells", table = "spells", dir = "content.spells", label = "spell" }

spells.USABLE_IN = { "town", "fight", "both" }
spells.TARGETS = { "enemy", "self" }
spells.FUNCTIONS = { { "cast", true }, { "can_cast", false } }
spells.extra_keys = scripted.extra_keys(spells.FUNCTIONS)

spells.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page." },
	{ name = "mp", type = "int", required = true, min = 0, max = 1000000, admin = true, label = "MP",
		help = "Magic points it costs to cast." },
	{ name = "power", type = "int", default = 0, min = 0, max = 1000000, admin = true, label = "Power",
		help = "What the spell's code makes of it: the HP it heals, its maximum damage, ..." },
	{ name = "icon", type = "icon", dir = "images/skills", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/skills/, without \".png\" (heal: heal.png); empty: default.png." },
	{ name = "usable_in", type = "choice", values = spells.USABLE_IN, default = "fight", label = "Usable in" },
	{ name = "target", type = "choice", values = spells.TARGETS, default = "enemy", label = "Target" },
}

local by_name = {}
for _, f in ipairs(spells.fields) do by_name[f.name] = f end

-- The top-level fields, the messages ("messages.hit", "messages.enemy.hit") and the named
-- numbers ("data.min").
function spells.field(name)
	return by_name[name] or scripted.field(name)
end

function spells.validate_extra(data, flat, err)
	scripted.validate(data, flat, err, spells.FUNCTIONS)
	if flat.usable_in and flat.usable_in ~= "fight" and flat.target == "enemy" then
		err("usable_in = \"" .. flat.usable_in .. "\" needs target = \"self\" (outside fights there is no " ..
			"enemy); use usable_in = \"fight\" for a spell cast at the enemy")
	end
end

function spells.write_children(id, flat)
	scripted.write("spells", id, flat)
end

-- Admin page fields: name, description, MP, power, the named numbers and the messages.
function spells.admin_fields(flat)
	local out = {}
	for _, f in ipairs(spells.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return spells
