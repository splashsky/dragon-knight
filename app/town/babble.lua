-- town/babble.lua :: legacy index.php babblebox(): the town page's chat iframe.
-- Text is stored raw and escaped on output (legacy makesafe() stored "&#60;" etc.).
local php = require("lib.php")
local view = require("lib.view")

local babble = {}

babble.MAX_CHARS = 120   -- the form's maxlength
babble.SHOWN = 20

-- makesafe() minus the HTML hacks: no tabs or line breaks, at most MAX_CHARS characters.
function babble.clean(s)
  s = tostring(s or ""):gsub("[\t\r\n]", "")
  if (utf8.len(s) or #s) > babble.MAX_CHARS then
    local cut = utf8.len(s) and utf8.offset(s, babble.MAX_CHARS + 1) or babble.MAX_CHARS + 1
    s = s:sub(1, cut - 1)
  end
  return s
end

-- GET /babble
function babble.show(req)
  local posts = dk.db:query("SELECT * FROM babble ORDER BY id DESC LIMIT ?", babble.SHOWN)
  local ordered = {}
  for i = #posts, 1, -1 do ordered[#ordered + 1] = posts[i] end
  return view.page(req, "Babble Box", "town/babble", { posts = ordered },
                   { layout = "minimal", nav = false })
end

-- POST /babble: blank posts are ignored; always back to the box (POST-redirect-GET).
function babble.post(req)
  local text = babble.clean(req.form.babble)
  if php.trim(text) ~= "" then
    dk.db:exec("INSERT INTO babble (posttime, author, babble) VALUES (?, ?, ?)",
               dk.now(), req.user.charname, text)
  end
  return view.redirect("/babble")
end

return babble
