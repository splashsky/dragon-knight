-- routes/home.lua :: GET / (port of legacy index.php donothing/dotown/doexplore).
local auth = require("lib.auth")
local game = require("lib.game")
local news = require("lib.news")
local view = require("lib.view")

local function town_page(req)
	local user = req.user
	local town = game.current_town(user)
	if not town then
		return view.message(req, "Error",
			"There is an error with your user account, or with the town data. Please try again.")
	end
	local control = game.control()
	local ctx = { town = town }
	if control.shownews == 1 then ctx.news = news.latest() end
	ctx.online = view.online()
	-- the town shows the Babble Box larger, instead of in the right column
	ctx.chat = view.chat(req, true)
	return view.page(req, "In Town", "home/town", ctx, { chat_inline = true })
end

local function home(req)
	local action = req.user.currentaction
	if action == "Fighting" then return view.redirect("/fight") end
	if action == "In Town" then return town_page(req) end
	return view.page(req, "Exploring", "home/explore", {})
end

return function(r)
	r:get("/", auth.game, home)
end
