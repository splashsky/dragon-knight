<!doctype html>
<html lang="en">
<head>
    <title><?php echo $control["game_name"]; ?> Help</title>

    <link rel="stylesheet" href="resources/css/game.css">

    <style>
        section {
            margin-top: 2rem;
            margin-bottom: 2rem;
        }
    </style>
</head>

<body>
    <div class="mx-auto" style="width: 90%;">
        <a name="top"></a>
        <header class="my-8">
            <h1><?php echo $control['game_name']; ?> Guide</h1>
            [ <a href="index.php">Return to the game</a> ]
        </header>

        <section>
            <h2>Table of Contents</h2>
            <ul>
                <li><a href="#intro">Introduction</a></li>
                <li><a href="#classes">Character Classes</a></li>
                <li><a href="#difficulties">Difficulty Levels</a></li>
                <li><a href="#inTown">Playing The Game: In Town</a></li>
                <li><a href="#exploring">Playing The Game: Exploring & Fighting</a></li>
                <li><a href="#status">Playing The Game: Status Panels</a></li>
                <li><a href="#items">Items & Drops</a></li>
                <li><a href="#monsters">Monsters</a></li>
                <li><a href="#spells">Spells</a></li>
                <li><a href="#levels">Levels</a></li>
                <li><a href="#credits">Credits</a></li>
            </ul>
        </section>

        <div class="divider"></div>

        <a name="intro"></a>
        <section>
            <h2>Introduction</h2>

            <p>
                Firstly, I'd like to say thank you for playing my game. The <i>Dragon Knight</i> game engine is the result of several months of 
                planning, coding and testing. The original idea was to create a web-based tribute to the NES game, <i>Dragon 
                Warrior</i>. In its current iteration, only the underlying fighting system really resembles that game, as almost 
                everything else in DK has been made bigger and better. But you should still recognize bits and pieces as stemming
                from <i>Dragon Warrior</i> and other RPGs of old.
            </p>
            
            <p>
                This is the first game I've ever written, and it has definitely been a positive experience. It got difficult at
                times, admittedly, but it was still a lot of fun to write, and even more fun to play. And I hope to use this
                experience so that if I ever want to create another game it will be even better than this one.
            </p>

            <p>
                If you are a site administrator, and would like to install a copy of DK on your own server, you may visit the
                <a href="https://dragonknight.dev" target="_new">development site</a> for <i>Dragon Knight</i>. This page 
                includes the downloadable game souce code, as well as some other resources that developers and administrators may
                find valuable.
            </p>

            <p>
                Once again, thanks for playing!<br><br>
                <i>Jamin Seven</i><br>
                <i>Dragon Knight creator</i><br>
                <a href="http://www.se7enet.com" target="_new">My Homepage</a><br>
                <a href="https://dragonknight.dev" target="_new">Dragon Knight Homepage</a>
            </p>

            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="classes"></a>
        <section>
            <h2>Character Classes</h2>

            <p>
                There are three character classes in the game. The main differences between the classes are what spells you get
                access to, the speed with which you level up, and the amount of HP/MP/strength/dexterity you gain per level. Below
                is a basic outline of each of the character classes. For more detailed information about the characters, please
                view the Levels table at the bottom of this page. Also, note that the outline below refers to the stock class setup
                for the game. If your administrator has used his/her own class setup, this information may not be accurate.
            </p>

            <p>
                <h3><?php echo config('classes.mage.title'); ?></h3>
                <ul>
                    <li>Fast level-ups</li>
                    <li>High hit points</li>
                    <li>High magic points</li>
                    <li>Low strength</li>
                    <li>Low dexterity</li>
                    <li>5 heal spells</li>
                    <li>5 hurt spells</li>
                    <li>3 sleep spells</li>
                    <li>3 +defense spells</li>
                    <li>0 +attack spells</li>
                </ul>
            </p>

            <p>
                <h3><?php echo config('classes.warrior.title'); ?></h3>
                <ul>
                    <li>Medium level-ups</li>
                    <li>Medium hit points</li>
                    <li>Low magic points</li>
                    <li>High strength</li>
                    <li>Low dexterity</li>
                    <li>3 heal spells</li>
                    <li>3 hurt spells</li>
                    <li>2 sleep spells</li>
                    <li>3 +defense spells</li>
                    <li>3 +attack spells</li>
                </ul>
            </p>

            <p>
                <h3><?php echo config('classes.paladin.title'); ?></h3>
                <ul>
                    <li>Slow level-ups</li>
                    <li>Medium hit points</li>
                    <li>Medium magic points</li>
                    <li>Low strength</li>
                    <li>High dexterity</li>
                    <li>4 heal spells</li>
                    <li>4 hurt spells</li>
                    <li>3 sleep spells</li>
                    <li>2 +defense spells</li>
                    <li>2 +attack spells</li>
                </ul>
            </p>

            <div class="mt-4">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="difficulties"></a>
        <section>
            <h2>Difficulty Levels</h2>

            <p>
                <i><?php echo $control['game_name']; ?></i> includes the ability to play using one of three difficulty levels.
                All monster statistics in the game are set at a base number. However, using a difficulty multiplier, certain statistics
                are increased. The amount of hit points a monster has goes up, which means it will take longer to kill. But the amount
                of experience and gold you gain from killing it also goes up. So the game is a little bit harder, but it is also more
                rewarding. The following are the three difficulty levels and their statistic multiplier, which applies to the monster's
                HP, experience drop, and gold drop.
            </p>
            
            <ul class="my-8">
                <li><?php echo config('game.difficulties.easy.title'); ?>: <b><?php echo config('game.difficulties.easy.mod'); ?>x</b></li>
                <li><?php echo config('game.difficulties.normal.title'); ?>: <b><?php echo config('game.difficulties.normal.mod'); ?>x</b></li>
                <li><?php echo config('game.difficulties.hard.title'); ?>: <b><?php echo config('game.difficulties.hard.mod'); ?>x</b></li>
            </ul>

            <div>[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="inTown"></a>
        <section>
            <h2>Playing The Game: In Town</h2>

            <p>
                When you begin a new game, the first thing you see is the Town screen. Towns serve four primary functions: healing, buying items,
                buying maps, and displaying game information.
            </p>
            
            <p>
                To heal yourself, click the "Rest at the Inn" link at the top of the town screen. Each town's Inn has a different price - some towns
                are cheap, others are expensive. No matter what town you're in, the Inns always serve the same function: they restore your current
                hit points, magic points, and travel points to their maximum amounts. Out in the field, you are free to use healing spells to restore
                your hit points, but when you run low on magic points, the only way to restore them is at an Inn.
            </p>

            <p>
                Buying weapons and armor is accomplished through the appropriately-named "Buy Weapons/Armor" link. Not every item is available in
                every town, so in order to get the most powerful items, you'll need to explore some of the outer towns. Once you've clicked the link,
                you are presented with a list of items available in this town's store. To the left of each item is an icon that represents its type:
                weapon, armor or shield. The amount of attack/defense power, as well as the item's price, are displayed to the right of the item name.
                You'll notice that some items have a red asterisk (<span class="highlight">*</span>) next to their names. These are items that come
                with special attributes that modify other parts of your character profile. See the Items & Drops table at the bottom of this page for
                more information about special items.
            </p>

            <p>
                Maps are the third function in towns. Buying a map to a town places the town in your Fast Travel box in the left status panel. Once
                you've purchased a town's map, you can click its name from your Fast Travel box and you will jump to that town. Travelling this way
                costs travel points, though, and you'll only be able to visit towns if you have enough travel points.
            </p>

            <p>
                The final function in towns is displaying game information and statistics. This includes the latest news post made by the game
                administrator, a list of players who have been online recently, and the Babble Box.
            </p>

            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="exploring"></a>
        <section>
            <h2>Playing The Game: Exploring & Fighting</h2>

            <p>
                Once you're done in town, you are free to start exploring the world. Use the compass buttons on the left status panel to move around.
                The game world is basically a big square, divided into four quadrants. Each quadrant is <?php echo $control["game_size"]; ?> spaces
                square. The first town is usually located at [0, 0]. Click the North button from the first town, and now you'll be at [1N, 0E].
                Likewise, if you now click the West button, you'll be at [1N, 1W]. Monster levels increase with every 5 spaces you move outward 
                from [0N, 0E].
            </p>

            <p>
                While you're exploring, you will occasionally run into monsters. As in pretty much any other RPG game, you and the monster take turns
                hitting each other in an attempt to reduce each other's hit points to zero. Once you run into a monster, the Exploring screen changes 
                to the Fighting screen.
            </p>

            <p>
                When a fight begins, you'll see the monster's name and hit points, and the game will ask you for your first command. You then get to
                pick whether you want to fight, use a spell, or run away. Note, though, that sometimes the monster has the chance to hit you
                first.
            </p>

            <p>
                The Fight button is pretty straightforward: you attack the monster, and the amount of damage dealt is based on your attack power and
                the monster's armor. On top of that, there are two other things that can happen: an Excellent Hit, which doubles your total attack
                damage; and a monster dodge, which results in you doing no damage to the monster.
            </p>

            <p>
                The Spell button allows you to pick an available spell and cast it. See the Spells list at the bottom of this page for more information
                about spells.
            </p>

            <p>
                Finally, there is the Run button, which lets you run away from a fight if the monster is too powerful. Be warned, though: it is
                possible for the monster to block you from running and attack you. So if your hit points are low, you may fare better by staying
                around monsters that you know can't do much damage to you.
            </p>

            <p>
                Once you've had your turn, the monster also gets his turn. It is also possible for you to dodge the monster's attack and take no
                damage.
            </p>

            <p>
                The end result of a fight is either you or the monster being knocked down to zero hit points. If you win, the monster dies and will
                give you a certain amount of experience and gold. There is also a chance that the monster will drop an item, which you can put into
                one of the three inventory slots to give you extra points in your character profile. If you lose and die, half of your gold is taken
                away - however, you are given back a few hit points to help you make it back to town (for example, if you don't have enough gold to
                pay for an Inn, and need to kill a couple low-level monsters to get the money).
            </p>

            <p>
                When the fight is over, you can continue exploring until you find another monster to beat into submission.
            </p>

            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="status"></a>
        <section>
            <h2>Playing The Game: Status Panels</h2>

            <p>
                There are two status panels on the game screen: left and right.
            </p>

            <p>
                The left panel inclues your current location and play status (In Town, Exploring, Fighting), compass buttons for movement, and the
                Travel To list for jumping between towns. At the bottom of the left panel is also a list of game functions.
            </p>

            <p>
                The right panel displays some character statistics, your inventory, and quick spells.
            </p>

            <p>
                The Character section shows the most important character statistics. It also displays the status bars for your current hit points,
                magic points and travel points. These status bars are colored either green, yellow or red depending on your current amount of each
                stat. There is also a link to pop up your list of extended statistics, which shows more detailed character information.
            </p>

            <p>
                The Fast Spells section lists any Heal spells you've learned. You may use these links any time you are in town or exploring to cast
                the heal spell. These may not be used during fights, however - you have to use the Spells box on the fight screen for that.
            </p>
            
            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="items"></a>
        <section>
            <h2>Items & Drops</h2>
            <a href="help.php?with=items">Click here</a> for the Items & Drops spoiler page.
        </section>

        <a name="monsters"></a>
        <section>
            <h2>Monsters</h2>
            <a href="help.php?with=monsters">Click here</a> for the Monsters spoiler page.
        </section>

        <a name="spells"></a>
        <section>
            <h2>Spells</h2>
            <a href="help.php?with=spells">Click here</a> for the Spells spoiler page.
        </section>

        <a name="levels"></a>
        <section>
            <h2>Levels</h2>
            <a href="help.php?with=levels">Click here</a> for the Levels spoiler page.

            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>

        <div class="divider"></div>

        <a name="credits"></a>
        <section>
            <h2>Credits</h2>

            <p>
                These credits are from the original game. We've preserved them in order to cement the legacy of
                this project. If your name is on the list below, we salute you!
            </p>

            <p>
                Major props go to a few people on the PHP manual site, for help with various chunks of code. The specific people are listed in the source code.
            </p>

            <p>
                Super monkey love goes to Enix and the developers of <i>Dragon Warrior</i>. If it weren't for you guys, my game never would have been made.
            </p>

            <p>
                Mega props go to Dalez from GameFAQs for his DW3 experience chart, which was where I got my experience levels from.
            </p>

            <div style="margin-top: 2rem;">
                <p>
                    Mad crazy ninja love goes to the following people for help and support throughout the development process...
                </p>

                <p>
                    <h3>Ideas... (whether they got used or not)</h3>
                    <ul>
                        <li>kushet</li>
                        <li>lghtning</li>
                        <li>Ebolamonkey3000</li>
                        <li>Crimson Scythe</li>
                        <li>SilDeath</li>
                    </ul>
                </p>

                <p>
                    <h3>Beta Testing... (usernames from original DK launch)</h3>
                    <ul>
                        <li>Ebolamonkey3000</li>
                        <li>lisi</li>
                        <li>Junglist</li>
                        <li>Crimson Scythe</li>
                        <li>Sk8erpunk69</li>
                        <li>lghtning</li>
                        <li>kushet</li>
                        <li>SilDeath</li>
                        <li>lowrider4life</li>
                        <li>dubiin</li>
                        <li>Sam Wise The Great</li>
                    </ul>
                </p>

                <p>
                    Apologies and lots of happy naked love to anyone I forgot.
                </p>

                <p>
                    And of course, thanks to <b>you</b> for playing my game!
                </p>
            </div>
        </section>

        <section>
            <p>
                Please visit the following sites for more information:<br>
                <a href="http://www.se7enet.com" target="_new">Se7enet</a> (Jamin's homepage)<br>
                <a href="https://dragonknight.dev" target="_new">Dragon Knight Dev Site</a>
            </p>

            <p>
                All original coding and graphics for the <i>Dragon Knight</i> game engine are copyright &copy; 2003-2005 by Jamin Seven.
            </p>
            
            <div class="mt-8">[ <a href="#top">Top</a> ]</div>
        </section>
    </div>

    <footer class="copyright flex items-center" style="width: 90%;">
        <div class="w-1/3 text-center">Powered by <a href="https://dragonknight.dev" target="_new">Dragon Knight</a></div>
        <div class="w-1/3 text-center">&copy; <a href="https://surf.gg">Surf</a> 2020</div>
        <div class="w-1/3 text-center">Version <?php echo config('general.version'); echo config('general.build'); ?></div>
    </footer>
</body>
</html>