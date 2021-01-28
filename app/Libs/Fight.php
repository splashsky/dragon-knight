<?php

/**
 * The Fight library contains functions that facilitate combat in the game.
 */

function endFight(int $id)
{
    global $db;

    $db->quick('delete from {{ table }} where user_id=?', 'fights', [$id]);
}

function initiateFight(Fight &$fight, $user)
{
    if (! $fight->fightExistsFor($user->id)) {
        // Find a random monster in our area.
        $monster = findNewMonster($user->latitude, $user->longitude, $mod);

        // Set up fight data to be put into the database.
        $fight = $fight->create([
            'user_id' => $user->id,
            'monster_id' => $monster['id'],
            'monster_name' => $monster['name'],
            'monster_hp' => $monster['hp'],
            'monster_damage' => $monster['damage'] * $mod,
            'monster_armor' => $monster['armor'] * $mod,
            'monster_immune' => $monster['immune']
        ]);
    } else {
        $fight->getByUserId($user->id);
    }

    return $fight;
}

function getUserSpellList(string $userSpells = ''): array
{
    global $db;

    if ($userSpells == '0' || empty($userSpells)) { return []; }
    $known = explode(',', $userSpells);
    $spells = $db->query('SELECT * FROM {{ table }}', 'spells');
    $spellData = [];

    foreach ($spells->fetchAll() as $spell) {
        foreach ($known as $id) {
            if ($spell['id'] === $id) {
                $spellData[$id] = $spell;
            }
        }
    }

    return $spellData;
}

function generateSpellList(array $spells = []): string
{
    if (empty($spells)) { return '<option value="0">None</option>'; }

    $list = '';
    foreach ($spells as $id => $spell) { $list .= "<option value=\"{$id}\">{$spell['name']}</option>"; }
    return $list;
}

function findNewMonster(int $latitude, int $longitude, $mod = 1): array
{
    global $db;

    // Get our absolute distance from the center of the world.
    $lat = abs($latitude);
    $lon = abs($longitude);

    // Determine the highest level of monster we can find. 1 monster level for every 5 spaces.
    $maxLevel = floor(max($latitude + 5, $longitude + 5) / 5);
    $minLevel = $maxLevel - 2;
    if ($maxLevel < 1) { $maxLevel = 1; }
    if ($minLevel < 1) { $minLevel = 1; }

    // Pick a random monster within our level limit.
    $monster = $db->prepare('SELECT * FROM {{ table }} WHERE level >= ? AND level <= ? ORDER BY rand() LIMIT 1', 'monsters');
    $monster->execute([$minLevel, $maxLevel]);
    $monster = $monster->fetch();

    // Randomize the monster's health a little bit.
    $monster['hp'] = rand((($monster['hp'] / 5) * 4), $monster['hp']) * $mod;

    return $monster;
}

function firstStrikeChance(int $userDex, int $monsterDam): int
{
    $firstStrikeChance = rand(1, 10) + ceil(sqrt($userDex));
    return $firstStrikeChance > (rand(1, 7) + ceil(sqrt($monsterDam))) ? 1 : 0;
}

function chanceToRun(int $userDex, int $monsterDam): int
{   
    $chanceToRun = rand(4, 10) + ceil(sqrt($userDex));
    return $chanceToRun > (rand(1, 5) + ceil(sqrt($monsterDam))) ? 1 : 0;
}

function attemptToRun($user, Fight $fight): bool
{
    if (chanceToRun($user['dexterity'], $fight->monster_damage) == 0) {
        return false;
    }

    return true;
}

/**
 * The master fight function. An overweight behemoth that handles combat.
 */
