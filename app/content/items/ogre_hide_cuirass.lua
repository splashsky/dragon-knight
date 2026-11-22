-- app/content/items/ogre_hide_cuirass.lua :: the Ogre-hide Cuirass (a thick hide cuirass that adds to maximum HP).
return {
	name = "Ogre-hide Cuirass",
	lore = [[
Hide from an ogre's back, cured for a year in brine and then cut into a cuirass with
the grain running down the spine. Hunters in the hills near Hambry trade them as
trophies, and the tanners say the stuff keeps the wearer on his feet a little longer
than he should be. It stinks for a month after the first wetting, and nobody has yet
found a way to stop that.]],
	icon = "ogre_hide_cuirass",
	category = "armor",
	price = 2800,
	defense = 105,
	modifiers = { { kind = "stat", stat = "maxhp", amount = 30 } },
}
