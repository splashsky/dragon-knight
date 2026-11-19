-- admin/tables.lua :: field specs for the simple "list + edit one row" tables
-- (legacy admin.php items/edititem, drops, towns, monsters, spells, users). See
-- admin/editor.lua for the spec format. Column lists here are the UPDATE whitelists.
local auth = require("lib.auth")
local game = require("lib.game")

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

tables.items = function()
  return {
    table = "items", path = "/admin/items", column = "name",
    heading = "Edit Items", saved = "Item updated.",
    list_intro = "Click an item's name to edit it.", none = "No items found.",
    notes = "admin/notes_special_item",
    fields = {
      ID,
      text("name", "Name"),
      { name = "type", label = "Type", kind = "select", int = true,
        options = { { 1, "Weapon" }, { 2, "Armor" }, { 3, "Shield" } } },
      num("buycost", "Cost", 5, 10, { suffix = " gold" }),
      num("attribute", "Attribute", 5, 10, {
        help = "How much the item adds to total attackpower (weapons) or defensepower (armor/shields)." }),
      { name = "special", label = "Special", size = 30, maxlength = 50,
        default = "X", default_if = { "", " " },
        help = 'Should be either a special code or <span class="highlight">X</span> to disable. ' ..
               "Edit this field very carefully because mistakes to formatting or field names " ..
               "can create problems in the game." },
    },
  }
end

local ATTR_HELP = "Edit this field very carefully because mistakes to formatting or field " ..
                  "names can create problems in the game."

tables.drops = function()
  return {
    table = "drops", path = "/admin/drops", column = "name",
    heading = "Edit Drops", saved = "Item updated.",
    list_intro = "Click an item's name to edit it.", none = "No items found.",
    notes = "admin/notes_special_drop",
    fields = {
      ID,
      text("name", "Name"),
      num("mlevel", "Monster Level", 5, 10, {
        required = "Monster level is required.", numeric = "Monster level must be a number.",
        help = "Minimum monster level that will drop this item." }),
      { name = "attribute1", label = "Attribute 1", size = 30, maxlength = 50,
        required = "First attribute is required.", empty = { "", " ", "X" },
        help = "Must be a special code. First attribute cannot be disabled. " .. ATTR_HELP },
      { name = "attribute2", label = "Attribute 2", size = 30, maxlength = 50,
        default = "X", default_if = { "", " " },
        help = 'Should be either a special code or <span class="highlight">X</span> to disable. ' ..
               ATTR_HELP },
    },
  }
end

tables.towns = function()
  return {
    table = "towns", path = "/admin/towns", column = "name",
    heading = "Edit Towns", saved = "Town updated.",
    list_intro = "Click an town's name to edit it.", none = "No towns found.",
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
      text("itemslist", "Items List", 30, 200, {
        help = "Comma-separated list of item ID numbers available for purchase at this town. " ..
               '(Example: <span class="highlight">1,2,3,6,9,10,13,20</span>)' }),
    },
  }
end

tables.monsters = function()
  return {
    table = "monsters", path = "/admin/monsters", column = "name",
    heading = "Edit Monsters", saved = "Monster updated.",
    list_intro = "Click an monster's name to edit it.", none = "No monsters found.",
    fields = {
      ID,
      text("name", "Name"),
      num("maxhp", "Max Hit Points", 5, 10, {
        required = "Max HP is required.", numeric = "Max HP must be a number." }),
      num("maxdam", "Max Damage", 5, 10, { help = "Compares to player's attackpower." }),
      num("armor", "Armor", 5, 10, { help = "Compares to player's defensepower." }),
      num("level", "Monster Level", 5, 10, { help = "Determines spawn location and item drops." }),
      num("maxexp", "Max Experience", 5, 10, {
        required = "Max Exp is required.", numeric = "Max Exp must be a number.",
        help = "Max experience gained from defeating monster." }),
      num("maxgold", "Max Gold", 5, 10, { help = "Max gold gained from defeating monster." }),
      { name = "immune", label = "Immunity", kind = "select", int = true,
        options = { { 0, "None" }, { 1, "Hurt Spells" }, { 2, "Hurt & Sleep Spells" } },
        help = "Some monsters may not be hurt by certain spells." },
    },
  }
end

