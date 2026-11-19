-- admin/settings.lua :: GET/POST /admin/settings (legacy admin.php main()): the control row.
local common = require("admin.common")
local editor = require("admin.editor")
local game = require("lib.game")
local php = require("lib.php")
local view = require("lib.view")

local settings = {}

local function yesno(name, label, help, no, yes)
  return { name = name, label = label, kind = "select", int = true,
           options = { { 0, no or "No" }, { 1, yes or "Yes" } }, help = help }
end

local function name_field(name, label)
  return { name = name, label = label, size = 20, maxlength = 50 }
end

-- Legacy's "Page Compression" switch is not offered: the C server doesn't gzip, so it
-- would do nothing. The control.compression column is left untouched.
local function spec()
  return {
    table = "control", heading = "Main Settings", saved = "Settings updated.",
    intro = "These options control several major settings for the overall game engine.",
    fields = {
      { name = "gameopen", label = "Game Open", kind = "select", int = true, highlight = true,
        options = { { 1, "Open" }, { 0, "Closed" } },
        help = "Close the game if you are upgrading or working on settings and don't want to " ..
               "cause odd errors for end-users. Closing the game will completely halt all activity." },
      { name = "gamename", label = "Game Name", size = 30, maxlength = 50,
        help = 'Default is "Dragon Knight". Change this if you want to change to call your game ' ..
               "something different." },
      { name = "gameurl", label = "Game URL", size = 50, maxlength = 100,
        help = 'Please specify the full URL to your game installation ("http://www.server.com/dkpath/"). ' ..
               "This gets used in the registration email sent to users. If you leave this field " ..
               "blank, the address the request came in on is used." },
      { name = "adminemail", label = "Admin Email", size = 30, maxlength = 100,
        help = "Please specify your email address. This gets used when the game has to send an " ..
               "email to users." },
      { name = "gamesize", label = "Map Size", size = 3, maxlength = 3, int = true,
        help = "Default is 250. This is the size of each map quadrant. Note that monster levels " ..
               "increase every 5 spaces, so you should ensure that you have at least (map size / 5) " ..
               "monster levels total, otherwise there will be parts of the map without any monsters, " ..
               "or some monsters won't ever get used. Ex: with a map size of 250, you should have 50 " ..
               "monster levels total." },
      { name = "forumtype", label = "Forum Type", kind = "select", int = true,
        options = { { 0, "Disabled" }, { 1, "Internal" }, { 2, "External" } },
        help = "'Disabled' removes the forum link. 'Internal' uses the built-in (and very " ..
               "stripped-down) forum program included with Dragon Knight, if you don't have your " ..
               "own forums software already installed. 'External' uses the address provided below " ..
               "and links to your own forums software." },
      { name = "forumaddress", label = "External Forum", size = 30, maxlength = 200,
        help = "If the above value is set to 'External,' please specify the complete URL to your " ..
               "forums here." },
      yesno("verifyemail", "Email Verification", "Make users verify their email address for " ..
            "added security.", "Disabled", "Enabled"),
      yesno("shownews", "Show News", "Toggle display of the Latest News box in towns."),
      yesno("showonline", "Show Who's Online", "Toggle display of the Who's Online box in towns."),
      yesno("showbabble", "Show Babblebox", "Toggle display of the Babble Box in towns."),
      name_field("class1name", "Class 1 Name"),
      name_field("class2name", "Class 2 Name"),
      name_field("class3name", "Class 3 Name"),
      name_field("diff1name", "Difficulty 1 Name"),
      name_field("diff2name", "Difficulty 2 Name"),
      { name = "diff2mod", label = "Difficulty 2 Value", size = 3, maxlength = 3, real = true,
        help = "Default is 1.2. Specify factoral value for medium difficulty here." },
      name_field("diff3name", "Difficulty 3 Name"),
      { name = "diff3mod", label = "Difficulty 3 Value", size = 3, maxlength = 3, real = true,
        help = "Default is 1.5. Specify factoral value for hard difficulty here." },
    },
    -- legacy main() checks, in its order
    validate = function(v, errors)
      local function err(msg) errors[#errors + 1] = msg end
      if v.gamename == "" then err("Game name is required.") end
      -- PHP: ("abc" % 5) == 0, so a non-number only trips the next check
      if php.intval(v.gamesize) % 5 ~= 0 then err("Map size must be divisible by five.") end
      if not common.is_numeric(v.gamesize) then err("Map size must be a number.") end
      if v.forumtype == "2" and v.forumaddress == "" then
        err("You must specify a forum address when using the External setting.")
      end
      for i = 1, 3 do
        if v["class" .. i .. "name"] == "" then err("Class " .. i .. " name is required.") end
      end
      for i = 1, 3 do
        if v["diff" .. i .. "name"] == "" then err("Difficulty " .. i .. " name is required.") end
      end
      for i = 2, 3 do
        local m = v["diff" .. i .. "mod"]
        if m == "" then
          err("Difficulty " .. i .. " value is required.")
        elseif not common.is_numeric(m) then
          -- not in legacy (MySQL would store 0 and break the formulas)
          err("Difficulty " .. i .. " value must be a number.")
        end
      end
    end,
  }
end

function settings.show(req)
  local s = spec()
  return editor.render(req, s, {
    action = "/admin/settings",
    values = editor.values_from_row(s, game.control()),
    saved = req.query.saved ~= nil,
  })
end

function settings.save(req)
  local s = spec()
  local v = editor.values_from_form(s, req)
  local errors = editor.validate(s, v)
  if #errors > 0 then
    return editor.render(req, s, { action = "/admin/settings", values = v, errors = errors })
  end
  editor.update(s, 1, v)
  game.reload_control()
  return view.redirect("/admin/settings?saved=1")
end

return settings
