-- effects.lua :: the effects engine: what spells (and items) do to a character.
--
-- An effect is a small table: { kind = "heal_hp", amount = 10 }. Content files list them
-- (a spell's `effects`; items' use effects and modifiers), effects.validate() checks them,
-- and the database stores a list as text (effects.encode: "heal_hp amount=10; sleep chance=5").
--
-- Active kinds do something when used (a spell is cast, a consumable is used):
--   heal_hp  { amount }          restores up to `amount` HP (never above max, never lowers)
--   heal_mp  { amount }          the same for MP
--   heal_tp  { amount }          the same for TP
--   damage   { max [, min] }     hurts the monster by rand(min, max); min defaults to
--                                max * 5/6 (the original Hurt spells); none if it is immune
--   sleep    { chance }          puts the monster to sleep: it stays asleep while
--                                rand(1, 15) <= chance (immune when immunity is 2)
--   buff_attack_pct  { pct }     +pct% damage dealt until the end of the fight
--   buff_defense_pct { pct }     -pct% damage taken until the end of the fight
-- The passive kind is a modifier of gear while it is equipped (summed by effects.modifiers):
--   stat     { stat, amount }    stat: maxhp, maxmp, maxtp, strength, dexterity, attack,
--                                defense, exp_bonus_pct, gold_bonus_pct; amount may be < 0
--
-- Applying works on a context: { player = <users row copy, mutated>, in_fight = bool,
-- rand = php.rand-like function, intro = "You have cast the Heal spell" }. The fight state
-- lives on the player row (currentmonsterhp, currentmonstersleep, currentmonsterimmune,
-- currentuberdamage, currentuberdefense), as in the original game. Rolls use exactly the
-- original arguments; messages are plain-text lines (escaped by the templates).
local effects = {}

local function int(min, max, label)
	return { type = "int", min = min, max = max, label = label }
end

effects.STATS = {
	"maxhp", "maxmp", "maxtp", "strength", "dexterity", "attack", "defense", "exp_bonus_pct", "gold_bonus_pct",
}
local STAT_SET = {}
for _, s in ipairs(effects.STATS) do STAT_SET[s] = true end

-- Parameters of the active kinds and of the passive kind (a name means the same thing in
-- every kind of its group, so a flat field "effects.2.amount" has one spec).
local ACTIVE_PARAMS = {
	amount = int(0, 1000000, "amount"),
	max = int(0, 1000000, "maximum damage"),
	min = int(0, 1000000, "minimum damage"),
	chance = int(1, 15, "chance in 15 to stay asleep"),
	pct = int(0, 1000, "percent"),
}
local PASSIVE_PARAMS = {
	stat = { type = "string", values = STAT_SET, label = "stat" },
	amount = int(-1000000, 1000000, "amount"),
}

-- kind -> { label (help pages), params (in order; optional ones in `optional`), town
-- (usable outside fights), heals (current stat it restores, for "already full"), passive }
effects.KINDS = {
	heal_hp = { label = "Heal", params = { "amount" }, town = true, heals = { "currenthp", "maxhp" } },
	heal_mp = { label = "Heal MP", params = { "amount" }, town = true, heals = { "currentmp", "maxmp" } },
	heal_tp = { label = "Heal TP", params = { "amount" }, town = true, heals = { "currenttp", "maxtp" } },
	damage = { label = "Hurt", params = { "max", "min" }, optional = { min = true } },
	sleep = { label = "Sleep", params = { "chance" } },
	buff_attack_pct = { label = "+Damage (%)", params = { "pct" } },
	buff_defense_pct = { label = "+Defense (%)", params = { "pct" } },
	stat = { label = "Modifier", params = { "stat", "amount" }, passive = true },
}

-- What "already full" refusals are called (effects.refusal).
local FULL = { currenthp = "hp_full", currentmp = "mp_full", currenttp = "tp_full" }

-- The spec of a parameter (`passive`: of the stat kind), or nil.
function effects.param_spec(name, passive)
	return (passive and PASSIVE_PARAMS or ACTIVE_PARAMS)[name]
end

local function check_param(spec, v)
	if spec.type == "int" then
		local n = math.type(v) == "float" and math.tointeger(v) or v
		if math.type(n) ~= "integer" or n < spec.min or n > spec.max then
			return nil, ("must be an integer from %d to %d"):format(spec.min, spec.max)
		end
		return n
	end
	if type(v) ~= "string" or not spec.values[v] then
		return nil, "must be one of " .. table.concat(effects.STATS, ", ")
	end
	return v
