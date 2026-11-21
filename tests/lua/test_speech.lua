-- Unit tests for monster speech (fight/speech.lua): nothing certain (a moment speaks by
-- chance), picking a line by weight (not the same line twice in a row), the files' `speech`
-- tables checked (dk check), and monsters speaking in a fight: their first words, a turn's
-- chatter (winning, losing), when hurt, healed, afflicted, at their death and their
-- victory, at most one line a round but for the last, the player's name filled in; lines
-- and lists said once a fight or once each time a condition comes true, conditions on
-- combinations of statuses and HP, and no dice rolled for any of it.
local engine = require("fight.engine")
local kind = require("lib.content.kinds.monsters")
local load = require("lib.content.load")
local php = require("lib.php")
local round = require("fight.round")
local schema = require("lib.content.schema")
local speech = require("fight.speech")
local state = require("fight.state")
local T = {}

local function eq(a, b, what)
	if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function has_error(list, text)
	for _, s in ipairs(list or {}) do
		if s:find(text, 1, true) then return end
	end
	error("no message containing '" .. text .. "' in: " .. table.concat(list or {}, " | "), 2)
end

local function text_of(i, text) return i and text or "-" end

-- A seeded rand with php.rand's argument handling that records the (cast) ranges.
local function recorder(seed)
	local x = seed
	local r = { calls = {} }
	r.rand = function(min, max)
		local a, b = php.intval(min), php.intval(max)
		if a > b then a, b = b, a end
		x = (x * 1103515245 + 12345) % 2147483648
		r.calls[#r.calls + 1] = a .. "," .. b
		return a + x % (b - a + 1)
	end
	return r
end

local M = speech.MARK

local function talker(sp, over)
	local m = { key = "t_talker", name = "Talker", level = 5, maxhp = 100, maxdam = 10, armor = 5, maxexp = 1,
		maxgold = 1, immune = 0, maxmp = 0, uses_mp = 1, attack_weight = 1, roams = 0,
		loadout = { equipment = {}, items = {}, spells = {} }, speech = sp }
	for k, v in pairs(over or {}) do m[k] = v end
	return m
end

local function fight(rand, m, over)
	local p = { id = 1, charname = "Tester", level = 5, currenthp = 500, maxhp = 500, currentmp = 50, maxmp = 100,
		currenttp = 5, maxtp = 10, strength = 5, dexterity = 5, attackpower = 5, defensepower = 5 }
	for k, v in pairs(over or {}) do p[k] = v end
	local f = state.new({ user_id = 1, round = 2, st = p })
	f.rand = rand
	f.data.voice = 7
	local c = state.add_monster(f, m, 1)
	c.hp = c.maxhp
	return f, c
end

local function said(list)
	local out = {}
	for _, l in ipairs(list) do
		if l:sub(1, 1) == M then out[#out + 1] = l:sub(2) end
	end
	return table.concat(out, "|")
end

function T.picks_by_weight_and_not_twice()
	local l = { "a", { text = "b", weight = 3 } }
	eq(text_of(speech.pick(l, 0)), "a")
	for roll = 1, 3 do eq(text_of(speech.pick(l, roll)), "b", "roll " .. roll) end
	eq(text_of(speech.pick(l, 4)), "a")
	-- the line said last time is left out when another may be said
	eq(text_of(speech.pick(l, 1, 2)), "a"); eq(text_of(speech.pick(l, 0, 1)), "b")
	eq(text_of(speech.pick({ "x" }, 5, 1)), "x", "a lone line may come again")
	eq(text_of(speech.pick({ chance = 50 }, 1)), "-", "nothing to say")
	-- only the lines allowed now (asked about every line)
	local asked = {}
	eq(text_of(speech.pick(l, 1, nil, function(i) asked[#asked + 1] = i return i == 1 end)), "a")
	eq(table.concat(asked, ","), "1,2")
	eq(text_of(speech.pick(l, 1, 1, function(i) return i == 1 end)), "a", "the only one allowed, said last or not")
	-- over many rolls the weights hold
	local n = { a = 0, b = 0 }
	for roll = 0, 3999 do local k = text_of(speech.pick(l, roll)); n[k] = n[k] + 1 end
	eq(n.a, 1000); eq(n.b, 3000)
end

function T.nothing_is_certain()
	-- a moment speaks by chance: the list's, else its default; never for certain
	local yes = 0
	for roll = 0, 99 do if speech.speaks({ chance = 30 }, "turn", roll) then yes = yes + 1 end end
	eq(yes, 30)
	yes = 0
	for roll = 0, 99 do if speech.speaks({}, "start", roll) then yes = yes + 1 end end
	eq(yes, speech.CHANCE.start)
	yes = 0
	for roll = 0, 99 do if speech.speaks({ chance = 100 }, "start", roll) then yes = yes + 1 end end
	eq(yes, 99, "at most 99 in 100")
	for _, p in ipairs(speech.POINTS) do assert(speech.CHANCE[p] > 0 and speech.CHANCE[p] < 100, p) end
end

local function base_data(over)
	local d = { name = "X", level = 3, maxhp = 10, maxdam = 4, armor = 2, maxexp = 1, maxgold = 1 }
	for k, v in pairs(over or {}) do d[k] = v end
	return d
end

function T.speech_is_checked()
	local flat = assert(schema.validate(kind, base_data({ speech = {
		start = { "Hello, {player}.", chance = 60 }, turn = { "Hm.", { text = "Hmm!", weight = 2 }, chance = 10, once = true },
		status = { sleep = { "Zzz" }, poison = { { text = "Ugh.", when = { has = { "poison", "uber_damage" } } } } },
		losing = { { text = "Help!", once = true, when = { hp_below = 20, foe_lacks = { "regen" } } },
			{ text = "Again?", once = "condition", when = function(m) return m.round > 2 end } },
		victory = { { text = "Ha!", when = { foe_has = { "sleep" }, from_round = 2, foe_hp_above = 0 } } },
	} })))
	eq(flat["speech.statuses"], "poison,regen,sleep,uber_damage", "the statuses it names (checked against the files)")
	assert(schema.validate(kind, base_data()), "speech is optional")
	local function errors(sp)
		local ok, errs = schema.validate(kind, base_data({ speech = sp }))
		assert(not ok, "expected errors")
		return errs
	end
	has_error(errors("hi"), "field 'speech' must be a table")
	has_error(errors({ shout = { "Hi" } }), "speech: unknown point 'shout'")
	has_error(errors({ start = "Hi" }), "speech.start must be a list of lines")
	has_error(errors({ start = { 5 } }), "speech.start[1] must be one line of text")
	has_error(errors({ start = { "" } }), "speech.start[1] must be one line of text")
	has_error(errors({ start = { "two\nlines" } }), "speech.start[1] must be one line of text")
	has_error(errors({ start = { string.rep("x", 201) } }), "of at most 200 characters")
	has_error(errors({ hurt = { { text = "Ow", weight = 0 } } }), "speech.hurt[1].weight must be an integer from 1")
	has_error(errors({ hurt = { { text = "Ow", chance = 2 } } }), "speech.hurt[1]: unknown field 'chance'")
	has_error(errors({ hurt = { "Ow", chance = 100 } }), "speech.hurt.chance must be an integer from 0 to 99")
	has_error(errors({ hurt = { "Ow", chance = -1 } }), "speech.hurt.chance must be an integer from 0 to 99")
	has_error(errors({ hurt = { "Ow", quiet = 1 } }), "unexpected key quiet")
	has_error(errors({ hurt = { "Ow", once = "yes" } }), "speech.hurt.once must be true")
	has_error(errors({ hurt = { { text = "Ow", once = 2 } } }), 'speech.hurt[1].once must be true (once a fight) or "condition"')
	has_error(errors({ hurt = { { text = "Ow", once = "condition" } } }), 'speech.hurt[1].once = "condition" needs a `when`')
	has_error(errors({ hurt = { { text = "Ow", when = 3 } } }), "speech.hurt[1].when must be a table")
	has_error(errors({ hurt = { { text = "Ow", when = { mood = "bad" } } } }), "speech.hurt[1].when: unknown condition 'mood'")
	has_error(errors({ hurt = { { text = "Ow", when = { has = "poison" } } } }), "speech.hurt[1].when.has must be a list of status keys")
	has_error(errors({ hurt = { { text = "Ow", when = { has = { "Bad Key" } } } } }), "'Bad Key' must be the key of a status")
	has_error(errors({ hurt = { { text = "Ow", when = { hp_below = 101 } } } }), "speech.hurt[1].when.hp_below must be an integer from 0 to 100")
	has_error(errors({ hurt = { { text = "Ow", when = { from_round = 0 } } } }), "speech.hurt[1].when.from_round must be an integer from 1")
	has_error(errors({ status = { "Zzz" } }), "speech.status: '1' must be the key of a status")
	has_error(errors({ status = { sleep = "Zzz" } }), "speech.status.sleep must be a list of lines")
	-- a status that doesn't exist (dk check, against the files), in a condition too
	for n, sp in ipairs({ 'status = { no_such_status = { "?" } }', 'turn = { { text = "?", when = { foe_has = { "no_such_status" } } } }' }) do
		local path = (dk.config.app_dir or "app") .. "/content/monsters/t_speech_ref" .. n .. ".lua"
		local fh = assert(io.open(path, "w"))
		fh:write('return { name = "T", level = 1, maxhp = 1, maxdam = 1, armor = 1, maxexp = 1, maxgold = 1,'
			.. ' speech = { ' .. sp .. ' } }\n')
		fh:close()
		local ok, all = pcall(load.all)
		os.remove(path)
		if not ok then error(all, 0) end
		has_error(all.errors, "t_speech_ref" .. n .. ".lua: speech.statuses: no status 'no_such_status'")
	end
end

function T.monsters_speak_in_a_fight()
	local sp = {
		start = { "Hello, {player}.", chance = 99 }, turn = { "My turn.", chance = 99 }, winning = { "Ha!", chance = 99 },
		losing = { "Uh oh.", chance = 99 }, hurt = { "Ow!", chance = 99 }, healed = { "Better.", chance = 99 },
		status = { sleep = { "Zzz...", chance = 99 } }, death = { "Farewell.", chance = 99 },
		victory = { "Gotcha, {player}.", chance = 99 },
	}
	-- the first words ({player}: the player's name)
	local f, c = fight(recorder(1).rand, talker(sp))
	f.out = {}
	speech.start(f)
	eq(said(f.out), "Talker: \u{201c}Hello, Tester.\u{201d}")
	-- (that was this round's line) a new round: hurt (and alive), at most once a round
	f.out = {}
	engine.damage(f, c, 10)
	eq(said(f.out), "", "one line a round")
	f.round = f.round + 1
	engine.damage(f, c, 10); engine.damage(f, c, 10)
	eq(said(f.out), "Talker: \u{201c}Ow!\u{201d}", "once a round")
	-- healed
	f.round = f.round + 1
	f.out = {}
	engine.apply(f, { { type = "heal", id = c.id, stat = "hp", amount = 5 } }, c)
	eq(said(f.out), "Talker: \u{201c}Better.\u{201d}")
	-- a status put on it
	f.round = f.round + 1
	f.out = {}
	engine.afflict(f, c, "sleep", { chance = 3 })
	eq(said(f.out), "Talker: \u{201c}Zzz...\u{201d}")
	-- its death: the last word even after a line this round, kept for the victory page
	f.out = {}
	engine.damage(f, c, 1000)
	eq(said(f.out), "Talker: \u{201c}Farewell.\u{201d}")
	eq(f.last_words.by, "Talker"); eq(f.last_words.text, "Farewell.")

	-- its turn: winning (the player far behind), losing, else the chatter
	f, c = fight(recorder(2).rand, talker(sp), { currenthp = 50 })
	local r = round.play(f, { kind = "continue" })
	eq(said(r.enemies), "Talker: \u{201c}Ha!\u{201d}")
	f, c = fight(recorder(3).rand, talker(sp))
	c.hp = 10
	r = round.play(f, { kind = "continue" })
	eq(said(r.enemies), "Talker: \u{201c}Uh oh.\u{201d}")
	f = fight(recorder(4).rand, talker(sp))
	r = round.play(f, { kind = "continue" })
	eq(said(r.enemies), "Talker: \u{201c}My turn.\u{201d}")
	-- the player falls: its victory, kept for the death page
	local died = false
	for seed = 5, 60 do
		f = fight(recorder(seed).rand, talker(sp, { maxdam = 100000 }), { currenthp = 1, defensepower = 0 })
		r = round.play(f, { kind = "continue" })
		if r.died then
			died = true
			eq(said(r.enemies):match("Gotcha, Tester%.") ~= nil, true, "the victory line")
			eq(r.f.taunt.by, "Talker"); eq(r.f.taunt.text, "Gotcha, Tester.")
			break
		end
	end
	assert(died, "the player never fell")
end

-- Says moment `point` of monster c in round n (f.out fresh): the text, or "-".
local function speak(f, c, n, point, key)
	f.round, f.out = n, {}
	return speech.say(f, c, point, key) or "-"
end

function T.once_and_conditions()
	-- a line once a fight; a list once a fight
	local f, c = fight(recorder(1).rand, talker({
		turn = { "a", { text = "rare", weight = 1000, once = true }, chance = 99 },
		losing = { "x", "y", once = true, chance = 99 },
	}))
	local got = {}
	for n = 1, 30 do got[#got + 1] = speak(f, c, n, "turn") end
	local rare = 0
	for _, t in ipairs(got) do if t == "rare" then rare = rare + 1 end end
	eq(rare, 1, "the rare line once: " .. table.concat(got, ","))
	local said = 0
	for n = 1, 30 do if speak(f, c, n, "losing") ~= "-" then said = said + 1 end end
	eq(said, 1, "the losing list once")
	-- conditions: statuses on both sides (all of them), shares of HP, the round, a function
	f, c = fight(recorder(2).rand, talker({ turn = { chance = 99,
		{ text = "both", when = { has = { "sleep", "poison" } } },
		{ text = "you sleep, I'm fine", when = { foe_has = { "sleep" }, hp_above = 50 } },
		{ text = "late", when = { from_round = 10, lacks = { "sleep" } } },
		{ text = "fn", when = function(m) return m.target.hp < 100 end },
	} }))
	local p = state.player(f)
	eq(speak(f, c, 1, "turn"), "-", "no condition holds")
	engine.afflict(f, c, "sleep", { chance = 3 })
	eq(speak(f, c, 2, "turn"), "-", "asleep only")
	engine.afflict(f, c, "poison", {})
	eq(speak(f, c, 3, "turn"), "both")
	engine.cure(f, c, "sleep"); engine.cure(f, c, "poison")
	engine.afflict(f, p, "sleep", { chance = 3 })
	eq(speak(f, c, 4, "turn"), "you sleep, I'm fine")
	c.hp = 10
	eq(speak(f, c, 5, "turn"), "-", "not above half its HP")
	engine.cure(f, p, "sleep")
	eq(speak(f, c, 10, "turn"), "late")
	engine.afflict(f, c, "sleep", { chance = 3 })
	eq(speak(f, c, 11, "turn"), "-", "late, but asleep")
	f.st.currenthp = 50
	eq(speak(f, c, 12, "turn"), "fn")
	-- once each time its condition comes true
	f, c = fight(recorder(3).rand, talker({ turn = { chance = 99,
		{ text = "you sleep", when = { foe_has = { "sleep" } }, once = "condition" } } }))
	p = state.player(f)
	engine.afflict(f, p, "sleep", { chance = 3 })
	got = {}
	for n = 1, 4 do got[#got + 1] = speak(f, c, n, "turn") end
	engine.cure(f, p, "sleep")
	got[#got + 1] = speak(f, c, 5, "turn")   -- (the condition stopped holding: it may come again)
	engine.afflict(f, p, "sleep", { chance = 3 })
	for n = 6, 9 do got[#got + 1] = speak(f, c, n, "turn") end
	eq(table.concat(got, ","), "you sleep,-,-,-,-,you sleep,-,-,-")
	-- a failing condition: not said (logged)
	f, c = fight(recorder(4).rand, talker({ turn = { chance = 99, { text = "boom", when = function() error("x") end } } }))
	eq(speak(f, c, 1, "turn"), "-")
end

function T.moments_speak_by_chance()
	-- over many fights a moment speaks about as often as its chance says
	local said = 0
	for voice = 1, 2000 do
		local f, c = fight(recorder(1).rand, talker({ turn = { "a", "b", chance = 30 } }))
		f.data.voice = voice
		if speak(f, c, 3, "turn") ~= "-" then said = said + 1 end
	end
	assert(said > 500 and said < 700, "30% of 2000: " .. said)
end

function T.speech_rolls_no_dice()
	local sp = { turn = { "a", "b", "c", chance = 60 }, hurt = { "x", "y", chance = 90 }, winning = { "w", chance = 99 },
		losing = { "l", chance = 99 } }
	for seed = 1, 30 do
		local quiet, chatty = recorder(seed), recorder(seed)
		local f1 = fight(quiet.rand, talker(nil))
		local f2 = fight(chatty.rand, talker(sp))
		for _ = 1, 4 do
			local r1 = round.play(f1, { kind = "attack" })
			local r2 = round.play(f2, { kind = "attack" })
			eq(table.concat(chatty.calls, " "), table.concat(quiet.calls, " "), "seed " .. seed .. ": the same dice")
			if r1.victory or r1.died or not r1.f then break end
			f1, f2 = r1.f, r2.f
			f1.round, f2.round = f1.round + 1, f2.round + 1
		end
	end
end

return T
