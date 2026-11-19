-- routes/town.lua :: OWNED BY F1 (town/explore/heal/character/map/babble). Stub from P2.
--
-- Routes to implement (PLAN.md "URL map"; legacy towns.php, explore.php, heal.php, index.php):
--   GET  /inn                 inn() confirm page          POST /inn            stay (name="submit") / cancel
--   GET  /shop                buy() item list
--   GET  /shop/buy/#id        buy2() confirm               POST /shop/buy/#id   buy3() (submit / cancel)
--   GET  /maps                maps() list
--   GET  /maps/buy/#id        maps2() confirm              POST /maps/buy/#id   maps3()
--   POST /travel/#id          travelto() (left nav "Travel To" buttons)
--   POST /move                move(); button name north|south|east|west (left nav compass)
--   POST /spell/#id           healspells() (right nav "Fast Spells" buttons)
--   GET  /character           showchar() popup, layout = "minimal"
--   GET  /character/#id       onlinechar() (Who's Online links)
--   GET  /map                 showmap() popup, layout = "minimal"
--   GET  /babble              babblebox() iframe page      POST /babble         post a message
--   GET  /ninja               302 to http://www.se7enet.com/img/shirtninja.jpg
-- Use auth.game as the guard on all of them. See docs/APP.md.
return function(r)
end
