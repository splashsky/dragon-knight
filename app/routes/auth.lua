-- routes/auth.lua :: accounts (port of legacy login.php + users.php).
local auth = require("lib.auth")
local game = require("lib.game")
local mail = require("lib.mail")
local php = require("lib.php")
local session = require("lib.session")
local view = require("lib.view")

local PAGE = { nav = false }   -- account pages never show the game nav (legacy display(..., false, false, false))

local function field(req, name)
  local v = req.form[name]
  if type(v) ~= "string" then return "" end
  return v
end

-- legacy: preg_match("/[^A-z0-9_\-]/") -- note A-z also admits [ \ ] ^ _ `
local function is_alnum(s)
  return not s:find("[^A-z0-9_%-]")
end

local MAX_PASSWORD = 200

-- Base URL of the game for emails: control.gameurl (legacy pointed it at index.php),
-- else the request's Host.
local function base_url(req)
  local u = tostring(game.control().gameurl or "")
  u = u:gsub("/index%.php$", ""):gsub("/+$", "")
  if u == "" then
    local host = req.headers["host"] or "localhost"
    if not host:find("^[%w%.%-:%[%]]+$") then host = "localhost" end
    u = "http://" .. host
  end
  return u
end

---------------------------------------------------------------------------------------
-- login / logout

local function login_form(req, ctx)
  return view.page(req, "Log In", "auth/login", ctx or {}, PAGE)
end

local function login_post(req)
  local username, password = field(req, "username"), field(req, "password")
  local user = username ~= "" and dk.db:first("SELECT * FROM users WHERE username = ?", username)
  if not auth.verify_password(password, user and user.password) then
    return login_form(req, { error = "Invalid username or password. Please go back and try again.",
                             username = username })
  end
  if auth.needs_rehash(user.password) then
    dk.db:exec("UPDATE users SET password = ? WHERE id = ?", auth.hash_password(password), user.id)
  end
  session.create(req, user.id, req.form.rememberme ~= nil)
  return view.redirect("/")
end

local function logout(req)
  session.destroy(req)
  return view.redirect("/login")
end

---------------------------------------------------------------------------------------
-- register

local function register_ctx(values, errors)
  local c = game.control()
  return {
    v = values or {},
    errors = errors,
    verifyemail = c.verifyemail == 1,
    classes = { c.class1name, c.class2name, c.class3name },
    difficulties = { c.diff1name, c.diff2name, c.diff3name },
  }
end

local function register_form(req)
  return view.page(req, "Register", "auth/register", register_ctx(), PAGE)
end

local function send_verify_mail(req, email, code)
  local c = game.control()
  local url = base_url(req)
  local body = table.concat({
    "You or someone using your email address recently signed up for an account on the " ..
      c.gamename .. " server, located at " .. url .. ".",
    "",
    "This email is sent to verify your registration email. In order to begin using your " ..
      "account, you must verify your email address. ",
    "Please visit the Verification Page (" .. url .. "/verify) and enter the code below to " ..
      "activate your account.",
    "Verification code: " .. code,
    "",
    "If you were not the person who signed up for the game, please disregard this message. " ..
      "You will not be emailed again.",
  }, "\n")
  return mail.send(email, c.gamename .. " Account Verification", body)
end

local function register_post(req)
  local c = game.control()
  local v = {
    username = field(req, "username"), charname = field(req, "charname"),
    email1 = field(req, "email1"), email2 = field(req, "email2"),
    charclass = field(req, "charclass"), difficulty = field(req, "difficulty"),
  }
  local password1, password2 = field(req, "password1"), field(req, "password2")
  local errors = {}
  local function err(msg) errors[#errors + 1] = msg end

  if v.username == "" then err("Username field is required.") end
  if not is_alnum(v.username) then err("Username must be alphanumeric.") end
  if #v.username > 30 then err("Username must be 30 characters or less.") end
  if dk.db:first("SELECT id FROM users WHERE username = ? LIMIT 1", v.username) then
    err("Username already taken - unique username required.")
  end

  if v.charname == "" then err("Character Name field is required.") end
  if not is_alnum(v.charname) then err("Character Name must be alphanumeric.") end
  if #v.charname > 30 then err("Character Name must be 30 characters or less.") end
  if dk.db:first("SELECT id FROM users WHERE charname = ? LIMIT 1", v.charname) then
    err("Character Name already taken - unique Character Name required.")
  end

  if v.email1 == "" or v.email2 == "" then err("Email fields are required.") end
  if v.email1 ~= v.email2 then err("Emails don't match.") end
  if not php.is_email(v.email1) then err("Email isn't valid.") end
  if dk.db:first("SELECT id FROM users WHERE email = ? LIMIT 1", v.email1) then
    err("Email already taken - unique email address required.")
  end

  -- Passwords may contain any characters now (legacy: alphanumeric, max 10).
  if php.trim(password1) == "" then err("Password field is required.") end
  if #password1 > MAX_PASSWORD then err("Password is too long.") end
  if password1 ~= password2 then err("Passwords don't match.") end

  local charclass = math.tointeger(tonumber(v.charclass))
  local difficulty = math.tointeger(tonumber(v.difficulty))
  if not charclass or charclass < 1 or charclass > 3 then err("Character Class is invalid.") end
  if not difficulty or difficulty < 1 or difficulty > 3 then err("Difficulty is invalid.") end

  if #errors > 0 then
    return view.page(req, "Register", "auth/register", register_ctx(v, errors), PAGE)
  end

  local verifycode = c.verifyemail == 1 and auth.random_letters(8) or "1"
  dk.db:exec("INSERT INTO users (regdate, verify, username, password, email, charname, charclass, difficulty) " ..
             "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", dk.now(), verifycode, v.username,
             auth.hash_password(password1), v.email1, v.charname, charclass, difficulty)

  local msg
  if c.verifyemail == 1 then
    if send_verify_mail(req, v.email1, verifycode) then
      msg = "Your account was created successfully.<br /><br />You should receive an Account " ..
        "Verification email shortly. You will need the verification code contained in that " ..
        "email before you are allowed to log in. Once you have received the email, please " ..
        "visit the <a href=\"/verify\">Verification Page</a> to enter your code and start playing."
    else
      msg = "Your account was created successfully.<br /><br />However, there was a problem " ..
        "sending your verification email. Please check with the game administrator to help " ..
        "resolve this problem."
    end
  else
    msg = "Your account was created succesfully.<br /><br />You may now continue to the " ..
      "<a href=\"/login\">Login Page</a> and continue playing " .. dk.html(c.gamename) .. "!"
  end
  return view.message(req, "Register", msg, PAGE)
end

---------------------------------------------------------------------------------------
-- verify

local function verify_form(req, ctx)
  return view.page(req, "Verify Email", "auth/verify", ctx or {}, PAGE)
end

local function verify_post(req)
  local username, email = field(req, "username"), field(req, "email")
  local code = php.trim(field(req, "verify")):upper()
  local function fail(msg)
    return verify_form(req, { error = msg, username = username, email = email })
  end
  local user = dk.db:first("SELECT id, email, verify FROM users WHERE username = ? LIMIT 1", username)
  if not user then return fail("No account with that username.") end
  if user.verify == "1" then return fail("Your account is already verified.") end
  if user.email:lower() ~= email:lower() then return fail("Incorrect email address.") end
  if not dk.crypto.eq(user.verify, code) then return fail("Incorrect verification code.") end
  dk.db:exec("UPDATE users SET verify = '1' WHERE id = ?", user.id)
  return view.message(req, "Verify Email",
    "Your account was verified successfully.<br /><br />You may now continue to the " ..
    "<a href=\"/login\">Login Page</a> and start playing the game.<br /><br />Thanks for playing!",
    PAGE)
end

---------------------------------------------------------------------------------------
-- lost password

local function lostpassword_form(req, ctx)
  return view.page(req, "Lost Password", "auth/lostpassword", ctx or {}, PAGE)
end

local function lostpassword_post(req)
  local email = field(req, "email")
  local user = email ~= "" and dk.db:first("SELECT id, email FROM users WHERE email = ? LIMIT 1", email)
  if not user then
    return lostpassword_form(req, { error = "No account with that email address.", email = email })
  end
  local newpass = auth.random_letters(8)
  dk.db:exec("UPDATE users SET password = ? WHERE id = ?", auth.hash_password(newpass), user.id)
  session.destroy_user(user.id)
  local c = game.control()
  local body = table.concat({
    "You or someone using your email address submitted a Lost Password application on the " ..
      c.gamename .. " server, located at " .. base_url(req) .. ". ",
    "",
    "We have issued you a new password so you can log back into the game.",
    "",
    "Your new password is: " .. newpass,
    "",
    "Thanks for playing.",
  }, "\n")
  if mail.send(user.email, c.gamename .. " Lost Password", body) then
    return view.message(req, "Lost Password",
      "Your new password was emailed to the address you provided.<br /><br />Once you receive " ..
      "it, you may <a href=\"/login\">Log In</a> and continue playing.<br /><br />Thank you.", PAGE)
  end
  return view.message(req, "Lost Password",
    "There was an error sending your new password.<br /><br />Please check with the game " ..
    "administrator for more information.<br /><br />We apologize for the inconvience.", PAGE)
end

---------------------------------------------------------------------------------------
-- change password

local function changepassword_form(req, ctx)
  return view.page(req, "Change Password", "auth/changepassword", ctx or {}, PAGE)
end

local function changepassword_post(req)
  local username = field(req, "username")
  local oldpass, newpass1, newpass2 = field(req, "oldpass"), field(req, "newpass1"), field(req, "newpass2")
  local function fail(msg)
    return changepassword_form(req, { error = msg, username = username })
  end
  local user = username ~= "" and dk.db:first("SELECT id, password FROM users WHERE username = ? LIMIT 1", username)
  if not user then return fail("No account with that username.") end
  if not auth.verify_password(oldpass, user.password) then
    return fail("The old password you provided was incorrect.")
  end
  if php.trim(newpass1) == "" then return fail("New password field is required.") end
  if #newpass1 > MAX_PASSWORD then return fail("New password is too long.") end
  if newpass1 ~= newpass2 then return fail("New passwords don't match.") end
  dk.db:exec("UPDATE users SET password = ? WHERE id = ?", auth.hash_password(newpass1), user.id)
  session.destroy_user(user.id)
  session.destroy(req)
  return view.message(req, "Change Password",
    "Your password was changed successfully.<br /><br />You have been logged out of the game " ..
    "to avoid cookie errors.<br /><br />Please <a href=\"/login\">log back in</a> to continue playing.",
    PAGE)
end

return function(r)
  r:get("/login", function(req) return login_form(req) end)
  r:post("/login", login_post)
  r:post("/logout", logout)
  r:get("/register", register_form)
  r:post("/register", register_post)
  r:get("/verify", function(req) return verify_form(req) end)
  r:post("/verify", verify_post)
  r:get("/lostpassword", function(req) return lostpassword_form(req) end)
  r:post("/lostpassword", lostpassword_post)
  r:get("/changepassword", function(req) return changepassword_form(req) end)
  r:post("/changepassword", changepassword_post)
end
