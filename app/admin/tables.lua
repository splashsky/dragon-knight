-- admin/tables.lua :: field specs for the simple "list + edit one row" tables
-- (legacy admin.php towns, users; items and drops, spells, classes and monsters are
-- content, see admin/items.lua, admin/spells.lua, admin/classes.lua and admin/effects.lua). See
-- admin/editor.lua for the spec format. Column lists here are the UPDATE whitelists.
local auth = require("lib.auth")
local classes = require("lib.classes")
local inventory = require("lib.inventory")
local items = require("lib.items")
local roles = require("lib.roles")
local session = require("lib.session")
local spells = require("lib.spells")

local tables = {}

local SEP = { kind = "separator" }

local function num(name, label, size, maxlength, extra)
	local f = { name = name, label = label, int = true, size = size or 5, maxlength = maxlength or 10,
							required = label .. " is required.", numeric = label .. " must be a number." }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

local function text(name, label, size, maxlength, extra)
	local f = { name = name, label = label, size = size or 30, maxlength = maxlength or 30,
							required = label .. " is required." }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

local ID = { name = "id", label = "ID", kind = "static" }

-- "round 3; Blue Slime 4/4 HP (Asleep); you: Damage Up" for the user editor.
local function statuses_text(sql, ...)
	local names = {}
	for _, r in ipairs(dk.db:query(sql, ...)) do
		names[#names + 1] = r.name .. (r.turns_left and (" (" .. r.turns_left .. ")") or "")
	end
	return table.concat(names, ", ")
end

local function fight_summary(user_id)
	local f = dk.db:first("SELECT round, wave FROM fights WHERE user_id = ?", user_id)
	if not f then return "None" end
	local parts = { "round " .. f.round }
	for _, c in ipairs(dk.db:query("SELECT c.*, coalesce(m.name, s.name) AS name FROM fight_combatants c " ..
			"LEFT JOIN monsters m ON c.kind = 'monster' AND m.id = c.entity_id " ..
			"LEFT JOIN summons s ON c.kind = 'summon' AND s.id = c.entity_id WHERE c.user_id = ? ORDER BY c.id", user_id)) do
		local st = statuses_text("SELECT s.name, fs.turns_left FROM fight_statuses fs JOIN statuses s ON s.id = fs.status_id " ..
			"WHERE fs.user_id = ? AND fs.combatant_id = ? ORDER BY fs.position", user_id, c.id)
		local who = c.side == "player" and "you" or (tostring(c.name) .. " " .. tostring(c.hp) .. "/" .. tostring(c.maxhp) .. " HP")
		if c.side ~= "player" or st ~= "" then parts[#parts + 1] = who .. (st ~= "" and (" (" .. st .. ")") or "") end
	end
	return table.concat(parts, "; ")
end

local function world_summary(user_id)
	local st = statuses_text("SELECT s.name, us.turns_left FROM user_statuses us JOIN statuses s ON s.id = us.status_id " ..
		"WHERE us.user_id = ? ORDER BY us.position", user_id)
	return st ~= "" and st or "None"
end

-- Item keys typed in the town editor -> item ids, or nil and the unknown key.
local function item_ids(text)
	local ids = {}
	for key in text:gmatch("[^,%s]+") do
		local id = dk.db:value("SELECT id FROM items WHERE key = ?", key)
		if not id then return nil, key end
		ids[#ids + 1] = id
	end
	return ids
end

tables.towns = function()
	return {
		table = "towns", path = "/admin/towns", column = "name",
		heading = "Edit Towns", saved = "Town updated.",
		list_intro = "Click an town's name to edit it.", none = "No towns found.",
		validate = function(v, errors)
			local _, unknown = item_ids(v.items)
			if unknown then errors[#errors + 1] = "Items: there is no item '" .. unknown .. "'." end
		end,
		after_save = function(_, row, v)
			items.set_town(row.id, item_ids(v.items))
		end,
		fields = {
			ID,
			text("name", "Name"),
			num("latitude", "Latitude", 5, 10, { help = "Positive or negative integer." }),
			num("longitude", "Longitude", 5, 10, { help = "Positive or negative integer." }),
			num("innprice", "Inn Price", 5, 10, { suffix = " gold" }),
			num("mapprice", "Map Price", 5, 10, { suffix = " gold",
				help = "How much it costs to buy the map to this town." }),
			num("travelpoints", "Travel Points", 5, 10, {
				help = "How many TP are consumed when travelling to this town." }),
			{ name = "items", label = "Items", virtual = true, size = 60, maxlength = 2000,
				get = function(row) return table.concat(items.town_keys(row.id), ", ") end,
				help = 'Keys of the items this town\'s shop sells, comma-separated (see <a href="/admin/items">Items</a>; ' ..
							 'example: <span class="highlight">stick, branch, herb</span>).' },
		},
	}
end

-- Spell keys typed in the user editor -> spell ids, or nil and the unknown key.
local function spell_ids(text)
	local ids = {}
	for key in text:gmatch("[^,%s]+") do
		local id = dk.db:value("SELECT id FROM spells WHERE key = ?", key)
		if not id then return nil, key end
		ids[#ids + 1] = id
	end
	return ids
end

-- legacy edituser: every column except id/username/password/regdate/onlinetime is editable.
-- The password hash is never shown; "New Password" (optional) sets a new one. Spells are
-- edited as a list of spell keys (user_spells).
tables.users = function()
	local class_options = {}
	for _, c in ipairs(classes.all()) do
		class_options[#class_options + 1] = { c.id, c.name .. (c.retired ~= 0 and " (retired)" or "") }
	end
	return {
		table = "users", path = "/admin/users", column = "username",
		heading = "Edit Users", saved = "User updated.",
		list_intro = "Click a username to edit the account.", none = "No users found.",
		grouped = true,
		validate = function(v, errors)
			if #v.newpassword > 200 then errors[#errors + 1] = "New Password is too long." end
			local _, unknown = spell_ids(v.spells)
			if unknown then errors[#errors + 1] = "Spells: there is no spell '" .. unknown .. "'." end
		end,
		after_save = function(req, row, v)
			spells.set_known(row.id, spell_ids(v.spells))
			if v.newpassword == "" then return end
			dk.db:exec("UPDATE users SET password = ? WHERE id = ?",
								 auth.hash_password(v.newpassword), row.id)
			-- log the user out everywhere (but keep the admin's own current session)
			dk.db:exec("DELETE FROM sessions WHERE user_id = ? AND token_hash <> ?", row.id,
								 req.session and req.session.token_hash or "")
			session.publish_logout(row.id)
		end,
		fields = {
			ID,
			{ name = "username", label = "Username", kind = "static" },
			text("email", "Email", 30, 100),
			text("verify", "Verify", 30, 8, {
				help = "1 when verified; otherwise the code that was emailed." }),
			text("charname", "Character Name", 30, 30),
			{ name = "regdate", label = "Register Date", kind = "static", format = "datetime" },
			{ name = "onlinetime", label = "Last Online", kind = "static", format = "datetime" },
			{ name = "authlevel", label = "Auth Level", kind = "select", int = true,
				required = "Auth Level is required.", numeric = "Auth Level must be a number.",
				options = roles.CHOICES,
				help = 'A moderator may delete Babble Box messages; set to "Blocked" to temporarily (or permanently) ban a user.' },
			{ name = "newpassword", label = "New Password", kind = "password",
				help = "Leave blank to keep the current password. Setting one logs the user out." },
			SEP,
			num("latitude", "Latitude", 5, 6),
			num("longitude", "Longitude", 5, 6),
			{ name = "charclass", label = "Character Class", kind = "select", int = true,
				required = "Character Class is required.", numeric = "Character Class must be a number.",
				options = class_options },
			SEP,
			text("currentaction", "Current Action", 30, 30),
			{ name = "fight", label = "Fight", kind = "static", virtual = true,
				get = function(row) return fight_summary(row.id) end,
				help = "The fight in progress (since schema version 8 in its own tables); read-only. " ..
					"Setting the action to anything but Fighting doesn't end it: the next encounter replaces it." },
			{ name = "world_statuses", label = "Statuses", kind = "static", virtual = true,
				get = function(row) return world_summary(row.id) end,
				help = "Statuses outside fights (they tick on map moves); read-only." },
			SEP,
			num("currenthp", "Current HP", 5, 6),
			num("currentmp", "Current MP", 5, 6),
			num("currenttp", "Current TP", 5, 6),
			num("base_maxhp", "Base Max HP", 5, 6),
			num("base_maxmp", "Base Max MP", 5, 6),
			num("base_maxtp", "Base Max TP", 5, 6),
			SEP,
			num("level", "Level", 5, 5),
			num("gold", "Gold", 10, 8),
			num("experience", "Experience", 10, 8),
			num("strength", "Base Strength", 5, 5),
			num("dexterity", "Base Dexterity", 5, 5),
			num("base_attack", "Extra Attack Power", 5, 5, {
				help = "Attack power on top of strength and gear (usually 0)." }),
			num("base_defense", "Extra Defense Power", 5, 5, {
				help = "Defense power on top of dexterity and gear (usually 0)." }),
			num("base_exp_bonus", "Base Experience Bonus", 5, 5, { help = "In percent, on top of gear." }),
			num("base_gold_bonus", "Base Gold Bonus", 5, 5, { help = "In percent, on top of gear." }),
			{ name = "effective", label = "Effective Stats", kind = "static", virtual = true,
				get = function(row)
					local st = inventory.stats(row)
					return ("Max HP %d, Max MP %d, Max TP %d, Strength %d, Dexterity %d, Attack Power %d, " ..
									"Defense Power %d, Experience Bonus %d%%, Gold Bonus %d%%"):format(st.maxhp, st.maxmp, st.maxtp,
						st.strength, st.dexterity, st.attack, st.defense, st.exp_bonus_pct, st.gold_bonus_pct)
				end },
			{ name = "inventory", label = "Inventory", kind = "static", virtual = true,
				get = function(row)
					local parts = {}
					for _, e in ipairs(inventory.entries(row.id)) do
						parts[#parts + 1] = e.item.key .. (e.qty > 1 and (" x" .. e.qty) or "") ..
							(e.equipped and (" (" .. e.equipped .. ")") or "")
					end
					return #parts > 0 and table.concat(parts, ", ") or "Empty"
				end,
				help = 'Item keys (see <a href="/admin/items">Items</a>), with the slot of equipped ones. Read-only.' },
			SEP,
			num("dropcode", "Drop Code", 5, 8, { help = "The item a monster just dropped (item ID; 0: none)." }),
			{ name = "spells", label = "Spells", virtual = true, size = 50, maxlength = 1000,
				get = function(row)
					local keys = {}
					for _, s in ipairs(spells.known(row)) do keys[#keys + 1] = s.key end
					return table.concat(keys, ", ")
				end,
				help = 'Keys of the spells the character knows, comma-separated (see <a href="/admin/spells">Spells</a>). ' ..
							 "Spells added here count as learned at an unknown level." },
			text("towns", "Towns", 50, 200),
		},
	}
end

return tables
