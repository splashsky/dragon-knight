-- paging.lua :: `?start=N` paging shared by the forum and the news archive.
-- Render ctx.pages with include("community/forum/pager").
local php = require("lib.php")

local paging = {}

-- The `start` query parameter as a non-negative integer (garbage -> 0).
function paging.start(req)
	local n = php.intval(req.query.start)
	return n > 0 and n or 0
end

-- Page links for a list of `total` entries, `per` per page, currently at `start`
-- (empty when everything fits on one page). Page 1 links to `base` itself.
function paging.pages(base, start, per, total)
	local pages = {}
	if total > per then
		for i = 0, (total - 1) // per do
			local s = i * per
			pages[#pages + 1] = {
				n = i + 1,
				url = s == 0 and base or base .. "?start=" .. s,
				current = start >= s and start < s + per,
			}
		end
	end
	return pages
end

return paging
