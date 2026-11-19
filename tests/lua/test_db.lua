-- Unit tests for the dk.db binding (src/bind_db.c) beyond what every page exercises.
local T = {}

-- Statements with more parameters than a C function's guaranteed stack space (an UPDATE
-- of every users column has ~45).
function T.many_parameters()
	local n = 300
	local ones = {}
	for i = 1, n do ones[i] = 1 end
	local sql = "SELECT " .. ("? + "):rep(n - 1) .. "?"
	assert(dk.db:value(sql, table.unpack(ones)) == n, "value")
	assert(dk.db:first(sql .. " AS total", table.unpack(ones)).total == n, "first")
	assert(dk.db:query(sql .. " AS total", table.unpack(ones))[1].total == n, "query")
	local ok = pcall(dk.db.value, dk.db, "SELECT ?", 1, 2)
	assert(not ok, "a wrong parameter count is an error")
end

return T
