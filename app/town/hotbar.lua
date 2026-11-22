-- town/hotbar.lua :: arranging the fight's hotbar (3.1, lib/hotbar.lua; docs/APP.md
-- "Hotbar"); not while fighting (common.not_fighting: the bar stays as the fight began).
--   GET  /hotbar  the ten slots (1 Attack, 9 Guard and 0 Run fixed; 2-8 each with a list of the
--                 actions to put there) and the player's actions; ?saved=1 / ?reset=1 say
--                 what the last POST did
--   POST /hotbar  save: slot2 .. slot8 = an action's key or "" (empty); every other action
--                 goes off the bar. forget (the Reset button; not "reset", which would
--                 hide the form's reset()): forget the arrangement (the bar fills again).
--                 Both redirect to GET /hotbar.
local common = require("town.common")
local hotbar = require("lib.hotbar")
local tips = require("lib.tips")
local view = require("lib.view")

local page = {}

-- An action's label in the lists: "Heal (spell)", "Herb (item)", "Wand (gear)".
local function label(a)
	if a.kind == "spell" then return a.name .. " (spell)" end
	if (a.item.category or "") == "consumable" then return a.name .. " (item)" end
	return a.name .. " (gear)"
end

-- GET /hotbar
function page.show(req)
	local user = req.user
	local choices = hotbar.choices(user)
	local by_key, keys, at_hand = {}, {}, {}
	for _, a in ipairs(hotbar.actions(user)) do at_hand[a.key] = true end
	for _, a in ipairs(choices) do
		a.label = label(a)
		a.tip = a.spell and tips.spell(a.spell) or tips.item(a.item)
		a.away = not at_hand[a.key]
		by_key[a.key] = a
		if not a.away then keys[#keys + 1] = a.key end
	end
	local slots = hotbar.arrange(user.id, keys)
	local list, on = {}, {}
	for n = hotbar.FIRST, hotbar.LAST do
		local a = slots[n] and by_key[slots[n]]
		if a then on[a.key] = n end
		list[#list + 1] = { n = n, action = a }
	end
	for _, a in ipairs(choices) do a.slot = on[a.key] end
	return view.page(req, "Hotbar", "town/hotbar", {
		slots = list,
		choices = choices,
		saved = req.query.saved ~= nil,
		reset = req.query.reset ~= nil,
		attack_icon = "/static/images/skills/attack.png",
		guard_icon = "/static/images/skills/guard.png",
		run_icon = "/static/images/skills/run.png",
	})
end

-- POST /hotbar
function page.save(req)
	local user = req.user
	local form = req.form
	if form.forget ~= nil then
		hotbar.reset(user.id)
		return view.redirect("/hotbar?reset=1")
	end
	local _, allowed = hotbar.choices(user)
	local chosen, used = {}, {}
	for n = hotbar.FIRST, hotbar.LAST do
		local key = form["slot" .. n]
		if key ~= nil and key ~= "" then
			if not allowed[key] then return common.cheat(req) end
			-- the same action in two lists (no JavaScript): the first slot keeps it
			if not used[key] then
				used[key] = true
				chosen[n] = key
			end
		end
	end
	hotbar.save(user, chosen)
	return view.redirect("/hotbar?saved=1")
end

return page
