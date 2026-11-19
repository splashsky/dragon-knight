-- cli/check.lua :: the Lua part of `dk check` (run without a database after every module
-- and template compiled): validates the content files (app/content/).
local load = require("lib.content.load")
local schema = require("lib.content.schema")

return {
	run = function()
		local all = load.all()
		for _, e in ipairs(all.errors) do io.stderr:write("FAIL content ", e, "\n") end
		if #all.errors > 0 then return 1 end
		local parts = {}
		for _, name in ipairs(schema.KINDS) do
			parts[#parts + 1] = #all.kinds[name].entities .. " " .. name
		end
		print("content: ok (" .. table.concat(parts, ", ") .. ")")
		return 0
	end,
}
