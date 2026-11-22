-- content/kinds/statuses.lua :: statuses (app/content/statuses/<key>.lua) -> the statuses
-- table. A status is a named, timed effect on a combatant (the player, a monster, a
-- summon): poison, a damage buff, sleep, "recharging" after a Hyper Beam. It is scripted
-- like a spell (docs/APP.md "Fight engine"): its numbers (ticks, data) and message strings
-- are data, synced and overridable; what it does is its hooks (on_apply, on_tick,
-- on_expire, on_remove, modify_damage_dealt, modify_damage_taken, blocks_action), which
-- stay in the file; on_tick runs on every tick of the game's clock it is up (10 s). The resistances and wards it gives its bearer (resist, ward:
-- lib/content/affinities.lua) are data too. The runtime is app/fight/engine.lua.
local affinities = require("lib.content.affinities")
local scripted = require("lib.content.scripted")
local schema = require("lib.content.schema")

local statuses = { name = "statuses", table = "statuses", dir = "content.statuses", label = "status" }

statuses.KINDS = { "harmful", "helpful", "neutral" }
statuses.SCOPES = { "fight", "world", "both" }
statuses.FUNCTIONS = {
	{ "on_apply", false }, { "on_tick", false }, { "on_expire", false }, { "on_remove", false },
	{ "modify_damage_dealt", false }, { "modify_damage_taken", false },
}
statuses.extra_keys = scripted.extra_keys(statuses.FUNCTIONS, { blocks_action = true, resist = true, ward = true })

statuses.fields = {
	{ name = "name", type = "string", required = true, max = 50, admin = true, label = "Name" },
	{ name = "description", type = "text", default = "", max = 1000, admin = true, label = "Description",
		help = "Shown on the help page." },
	schema.lore_field(),
	{ name = "icon", type = "icon", dir = "images/statuses", default = "", admin = true, label = "Icon",
		help = "A PNG in public/images/statuses/, without \".png\" (poison: poison.png); empty: none." },
	{ name = "kind", type = "choice", values = statuses.KINDS, default = "neutral", label = "Kind",
		help = "harmful statuses are what an antidote cures; helpful ones are buffs." },
	{ name = "scope", type = "choice", values = statuses.SCOPES, default = "fight", label = "Scope",
		help = "fight: ends with the fight; world: outside fights (it ticks while the character isn't fighting); " ..
			"both: either." },
	{ name = "ticks", type = "int", default = 0, min = 0, max = 10000, admin = true, label = "Ticks",
		help = "How long it lasts when applied without a duration, in ticks of the game's clock (10 seconds " ..
			"each); 0: until removed or the end of the fight." },
}

local by_name = {}
for _, f in ipairs(statuses.fields) do by_name[f.name] = f end
local BLOCKS = { name = "blocks_action", type = "bool", label = "Blocks the bearer's action" }

function statuses.field(name)
	if name == "blocks_action" then return BLOCKS end
	return by_name[name] or affinities.field(name) or scripted.field(name)
end

-- blocks_action is data (true / false, stored) or a function deciding per turn (code).
function statuses.validate_extra(data, flat, err)
	scripted.validate(data, flat, err, statuses.FUNCTIONS)
	affinities.validate(data, flat, err)
	local b = data.blocks_action
	if b == nil or type(b) == "function" then
		flat.blocks_action = 0
	elseif type(b) == "boolean" then
		flat.blocks_action = b and 1 or 0
	else
		err("field 'blocks_action' must be true, false or a function(t) returning true or false")
	end
	if data.messages ~= nil and type(data.messages) == "table" and data.messages.enemy ~= nil then
		err("field 'messages.enemy': statuses have no monster wording (t:say is never worded for a monster)")
	end
end

-- Its wards must be of status files.
function statuses.validate_refs(flat, all, err)
	affinities.check_refs(flat, all, err)
end

function statuses.write_children(id, flat)
	dk.db:exec("UPDATE statuses SET blocks_action = ? WHERE id = ?", flat.blocks_action or 0, id)
	scripted.write("statuses", id, flat)
	affinities.write("statuses", id, flat)
end

-- Admin page fields: name, description, ticks, the named numbers and the messages.
function statuses.admin_fields(flat)
	local out = {}
	for _, f in ipairs(statuses.fields) do
		if f.admin then out[#out + 1] = f end
	end
	for _, f in ipairs(scripted.admin_fields(flat)) do out[#out + 1] = f end
	return out
end

return statuses
