-- tools/world.lua :: installed by tools/world.sh as cli/check.lua in a scratch copy of app/,
-- so `dk check` runs it in the project's own Lua (with no database): writes the world's data
-- module (world.lua) from world generator v1, and the world's picture drawn from that data
-- (world.svg) and its frame (world-frame.svg), and its relief (world-relief.bin: the heights and the water, for the World
-- Map's WebGL sky), into the directory DK_WORLD_OUT names.
local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

return {
	run = function()
		local dir = assert(os.getenv("DK_WORLD_OUT"), "DK_WORLD_OUT: where to write the world")
		local generator = require("lib.terrain.generator_v1")
		local data = generator.text()
		write(dir .. "/world.lua", data)
		package.loaded["lib.terrain.world"] = assert(load(data, "=world.lua", "t", {}))()
		package.loaded["lib.terrain"] = nil
		write(dir .. "/world.svg", require("lib.terrain.picture").svg())
		write(dir .. "/world-frame.svg", require("lib.terrain.picture").frame())
		write(dir .. "/world-relief.bin", require("lib.terrain").relief())
		print(("world generator %s (seed 0x%X): wrote world.lua, world.svg, world-frame.svg and world-relief.bin"):format(generator.VERSION,
			generator.SEED))
		return 0
	end,
}
