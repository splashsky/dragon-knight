-- Unit tests for the pure helpers in app/lib/news.lua.
local news = require("lib.news")
local T = {}

local function para(text, want, want_more)
	local got, more = news.first_paragraph(text)
	assert(got == want, string.format("%q: paragraph %q, expected %q", text, got, want))
	assert(more == want_more, string.format("%q: more = %s", text, tostring(more)))
end

function T.first_paragraph_single()
	para("One line.", "One line.", false)
	para("Line one\nline two", "Line one\nline two", false)
	para("Trailing blanks\n\n  \n", "Trailing blanks", false)
	para("", "", false)
	para(nil, "", false)
end

function T.first_paragraph_cuts_at_blank_line()
	para("First\nstill first\n\nSecond", "First\nstill first", true)
	para("First\n \t \nSecond", "First", true)
	para("First\n\n\n\nSecond\n\nThird", "First", true)
end

function T.first_paragraph_normalizes_line_ends()
	para("First\r\nmore\r\n\r\nSecond", "First\nmore", true)
	para("First\r\rSecond", "First", true)
	para("First\r\n \r\n", "First", false)
end

function T.first_paragraph_skips_leading_blank_lines()
	para("\n  \nFirst\n\nSecond", "First", true)
end

function T.default_title()
	assert(news.default_title("Short title\nbody") == "Short title")
	assert(news.default_title("   padded   \nbody") == "padded")
	assert(news.default_title("\r\n  \r\nAfter blanks") == "After blanks")
	assert(news.default_title(string.rep("a", 60)) == string.rep("a", 60))
	assert(news.default_title(string.rep("a", 61)) == string.rep("a", 60) .. "...")
	assert(news.default_title(string.rep("a", 59) .. " bcd") == string.rep("a", 59) .. "...")
	assert(news.default_title(string.rep("é", 70)) == string.rep("é", 60) .. "...")
	assert(news.default_title("  \n ") == "")
end

function T.reply_label()
	assert(news.reply_label(0) == "Reply")
	assert(news.reply_label(nil) == "Reply")
	assert(news.reply_label(1) == "1 reply")
	assert(news.reply_label(2) == "2 replies")
	assert(news.reply_label(11) == "11 replies")
end

return T
