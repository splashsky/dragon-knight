-- weather_lines.lua :: the words of the weather (docs/APP.md "Clock and weather"). Plain
-- tables: lib/weather.lua picks among a list's variants by a hash of the place and time,
-- never by dice, so a reload shows the same line. Add variants to any list. In a line,
-- "{direction}" becomes a compass direction ("south-east").
return {
	-- names: the Location box and its tooltip
	sky = {
		clear = "Clear", sun = "Sunny", heat = "Heat", overcast = "Overcast", fog = "Fog",
		drizzle = "Drizzle", rain = "Rain", downpour = "Downpour", thunderstorm = "Thunderstorm",
		snow = "Snow", blizzard = "Blizzard",
	},
	ground = { dry = "Dry ground", wet = "Wet ground", mud = "Mud", snow = "Snow on the ground", ice = "Ice" },
	time = { dawn = "Dawn", day = "Day", dusk = "Dusk", night = "Night" },
	storm = { squall = "Squall", storm = "Storm", great = "Great storm" },
	-- clockwise from north (weather.lua turns a bearing into one of them)
	directions = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" },

	-- The weather as it is (weather.describe): a sentence for the sky ("sky:time" before
	-- "sky"), one for the ground (none when dry), the storm overhead and a storm near.
	standing = {
		sky = {
			clear = { "The sky is clear.", "Not a cloud is in the sky." },
			["clear:dawn"] = { "The sky pales, clear and cold.", "A clear dawn spreads over the land." },
			["clear:dusk"] = { "The clear sky reddens in the west.", "The evening is clear and still." },
			["clear:night"] = { "Stars crowd the clear night sky.", "The night is clear, and the moon is bright." },
			sun = { "The sun shines warm on the road.", "Sunlight lies bright across the land." },
			heat = { "The heat presses down, thick and still.", "The air shimmers in the heat.",
				"Heat rises off the baked earth." },
			overcast = { "Grey clouds cover the sky.", "A low, grey sky hangs over everything." },
			["overcast:night"] = { "Clouds hide the moon and stars.", "The night is dark under thick clouds." },
			fog = { "Fog lies thick about you.", "You can barely see a stone's throw through the fog." },
			drizzle = { "A fine drizzle is falling.", "A thin rain mists the air." },
			rain = { "Rain falls steadily.", "The rain drums on your hood." },
			downpour = { "Rain pours down in sheets.", "The rain hammers down so hard you can hardly see." },
			thunderstorm = { "Thunder cracks overhead as the rain lashes down.", "Lightning splits the sky, and the rain pours." },
			snow = { "Snow is falling softly.", "Snowflakes drift down around you." },
			blizzard = { "A blizzard howls about you.", "Snow drives sideways on a screaming wind." },
		},
		ground = {
			wet = { "The ground is wet.", "Puddles gather underfoot." },
			mud = { "The ground is thick mud.", "Your boots sink into the mud." },
			snow = { "Snow covers the ground.", "Snow crunches underfoot." },
			ice = { "The ground is slick with ice.", "Ice glazes the frozen ground." },
		},
		storm = {
			squall = { "A squall is passing over.", "You are caught in a squall." },
			storm = { "You are in the middle of a storm.", "A storm is passing over you." },
			great = { "A great storm rages all around you.", "You are deep inside a great storm." },
		},
		near = { "Thunder rumbles to the {direction}.", "Dark clouds gather to the {direction}.",
			"A storm is moving to the {direction}." },
	},

	-- What changed since the minute before (weather.change): "from>to" before "to".
	change = {
		sky = {
			clear = { "The sky clears.", "The clouds part, and the sky clears." },
			["fog>clear"] = { "The fog lifts.", "The fog thins and drifts away." },
			["rain>clear"] = { "The rain stops, and the sky clears." },
			sun = { "The sun comes out.", "Sunlight breaks through." },
			["fog>sun"] = { "The sun burns the fog away." },
			heat = { "The heat builds.", "The air grows hot and heavy." },
			overcast = { "Clouds roll in.", "The sky turns grey." },
			["drizzle>overcast"] = { "The drizzle stops.", "The drizzle lets up." },
			["rain>overcast"] = { "The rain stops.", "The rain lets up under a grey sky." },
			fog = { "Fog creeps in.", "A fog rises and closes about you." },
			drizzle = { "A light drizzle begins.", "A fine rain starts to fall." },
			["rain>drizzle"] = { "The rain eases to a drizzle." },
			rain = { "Rain begins to fall.", "It starts to rain." },
			["drizzle>rain"] = { "The drizzle thickens into rain." },
			["downpour>rain"] = { "The downpour eases." },
			["thunderstorm>rain"] = { "The thunder moves off, but the rain goes on." },
			downpour = { "The heavens open.", "Rain comes down in sheets." },
			["thunderstorm>downpour"] = { "The thunder stops, but the rain pours on." },
			thunderstorm = { "Thunder cracks overhead!", "Lightning splits the sky!" },
			snow = { "Snow begins to fall.", "The first flakes of snow drift down." },
			["blizzard>snow"] = { "The blizzard dies down to a gentle snow." },
			blizzard = { "A blizzard comes howling in.", "The wind rises, and the snow turns to a blizzard." },
		},
		ground = {
			dry = { "The ground dries.", "The ground is dry again." },
			["mud>dry"] = { "The mud dries.", "The mud firms up underfoot." },
			["snow>dry"] = { "The snow melts away." },
			["ice>dry"] = { "The ice melts away." },
			wet = { "The ground grows wet.", "Puddles start to form." },
			mud = { "The ground turns to mud.", "The puddles spread into mud." },
			snow = { "Snow settles on the ground.", "The ground turns white." },
			ice = { "The snow freezes to ice.", "The snow underfoot hardens into ice." },
		},
		time = {
			dawn = { "Dawn breaks.", "The sky pales in the east." },
			day = { "The sun is up.", "Full day comes." },
			dusk = { "Dusk falls.", "The light begins to fade." },
			night = { "Night falls.", "Darkness settles over the land." },
		},
		storm_arrives = {
			squall = { "A squall sweeps over you.", "A squall catches you." },
			storm = { "The storm is upon you.", "The storm breaks over you." },
			great = { "The great storm swallows the sky.", "The great storm is upon you." },
		},
		storm_leaves = {
			squall = { "The squall passes.", "The squall blows over." },
			storm = { "The storm moves on.", "The storm passes." },
			great = { "The great storm rolls away at last.", "The great storm passes on." },
		},
		near_comes = { "Thunder rumbles to the {direction}.", "Storm clouds gather to the {direction}." },
		near_goes = { "The storm to the {direction} moves away.", "The thunder to the {direction} fades." },
	},

	-- Different weather on the next tile (weather.edge), by its sky.
	edge = {
		clear = { "The sky is clear just to the {direction}." },
		sun = { "The sun shines just to the {direction}." },
		heat = { "Heat shimmers just to the {direction}." },
		overcast = { "Grey clouds hang just to the {direction}." },
		fog = { "A wall of fog stands just to the {direction}." },
		drizzle = { "A drizzle falls just to the {direction}." },
		rain = { "Rain is falling just to the {direction}." },
		downpour = { "Rain pours down just to the {direction}." },
		thunderstorm = { "Thunder crashes just to the {direction}." },
		snow = { "Snow is falling just to the {direction}." },
		blizzard = { "A blizzard howls just to the {direction}." },
	},
}