function fight()
{
    global $user, $control, $link, $db;

    if ($user['action'] != 'Fighting') { redirect('index.php'); }

    $userObj = new User($db);
    $userObj->getById($user->id);

    $page = [];
    $dead = false;
    
    // Get the user's difficulty mod.
    $mod = config("game.difficulties.{$user['difficulty']}")['mod'];
    
    // Get the user's spells and their data, and generate an HTML <option> list for their spells.
    $userSpells = getUserSpellList($user['spells']);
    $page['magicList'] = generateSpellList($userSpells);

    $fight = new Fight($db);
    $fight = initiateFight($fight);

    $firstStrikeChance = firstStrikeChance($user['dexterity'], $fight->monster_damage);
        
    $page['monsterName'] = $fight->monster_name;
    
    // Do run stuff.
    if (isset($_POST['run'])) {
        if (chanceToRun($user['dexterity'], $monster['damage']) == 0) { 
            $page["yourturn"] = "You tried to run away, but were blocked!<br /><br />";
            $page["monsterhp"] = "Monster's HP: " . $fight->monster_hp . "<br /><br />";
            $page["monsterturn"] = "";

            if ($fight->isMonsterAsleep()) {
                if ($fight->doesMonsterWakeUp()) {
                    $page["monsterturn"] .= "The monster has woken up.<br />";
                } else {
                    $page["monsterturn"] .= "The monster is still asleep.<br />";
                }
            }

            // Perform this if the monster is not asleep.
            if ($fight['monster_sleep'] == 0) {
                $toHit = ceil(rand($monster['damage'] * 0.5, $monster['damage']) * $mod);
                $toBlock = ceil(rand($user['defense'] * 0.75, $user['defense']) / 4);
                $toDodge = rand(1, 150);

                if ($toDodge <= sqrt($user['dexterity'])) {
                    $toHit = 0;
                    $page["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                    $persondamage = 0;
                } else {
                    $persondamage = $toHit - $toBlock;
                    if ($fight['uber_defense'] != 0) { $persondamage -= ceil($persondamage * ($fight['uber_defense'] / 100)); }
                    if ($persondamage < 1) { $persondamage = 1; }
                }

                $page["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
                $user['hp'] -= $persondamage;

                // The player freakin' died.
                if ($user['hp'] <= 0) {
                    $user->gold = ceil($user->gold / 2);
                    $user['hp'] = ceil($user['max_hp'] / 4);
                    $user['action'] = 'In Town';
                    $user->latitude = 0;
                    $user->longitude = 0;

                    endFight($user->id);
                    
                    
                    $userObj->update($user);

                    $dead = 1;
                }
            }
        }

        quick("update {{ table }} set currentaction='Exploring' where id=?", 'users', [$user->id], $link);
        
        redirect('index.php');
        
    // Do fight stuff.
    } elseif (isset($_POST["fight"])) {
        
        // Your turn.
        $page["yourturn"] = "";
        $toHit = ceil(rand($user['attack']*.75,$user['attack'])/3);
        $toexcellent = rand(1,150);
        if ($toexcellent <= sqrt($user["strength"])) { $toHit *= 2; $page["yourturn"] .= "Excellent hit!<br />"; }
        $toBlock = ceil(rand($fight['monster_armor']*.75,$fight['monster_armor'])/3);        
        $toDodge = rand(1,200);
        if ($toDodge <= sqrt($fight['monster_armor'])) { 
            $toHit = 0; $page["yourturn"] .= "The monster is dodging. No damage has been scored.<br />"; 
            $monsterdamage = 0;
        } else {
            $monsterdamage = $toHit - $toBlock;
            if ($monsterdamage < 1) { $monsterdamage = 1; }
            if ($fight['uber_damage'] != 0) {
                $monsterdamage += ceil($monsterdamage * ($fight['uber_damage']/100));
            }
        }
        $page["yourturn"] .= "You attack the monster for $monsterdamage damage.<br /><br />";
        $fight['uber_damage'] -= $monsterdamage;
        $page["monsterhp"] = "Monster's HP: " . $fight['monster_hp'] . "<br /><br />";
        if ($fight['uber_damage'] <= 0) {
            endFight($user->id);
            redirect('index.php?do=victory');
        }
        
        // Monster's turn.
        $page["monsterturn"] = "";
        if ($fight['monster_sleep'] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $fight['monster_sleep']) {
                $fight['monster_sleep'] = 0;
                $page["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $page["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($fight['monster_sleep'] == 0) { // Only do this if the monster is awake.
            $toHit = ceil(rand($monster['damage'] * 0.5,$monster['damage']));
            if ($user["difficulty"] == 2) { $toHit = ceil($toHit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $toHit = ceil($toHit * $control["diff3mod"]); }
            $toBlock = ceil(rand($user['defense']*.75,$user['defense'])/4);
            $toDodge = rand(1,150);
            if ($toDodge <= sqrt($user['dexterity'])) {
                $toHit = 0; $page["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                $persondamage = $toHit - $toBlock;
                if ($persondamage < 1) { $persondamage = 1; }
                if ($fight['uber_defense'] != 0) {
                    $persondamage -= ceil($persondamage * ($fight['uber_defense']/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $page["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user['hp'] -= $persondamage;

            // The player freakin' died.
            if ($user['hp'] <= 0) {
                $user->gold = ceil($user->gold / 2);
                $user['hp'] = ceil($user['max_hp'] / 4);
                $user['action'] = 'In Town';
                $user->latitude = 0;
                $user->longitude = 0;

                endFight($user->id);
                
                $userObj = new User($db);
                $userObj->getById($user->id);
                $userObj->update($user);

                $dead = 1;
            }
        }
        
    // Do spell stuff.
    } elseif (isset($_POST["spell"])) {
        
        // Your turn.
        $pickedspell = $_POST["userspell"];
        if ($pickedspell == 0) { display("You must select a spell first. Please go back and try again.", "Error"); die(); }
        
        $newSpell = prepare('select * from {{ table }} where id=?', 'spells', $link);
        $newspellrow = execute($newSpell, [$pickedspell])->fetch();
        
        $spell = false;
        foreach($userspells as $a => $b) {
            if ($b == $pickedspell) { $spell = true; }
        }
        if ($spell != true) { display("You have not yet learned this spell. Please go back and try again.", "Error"); die(); }
        if ($user['mp'] < $newspellrow["mp"]) { display("You do not have enough Magic Points to cast this spell. Please go back and try again.", "Error"); die(); }
        
        if ($newspellrow["type"] == 1) { // Heal spell.
            $newhp = $user['hp'] + $newspellrow['power'];
            if ($user['max_hp'] < $newhp) { $newspellrow['power'] = $user['max_hp'] - $user['hp']; $newhp = $user['hp'] + $newspellrow['power']; }
            $user['hp'] = $newhp;
            $user['mp'] -= $newspellrow["mp"];
            $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and gained ".$newspellrow['power']." Hit Points.<br /><br />";
        } elseif ($newspellrow["type"] == 2) { // Hurt spell.
            if ($fight['monster_immune'] == 0) {
                $monsterdamage = rand((($newspellrow['power']/6)*5), $newspellrow['power']);
                $fight['uber_damage'] -= $monsterdamage;
                $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell for $monsterdamage damage.<br /><br />";
            } else {
                $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, but the monster is immune to it.<br /><br />";
            }
            $user['mp'] -= $newspellrow["mp"];
        } elseif ($newspellrow["type"] == 3) { // Sleep spell.
            if ($fight['monster_immune'] != 2) {
                $fight['monster_sleep'] = $newspellrow['power'];
                $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell. The monster is asleep.<br /><br />";
            } else {
                $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, but the monster is immune to it.<br /><br />";
            }
            $user['mp'] -= $newspellrow["mp"];
        } elseif ($newspellrow["type"] == 4) { // +Damage spell.
            $fight['uber_damage'] = $newspellrow['power'];
            $user['mp'] -= $newspellrow["mp"];
            $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and will gain ".$newspellrow['power']."% damage until the end of this fight.<br /><br />";
        } elseif ($newspellrow["type"] == 5) { // +Defense spell.
            $fight['uber_defense'] = $newspellrow['power'];
            $user['mp'] -= $newspellrow["mp"];
            $page["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and will gain ".$newspellrow['power']."% defense until the end of this fight.<br /><br />";            
        }
            
        $page["monsterhp"] = "Monster's HP: " . $fight['monster_hp'] . "<br /><br />";

        if ($fight['uber_damage'] <= 0) {
            endFight($user->id);

            $db->quick('update {{ table }} set hp=?, mp=? where id=?', 'users', [$user['hp'], $user['mp'], $user->id]);
            
            redirect('index.php?do=victory');
        }
        
        // Monster's turn.
        $page["monsterturn"] = "";
        if ($fight['monster_sleep'] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $fight['monster_sleep']) {
                $fight['monster_sleep'] = 0;
                $page["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $page["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($fight['monster_sleep'] == 0) { // Only do this if the monster is awake.
            $toHit = ceil(rand($monster['damage']*.5,$monster['damage']));
            if ($user["difficulty"] == 2) { $toHit = ceil($toHit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $toHit = ceil($toHit * $control["diff3mod"]); }
            $toBlock = ceil(rand($user['defense']*.75,$user['defense'])/4);
            $toDodge = rand(1,150);
            if ($toDodge <= sqrt($user['dexterity'])) {
                $toHit = 0; $page["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                if ($toHit <= $toBlock) { $toHit = $toBlock + 1; }
                $persondamage = $toHit - $toBlock;
                if ($fight['uber_defense'] != 0) {
                    $persondamage -= ceil($persondamage * ($fight['uber_defense']/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $page["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user['hp'] -= $persondamage;

            // The player freakin' died.
            if ($user['hp'] <= 0) {
                $user->gold = ceil($user->gold / 2);
                $user['hp'] = ceil($user['max_hp'] / 4);
                $user['action'] = 'In Town';
                $user->latitude = 0;
                $user->longitude = 0;

                endFight($user->id);
                
                $userObj = new User($db);
                $userObj->getById($user->id);
                $userObj->update($user);

                $dead = 1;
            }
        }
    
    // Do a monster's turn if person lost the chance to swing first. Serves him right!
    } elseif ( $firstStrikeChance == 0 ) {
        $page["yourturn"] = "The monster attacks before you are ready!<br /><br />";
        $page["monsterhp"] = "Monster's HP: " . $fight['monster_hp'] . "<br /><br />";
        $page["monsterturn"] = "";
        if ($fight['monster_sleep'] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $fight['monster_sleep']) {
                $fight['monster_sleep'] = 0;
                $page["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $page["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($fight['monster_sleep'] == 0) { // Only do this if the monster is awake.
            $toHit = ceil(rand($monster['damage']*.5,$monster['damage']));
            if ($user["difficulty"] == 2) { $toHit = ceil($toHit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $toHit = ceil($toHit * $control["diff3mod"]); }
            $toBlock = ceil(rand($user['defense']*.75,$user['defense'])/4);
            $toDodge = rand(1,150);
            if ($toDodge <= sqrt($user['dexterity'])) {
                $toHit = 0; $page["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                $persondamage = $toHit - $toBlock;
                if ($persondamage < 1) { $persondamage = 1; }
                if ($fight['uber_defense'] != 0) {
                    $persondamage -= ceil($persondamage * ($fight['uber_defense']/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $page["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user['hp'] -= $persondamage;

            // The player freakin' died.
            if ($user['hp'] <= 0) {
                $user->gold = ceil($user->gold / 2);
                $user['hp'] = ceil($user['max_hp'] / 4);
                $user['action'] = 'In Town';
                $user->latitude = 0;
                $user->longitude = 0;

                endFight($user->id);
                
                $userObj = new User($db);
                $userObj->getById($user->id);
                $userObj->update($user);

                $dead = 1;
            }
        }

    } else {
        $page["yourturn"] = "";
        $page["monsterhp"] = "Monster's HP: " . $fight['monster_hp'] . "<br /><br />";
        $page["monsterturn"] = "";
    }
    
if ($dead != 1) { 
$page["command"] = <<<END
Command?<br /><br />
<form action="index.php?do=fight" method="post">
    <button type="submit" name="fight" class="button mb-4">Fight</button>

    <div>
        <select name="userspell" class="select-input"><option value="0">Choose One</option>{$page['magicList']}</select> 
        <button type="submit" name="spell" class="button mb-4">Cast</button>
    </div>

    <button type="submit" name="run" class="button mb-4">Run</button>
</form>
END;
    $updateUser = 'update {{ table }} set action=\'Fighting\', hp=?, mp=? where id=?';
    $db->quick($updateUser, 'users', [$user['hp'], $user['mp'], $user->id]);

    $updateFight = 'update {{ table }} set monster_hp=?, monster_damage=?, monster_armor=?, monster_sleep=?, monster_immune=?, uber_damage=?, uber_defense=? where user_id=?';
    $db->quick($updateFight, 'fights', [
        $fight['monster_hp'],
        $fight['monster_damage'],
        $fight['monster_armor'],
        $fight['monster_sleep'],
        $fight['monster_immune'],
        $fight['uber_damage'],
        $fight['uber_defense'],
        $user->id
    ]);
} else {
    $page["command"] = "<b>You have died.</b><br /><br />As a consequence, you've lost half of your gold. However, you have been given back a portion of your hit points to continue your journey.<br /><br />You may now continue back to <a href=\"index.php\">town</a>, and we hope you fair better next time.";
}
    
    // Finalize page and display it.
    $template = gettemplate("fight");
    $page = parsetemplate($template,$page);
    
    display($page, "Fighting");
}

/**
 * Handles the user's victory in a fight.
 */
function victory()
{
    global $user, $control, $link;
    
    //if ($fight['uber_damage'] != 0) { header("Location: index.php?do=fight"); die(); }
    if ($user["currentfight"] == 0) { header("Location: index.php"); die(); }
    
    $monster = prepare('select * from {{ table }} where id = ?', 'monsters', $link);
    $monster = execute($monster, [$user['currentmonster']])->fetch();
    
    $exp = rand((($monster["maxexp"]/6)*5),$monster["maxexp"]);
    if ($exp < 1) { $exp = 1; }
    if ($user["difficulty"] == 2) { $exp = ceil($exp * $control["diff2mod"]); }
    if ($user["difficulty"] == 3) { $exp = ceil($exp * $control["diff3mod"]); }
    if ($user["expbonus"] != 0) { $exp += ceil(($user["expbonus"]/100)*$exp); }
    $gold = rand((($monster["maxgold"]/6)*5),$monster["maxgold"]);
    if ($gold < 1) { $gold = 1; }
    if ($user["difficulty"] == 2) { $gold = ceil($gold * $control["diff2mod"]); }
    if ($user["difficulty"] == 3) { $gold = ceil($gold * $control["diff3mod"]); }
    if ($user["goldbonus"] != 0) { $gold += ceil(($user["goldbonus"]/100)*$exp); }
    if ($user["experience"] + $exp < 16777215) { $newexp = $user["experience"] + $exp; $warnexp = ""; } else { $newexp = $user["experience"]; $exp = 0; $warnexp = "You have maxed out your experience points."; }
    if ($user["gold"] + $gold < 16777215) { $newgold = $user["gold"] + $gold; $warngold = ""; } else { $newgold = $user["gold"]; $gold = 0; $warngold = "You have maxed out your experience points."; }
    
    $expQuery = prepare("select * from {{ table }} where id=?", 'levels', $link);
    $levelrow = execute($expQuery, [$user['level'] + 1])->fetch();
    
    if ($user["level"] < 100) {
        if ($newexp >= $levelrow[$user["class"]."_exp"]) {
            $newhp = $user['max_hp'] + $levelrow[$user["class"]."_hp"];
            $newmp = $user["maxmp"] + $levelrow[$user["class"]."_mp"];
            $newtp = $user["maxtp"] + $levelrow[$user["class"]."_tp"];
            $newstrength = $user["strength"] + $levelrow[$user["class"]."_strength"];
            $newdexterity = $user['dexterity'] + $levelrow[$user["class"]."_dexterity"];
            $newattack = $user['attack'] + $levelrow[$user["class"]."_strength"];
            $newdefense = $user['defense'] + $levelrow[$user["class"]."_dexterity"];
            $newlevel = $levelrow["id"];
            
            if ($levelrow[$user["class"]."_spells"] != 0) {
                $userspells = $user["spells"] . ",".$levelrow[$user["class"]."_spells"];
                $newspell = "spells='$userspells',";
                $spelltext = "You have learned a new spell.<br />";
            } else { $spelltext = ""; $newspell=""; }
            
            $page = "Congratulations. You have defeated the ".$monster["name"].".<br />You gain $exp experience. $warnexp <br />You gain $gold gold. $warngold <br /><br /><b>You have gained a level!</b><br /><br />You gain ".$levelrow[$user["class"]."_hp"]." hit points.<br />You gain ".$levelrow[$user["class"]."_mp"]." magic points.<br />You gain ".$levelrow[$user["class"]."_tp"]." travel points.<br />You gain ".$levelrow[$user["class"]."_strength"]." strength.<br />You gain ".$levelrow[$user["class"]."_dexterity"]." dexterity.<br />$spelltext<br />You can now continue <a href=\"index.php\">exploring</a>.";
            $title = "Courage and Wit have served thee well!";
            $dropcode = "";
        } else {
            $newhp = $user['max_hp'];
            $newmp = $user["maxmp"];
            $newtp = $user["maxtp"];
            $newstrength = $user["strength"];
            $newdexterity = $user['dexterity'];
            $newattack = $user['attack'];
            $newdefense = $user['defense'];
            $newlevel = $user["level"];
            $newspell = "";
            $page = "Congratulations. You have defeated the ".$monster["name"].".<br />You gain $exp experience. $warnexp <br />You gain $gold gold. $warngold <br /><br />";
            
            if (rand(1, 30) == 1) {
                $drop = prepare('select * from {{ table }} where mlevel <= ? order by rand() limit 1', 'drops', $link);
                $droprow = execute($drop, [$monster['level']])->fetch();
                $dropcode = "dropcode='".$droprow["id"]."',";
                $page .= "This monster has dropped an item. <a href=\"index.php?do=drop\">Click here</a> to reveal and equip the item, or you may also move on and continue <a href=\"index.php\">exploring</a>.";
            } else { 
                $dropcode = "";
                $page .= "You can now continue <a href=\"index.php\">exploring</a>.";
            }

            $title = "Victory!";
        }
    }

    $query = "update {{ table }} set currentaction='Exploring', level=?, maxhp=?, maxmp=?, maxtp=?, strength=?, dexterity=?, attackpower=?, defensepower=?, {$newspell} currentfight='0', currentmonster='0', currentmonsterhp='0', currentmonstersleep='0', currentmonsterimmune='0', currentuberdamage='0', currentuberdefense='0', {$dropcode} experience=?, gold=? WHERE id=?";
    quick($query, 'users', [
        $newlevel,
        $newhp,
        $newmp,
        $newtp,
        $newstrength,
        $newdexterity,
        $newattack,
        $newdefense,
        $newexp,
        $newgold,
        $user->id
    ], $link);

    display($page, $title);
}

function drop()
{
    global $user, $link;
    
    if ($user["dropcode"] == 0) { redirect('index.php'); }
    
    $drop = prepare('select * from {{ table }} where id=?', 'drops', $link);
    $droprow = execute($drop, [$user['dropcode']])->fetch();
    
    if (isset($_POST["submit"])) {
        $slot = $_POST["slot"];
        
        if ($slot == 0) { display("Please go back and select an inventory slot to continue.","Error"); }
        
        if ($user["slot".$slot."id"] != 0) {
            
            $slot = prepare('select * from {{ table }} where id=?', 'drops', $link);
            $slotrow = execute($slot, [$user["slot{$slot}id"]])->fetch();
            
            $old1 = explode(",",$slotrow["attribute1"]);
            if ($slotrow["attribute2"] != "X") { $old2 = explode(",",$slotrow["attribute2"]); } else { $old2 = array(0=>"maxhp",1=>0); }
            $new1 = explode(",",$droprow["attribute1"]);
            if ($droprow["attribute2"] != "X") { $new2 = explode(",",$droprow["attribute2"]); } else { $new2 = array(0=>"maxhp",1=>0); }
            
            $user[$old1[0]] -= $old1[1];
            $user[$old2[0]] -= $old2[1];
            if ($old1[0] == "strength") { $user['attack'] -= $old1[1]; }
            if ($old1[0] == "dexterity") { $user['defense'] -= $old1[1]; }
            if ($old2[0] == "strength") { $user['attack'] -= $old2[1]; }
            if ($old2[0] == "dexterity") { $user['defense'] -= $old2[1]; }
            
            $user[$new1[0]] += $new1[1];
            $user[$new2[0]] += $new2[1];
            if ($new1[0] == "strength") { $user['attack'] += $new1[1]; }
            if ($new1[0] == "dexterity") { $user['defense'] += $new1[1]; }
            if ($new2[0] == "strength") { $user['attack'] += $new2[1]; }
            if ($new2[0] == "dexterity") { $user['defense'] += $new2[1]; }
            
            if ($user['hp'] > $user['max_hp']) { $user['hp'] = $user['max_hp']; }
            if ($user['mp'] > $user["maxmp"]) { $user['mp'] = $user["maxmp"]; }
            if ($user["currenttp"] > $user["maxtp"]) { $user["currenttp"] = $user["maxtp"]; }
            
            $newname = addslashes($droprow["name"]);

            $s = $_POST['slot'];
            $query = "update {{ table }} set slot{$s}name=?, slot{$s}id=?, {$old1[0]}=?, {$old2[0]}=?, {$new1[0]}=?, {$new2[0]}=?, attackpower=?, defensepower=?, currenthp=?, currentmp=?, currenttp=?, dropcode='0' WHERE id=?";
            $data = [
                $newname,
                $droprow['id'],
                $user[$old1[0]],
                $user[$old2[0]],
                $user[$new1[0]],
                $user[$new2[0]],
                $user['attack'],
                $user['defense'],
                $user['hp'],
                $user['mp'],
                $user["currenttp"],
                $user->id
            ];
            quick($query, 'users', $data, $link);
        } else {
            $new1 = explode(",",$droprow["attribute1"]);
            if ($droprow["attribute2"] != "X") { $new2 = explode(",",$droprow["attribute2"]); } else { $new2 = array(0=>"maxhp",1=>0); }
            
            $user[$new1[0]] += $new1[1];
            $user[$new2[0]] += $new2[1];
            if ($new1[0] == "strength") { $user['attack'] += $new1[1]; }
            if ($new1[0] == "dexterity") { $user['defense'] += $new1[1]; }
            if ($new2[0] == "strength") { $user['attack'] += $new2[1]; }
            if ($new2[0] == "dexterity") { $user['defense'] += $new2[1]; }
            
            $newname = addslashes($droprow["name"]);
            $s = $_POST['slot'];
            $query = "update {{ table }} set slot{$s}name=?, slot{$s}id=?, {$new1[0]}=?, {$new2[0]}=?, attackpower=?, defensepower=?, dropcode='0' WHERE id=?";
            $data = [
                $newname,
                $droprow['id'],
                $user[$new1[0]],
                $user[$new2[0]],
                $user['attack'],
                $user['defense'],
                $user->id
            ];
            quick($query, 'users', $data, $link);
        }

        $page = "The item has been equipped. You can now continue <a href=\"index.php\">exploring</a>.";
        display($page, "Item Drop");
    }
    
    $attributearray = [
        "maxhp"=>"Max HP",
        "maxmp"=>"Max MP",
        "maxtp"=>"Max TP",
        "defensepower"=>"Defense Power",
        "attackpower"=>"Attack Power",
        "strength"=>"Strength",
        "dexterity"=>"Dexterity",
        "expbonus"=>"Experience Bonus",
        "goldbonus"=>"Gold Bonus"
    ];
    
    $page = "The monster dropped the following item: <b>{$droprow["name"]}</b><br /><br />";
    $page .= "This item has the following attribute(s):<br />";
    
    $attribute1 = explode(",",$droprow["attribute1"]);
    $page .= $attributearray[$attribute1[0]];
    if ($attribute1[1] > 0) { $page .= " +" . $attribute1[1] . "<br />"; } else { $page .= $attribute1[1] . "<br />"; }
    
    if ($droprow["attribute2"] != "X") { 
        $attribute2 = explode(",",$droprow["attribute2"]);
        $page .= $attributearray[$attribute2[0]];
        if ($attribute2[1] > 0) { $page .= " +" . $attribute2[1] . "<br />"; } else { $page .= $attribute2[1] . "<br />"; }
    }
    
    $page .= "<br />Select an inventory slot from the list below to equip this item. If the inventory slot is already full, the old item will be discarded.";
    $page .= "<form action=\"index.php?do=drop\" method=\"post\"><select name=\"slot\"><option value=\"0\">Choose One</option><option value=\"1\">Slot 1: ".$user["slot1name"]."</option><option value=\"2\">Slot 2: ".$user["slot2name"]."</option><option value=\"3\">Slot 3: ".$user["slot3name"]."</option></select> <input type=\"submit\" name=\"submit\" value=\"Submit\" /></form>";
    $page .= "You may also choose to just continue <a href=\"index.php\">exploring</a> and give up this item.";
    
    display($page, "Item Drop");
}
    

function dead()
{
    $page = "<b>You have died.</b><br /><br />As a consequence, you've lost half of your gold. However, you have been given back a portion of your hit points to continue your journey.<br /><br />You may now continue back to <a href=\"index.php\">town</a>, and we hope you fair better next time.";
}