end

local function kind_names(passive)
	local names = {}
	for k, def in pairs(effects.KINDS) do
		if (def.passive or false) == passive then names[#names + 1] = k end
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- Checks a list of effects from a content file. `passive`: the list holds modifiers (the
-- stat kind) instead of active effects. Returns a normalized copy, or nil and a list of
-- messages ("[2].amount must be ...": the caller prefixes the field name).
function effects.validate(list, passive)
	passive = passive or false
	if type(list) ~= "table" then return nil, { "must be a list of effects, like { { kind = \"heal_hp\", amount = 10 } }" } end
	local errors, out = {}, {}
	local function err(msg) errors[#errors + 1] = msg end
	for i in pairs(list) do
		if math.type(i) ~= "integer" or i < 1 or i > #list then
			err("must be a list (unexpected key " .. tostring(i) .. ")")
			return nil, errors
		end
	end
	if #list == 0 and not passive then err("must list at least one effect") end
	for i, e in ipairs(list) do
		local at = "[" .. i .. "]"
		local def = type(e) == "table" and effects.KINDS[e.kind]
		if type(e) ~= "table" then
			err(at .. " must be a table like { kind = \"heal_hp\", amount = 10 }")
		elseif not def or (def.passive or false) ~= passive then
			err(at .. ".kind must be one of " .. kind_names(passive) .. " (got " .. tostring(e.kind) .. ")")
		else
			local norm, known = { kind = e.kind }, { kind = true }
			for _, p in ipairs(def.params) do
				known[p] = true
				local v = e[p]
				if v == nil then
					if not (def.optional and def.optional[p]) then err(at .. ": missing " .. p) end
				else
					local value, msg = check_param(effects.param_spec(p, passive), v)
					if value == nil then err(at .. "." .. p .. " " .. msg) else norm[p] = value end
				end
			end
			local extra = {}
			for k in pairs(e) do
				if not known[k] then extra[#extra + 1] = tostring(k) end
			end
			table.sort(extra)
			for _, k in ipairs(extra) do err(at .. ": unknown parameter '" .. k .. "' for " .. e.kind) end
			out[i] = norm
		end
	end
	if #errors > 0 then return nil, errors end
	return out
end

---------------------------------------------------------------------------------------
-- Storage: a list as text ("damage max=15; sleep chance=5") and as flat content fields
-- ("effects.1.kind" = "damage", "effects.1.max" = 15).

function effects.encode(list)
	local parts = {}
	for _, e in ipairs(list) do
		local words = { e.kind }
		local def = effects.KINDS[e.kind]
		for _, p in ipairs(def and def.params or {}) do
			if e[p] ~= nil then words[#words + 1] = p .. "=" .. tostring(e[p]) end
		end
		parts[#parts + 1] = table.concat(words, " ")
	end
	return table.concat(parts, "; ")
end

-- The list stored by encode(). Unknown kinds are kept (as { kind = ... }) so that using
-- them is refused instead of silently doing nothing.
function effects.decode(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^;]+") do
		local e
		for word in part:gmatch("%S+") do
			if not e then
				e = { kind = word }
			else
				local k, v = word:match("^([%w_]+)=(.*)$")
				if k then e[k] = math.tointeger(tonumber(v)) or v end
			end
		end
		if e then list[#list + 1] = e end
	end
	return list
end

-- Adds the flat fields of `list` under `prefix` ("effects") to `flat`.
function effects.flatten(list, prefix, flat)
	for i, e in ipairs(list) do
		for k, v in pairs(e) do flat[prefix .. "." .. i .. "." .. k] = v end
	end
	return flat
end

-- The list back from flat fields (parameters the kind doesn't have are ignored).
function effects.unflatten(flat, prefix)
	local list = {}
	local i = 1
	while flat[prefix .. "." .. i .. ".kind"] ~= nil do
		local kind = flat[prefix .. "." .. i .. ".kind"]
		local e = { kind = kind }
		local def = effects.KINDS[kind]
		for _, p in ipairs(def and def.params or {}) do e[p] = flat[prefix .. "." .. i .. "." .. p] end
		list[i] = e
		i = i + 1
	end
	return list
end

---------------------------------------------------------------------------------------
-- Using active effects.

-- Whether every effect of the list works outside fights.
function effects.town_usable(list)
	if #list == 0 then return false end
	for _, e in ipairs(list) do
		local def = effects.KINDS[e.kind]
		if not (def and def.town) then return false end
	end
	return true
end

-- Why the list can't be used now, or nil: "cannot" (empty, unknown or passive kinds),
-- "fight_only" (outside a fight, an effect needs a monster), or "hp_full" / "mp_full" /
-- "tp_full" (only heals, and none would restore anything; named after the first one).
function effects.refusal(list, ctx)
	if #list == 0 then return "cannot" end
	for _, e in ipairs(list) do
		local def = effects.KINDS[e.kind]
		if not def or def.passive or effects.validate({ e }) == nil then return "cannot" end
	end
	if not ctx.in_fight and not effects.town_usable(list) then return "fight_only" end
	local p, full = ctx.player, nil
	for _, e in ipairs(list) do
		local heals = effects.KINDS[e.kind].heals
		if not heals then return nil end
		if p[heals[1]] < p[heals[2]] then return nil end
		full = full or FULL[heals[1]]
	end
	return full
end

local function heal(p, cur, max, amount)
	local gained = amount
	local new = p[cur] + gained
	if p[max] < new then
		gained = p[max] - p[cur]
		new = p[cur] + gained
	end
	if gained < 0 then return 0 end   -- above max (after losing gear): never lowers it
	p[cur] = new
	return gained
end

local APPLY = {
	heal_hp = function(e, p, ctx)
		return ctx.intro .. ", and gained " .. heal(p, "currenthp", "maxhp", e.amount) .. " Hit Points.", "currenthp"
	end,
	heal_mp = function(e, p, ctx)
		return ctx.intro .. ", and gained " .. heal(p, "currentmp", "maxmp", e.amount) .. " Magic Points.", "currentmp"
	end,
	heal_tp = function(e, p, ctx)
		return ctx.intro .. ", and gained " .. heal(p, "currenttp", "maxtp", e.amount) .. " Travel Points.", "currenttp"
	end,
	damage = function(e, p, ctx)
		if p.currentmonsterimmune ~= 0 then return ctx.intro .. ", but the monster is immune to it." end
		local damage = ctx.rand(e.min or (e.max / 6) * 5, e.max)
		p.currentmonsterhp = p.currentmonsterhp - damage
		return ctx.intro .. " for " .. damage .. " damage.", "currentmonsterhp"
	end,
	sleep = function(e, p, ctx)
		if p.currentmonsterimmune == 2 then return ctx.intro .. ", but the monster is immune to it." end
		p.currentmonstersleep = e.chance
		return ctx.intro .. ". The monster is asleep.", "currentmonstersleep"
	end,
	buff_attack_pct = function(e, p, ctx)
		p.currentuberdamage = e.pct
		return ctx.intro .. ", and will gain " .. e.pct .. "% damage until the end of this fight.", "currentuberdamage"
	end,
	buff_defense_pct = function(e, p, ctx)
		p.currentuberdefense = e.pct
		return ctx.intro .. ", and will gain " .. e.pct .. "% defense until the end of this fight.", "currentuberdefense"
	end,
}

-- Applies the list (which effects.refusal allowed) to ctx.player, in order. Returns the
-- message lines (one per effect) and the set of player fields that changed.
function effects.apply(list, ctx)
	local lines, changed = {}, {}
	for _, e in ipairs(list) do
		local line, field = APPLY[e.kind](e, ctx.player, ctx)
		lines[#lines + 1] = line
		if field then changed[field] = true end
	end
	return lines, changed
end

---------------------------------------------------------------------------------------
-- Passive modifiers and display.

-- Sum of the stat modifiers in `list`: { maxhp = 10, strength = -5, ... } (absent = 0).
function effects.modifiers(list)
	local sum = {}
	for _, e in ipairs(list) do
		if e.kind == "stat" then sum[e.stat] = (sum[e.stat] or 0) + e.amount end
	end
	return sum
end

-- The help pages' "type" and "attribute" of one effect: "Hurt", "15" ("12-15" with a min).
function effects.label(e)
	local def = effects.KINDS[e.kind]
	return def and def.label or tostring(e.kind)
end

function effects.attribute(e)
	if e.kind == "damage" and e.min then return e.min .. "-" .. tostring(e.max) end
	if e.kind == "stat" then return e.stat .. " " .. (e.amount > 0 and "+" or "") .. e.amount end
	local def = effects.KINDS[e.kind]
	local p = def and def.params[1]
	return p and tostring(e[p]) or ""
end

return effects
