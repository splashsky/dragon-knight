-- town/inn.lua :: legacy towns.php inn(): pay the innprice, refill HP/MP/TP, and (2.4) the
-- charges of the equipped items that cast a spell (bag items keep theirs; single-use ones
-- aren't rechargeable).
local common = require("town.common")
local game = require("lib.game")
local inventory = require("lib.inventory")
local items = require("lib.items")
local view = require("lib.view")

local inn = {}

-- GET /inn shows the confirmation; POST /inn with "submit" stays, with "cancel" leaves.
function inn.handle(req)
	local user = req.user
	local town = common.town_here(req)
	if not town then return common.cheat(req) end
	if user.gold < town.innprice then return common.message(req, "Inn", "inn_poor") end

	if req.method == "POST" and req.form.submit ~= nil then
		local s = game.stats(user)
		dk.db:exec("UPDATE users SET gold = ?, currenthp = ?, currentmp = ?, currenttp = ? WHERE id = ?",
							 user.gold - town.innprice, s.maxhp, s.maxmp, s.maxtp, user.id)
		local recharged = {}
		for _, e in ipairs(inventory.recharge(user.id)) do recharged[#recharged + 1] = e.item.name end
		return common.message(req, "Inn", "inn_done", { recharged = recharged })
	elseif req.method == "POST" and req.form.cancel ~= nil then
		return view.redirect("/")
	end
	-- what a night recharges: the equipped items that cast and are rechargeable
	local charged = {}
	for _, slot in ipairs(inventory.SLOTS) do
		local e = inventory.equipped(user.id)[slot]
		if e and items.casts(e.item) and items.rechargeable(e.item) then
			charged[#charged + 1] = { name = e.item.name, charges = math.min(e.charges, e.item.charges), max = e.item.charges }
		end
	end
	return view.page(req, "Inn", "town/inn", { town = town, charged = charged })
end

return inn
