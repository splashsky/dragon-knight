-- town/inn.lua :: legacy towns.php inn(): pay the innprice, refill HP/MP/TP.
local common = require("town.common")
local game = require("lib.game")
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
		return common.message(req, "Inn", "inn_done")
	elseif req.method == "POST" and req.form.cancel ~= nil then
		return view.redirect("/")
	end
	return view.page(req, "Inn", "town/inn", { town = town })
end

return inn
