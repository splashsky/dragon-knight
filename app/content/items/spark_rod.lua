-- app/content/items/spark_rod.lua :: the Spark Rod (a rod that casts Spark, the Mage's cheap spell).
return {
	name = "Spark Rod",
	description = "A short rod of copper and bone. Equipped, it casts Spark in a fight without costing MP, one charge at a time. Rest at an inn to recharge it.",
	lore = [[
Roma's copper workers make these for the Mages who have outgrown the wand and cannot yet
afford anything grander. A rod takes a Spark, and a Spark is the spell every apprentice
singes a finger on. Most Mages in Roma own one, and most keep it tucked in a belt where
the neighbours can see it.]],
	category = "weapon",
	price = 180,
	attack = 3,
	casts = "spark",                -- the spell it casts (app/content/spells/spark.lua)
	charges = 8,                    -- charges when full
}