tables.spells = function()
  return {
    table = "spells", path = "/admin/spells", column = "name",
    heading = "Edit Spells", saved = "Spell updated.",
    list_intro = "Click an spell's name to edit it.", none = "No spells found.",
    fields = {
      ID,
      text("name", "Name"),
      num("mp", "Magic Points", 5, 10, {
        required = "MP is required.", numeric = "MP must be a number.",
        help = "MP required to cast spell." }),
      num("attribute", "Attribute", 5, 10, {
        help = "Numeric value of the spell's effect. Ties with type, below." }),
      { name = "type", label = "Type", kind = "select", int = true,
        options = { { 1, "Heal" }, { 2, "Hurt" }, { 3, "Sleep" }, { 4, "Uber Attack" },
                    { 5, "Uber Defense" } },
        help = "- Heal gives player back [attribute] hit points.<br>" ..
               "- Hurt deals [attribute] damage to monster.<br>" ..
               "- Sleep keeps monster from attacking ([attribute] is monster's chance out of 15 " ..
               "to stay asleep each turn).<br>" ..
               "- Uber Attack increases total attack damage by [attribute] percent.<br>" ..
               "- Uber Defense increases total defense from attack by [attribute] percent." },
    },
  }
end

-- legacy edituser: every column except id/username/password/regdate/onlinetime is editable.
-- The password hash is never shown; "New Password" (optional) sets a new one.
tables.users = function()
  local c = game.control()
  return {
    table = "users", path = "/admin/users", column = "username",
    heading = "Edit Users", saved = "User updated.",
    list_intro = "Click a username to edit the account.", none = "No users found.",
    grouped = true,
    validate = function(v, errors)
      if #v.newpassword > 200 then errors[#errors + 1] = "New Password is too long." end
    end,
    after_save = function(req, row, v)
      if v.newpassword == "" then return end
      dk.db:exec("UPDATE users SET password = ? WHERE id = ?",
                 auth.hash_password(v.newpassword), row.id)
      -- log the user out everywhere (but keep the admin's own current session)
      dk.db:exec("DELETE FROM sessions WHERE user_id = ? AND token_hash <> ?", row.id,
                 req.session and req.session.token_hash or "")
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
        options = { { 0, "User" }, { 1, "Admin" }, { 2, "Blocked" } },
        help = 'Set to "Blocked" to temporarily (or permanently) ban a user.' },
      { name = "newpassword", label = "New Password", kind = "password",
        help = "Leave blank to keep the current password. Setting one logs the user out." },
      SEP,
      num("latitude", "Latitude", 5, 6),
      num("longitude", "Longitude", 5, 6),
      { name = "difficulty", label = "Difficulty", kind = "select", int = true,
        required = "Difficulty is required.", numeric = "Difficulty must be a number.",
        options = { { 1, c.diff1name }, { 2, c.diff2name }, { 3, c.diff3name } } },
      { name = "charclass", label = "Character Class", kind = "select", int = true,
        required = "Character Class is required.", numeric = "Character Class must be a number.",
        options = { { 1, c.class1name }, { 2, c.class2name }, { 3, c.class3name } } },
      SEP,
      text("currentaction", "Current Action", 30, 30),
      num("currentfight", "Current Fight", 5, 4),
      num("currentmonster", "Current Monster", 5, 6),
      num("currentmonsterhp", "Current Monster HP", 5, 6),
      -- legacy swapped the Sleep/Immune labels on these two inputs; fixed here.
      num("currentmonstersleep", "Current Monster Sleep", 5, 3),
      num("currentmonsterimmune", "Current Monster Immune", 5, 3),
      num("currentuberdamage", "Current Uber Damage", 5, 3),
      num("currentuberdefense", "Current Uber Defense", 5, 3),
      SEP,
      num("currenthp", "Current HP", 5, 6),
      num("currentmp", "Current MP", 5, 6),
      num("currenttp", "Current TP", 5, 6),
      num("maxhp", "Max HP", 5, 6),
      num("maxmp", "Max MP", 5, 6),
      num("maxtp", "Max TP", 5, 6),
      SEP,
      num("level", "Level", 5, 5),
      num("gold", "Gold", 10, 8),
      num("experience", "Experience", 10, 8),
      num("goldbonus", "Gold Bonus", 5, 5),
      num("expbonus", "Experience Bonus", 5, 5),
      num("strength", "Strength", 5, 5),
      num("dexterity", "Dexterity", 5, 5),
      num("attackpower", "Attack Power", 5, 5),
      num("defensepower", "Defense Power", 5, 5),
      SEP,
      num("weaponid", "Weapon ID", 5, 5),
      num("armorid", "Armor ID", 5, 5),
      num("shieldid", "Shield ID", 5, 5),
      num("slot1id", "Slot 1 ID", 5, 5),
      num("slot2id", "Slot 2 ID", 5, 5),
      num("slot3id", "Slot 3 ID", 5, 5),
      text("weaponname", "Weapon Name"),
      text("armorname", "Armor Name"),
      text("shieldname", "Shield Name"),
      text("slot1name", "Slot 1 Name"),
      text("slot2name", "Slot 2 Name"),
      text("slot3name", "Slot 3 Name"),
      SEP,
      num("dropcode", "Drop Code", 5, 8),
      text("spells", "Spells", 50, 200),
      text("towns", "Towns", 50, 200),
    },
  }
end

return tables
