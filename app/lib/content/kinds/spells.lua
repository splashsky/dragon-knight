-- content/kinds/spells.lua :: spells (app/content/spells/<key>.lua) -> the spells table.
-- What a spell does is a list of effects (lib/effects.lua), stored in spells.effects as
-- text; the flat form has them as "effects.1.kind", "effects.1.amount", ... See
-- lib/content/schema.lua for the kind interface and docs/APP.md "Spells" for the file format.
local effects = require("lib.effects")

local spells = {
	name = "spells", table = "spells", dir = "content.spells", label = "spell",
	extra_keys = { effects = true },
}

spells.USABLE_IN = { "town", "fight", "both" }

spells.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page." },
	{ name = "mp", type = "int", required = true, min = 0, max = 1000000, admin = true, label = "MP",
		help = "Magic points it costs to cast." },
	{ name = "usable_in", type = "choice", values = spells.USABLE_IN, default = "fight", label = "Usable in" },
}

local by_name = {}
for _, f in ipairs(spells.fields) do by_name[f.name] = f end

-- Effect parameters are overridable (amounts); an effect's kind is not.
function spells.field(name)
	if by_name[name] then return by_name[name] end
	local i, param = tostring(name):match("^effects%.(%d+)%.([%a_]+)$")
	if not i or param == "kind" then return nil end
	local spec = effects.param_spec(param)
	if not spec then return nil end
	return { name = name, type = spec.type, min = spec.min, max = spec.max, admin = true,
					 label = "Effect " .. i .. " " .. spec.label }
end

function spells.validate_extra(data, flat, err)
	local list, errs = effects.validate(data.effects)
	if not list then
		for _, e in ipairs(errs) do err("effects" .. (e:sub(1, 1) == "[" and "" or " ") .. e) end
		return
	end
	effects.flatten(list, "effects", flat)
	if flat.usable_in and flat.usable_in ~= "fight" and not effects.town_usable(list) then
		err("usable_in = \"" .. flat.usable_in .. "\" needs effects that work outside fights " ..
			"(heal_hp, heal_mp, heal_tp); use \"fight\"")
	end
end

-- The effects list of a flat entity.
function spells.effects(flat)
	return effects.unflatten(flat, "effects")
end

function spells.write_children(id, flat)
	dk.db:exec("UPDATE spells SET effects = ? WHERE id = ?", effects.encode(spells.effects(flat)), id)
end

-- Admin page fields: name, description, MP and the parameters of every effect.
function spells.admin_fields(flat)
	local out = {}
	for _, f in ipairs(spells.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for i, e in ipairs(spells.effects(flat)) do
		for _, p in ipairs(effects.KINDS[e.kind].params) do
			if e[p] ~= nil then
				local spec = spells.field("effects." .. i .. "." .. p)
				spec.label = "Effect " .. i .. " (" .. effects.label(e) .. "): " .. effects.param_spec(p).label
				out[#out + 1] = spec
			end
		end
	end
	return out
end

return spells
