<?php

/**
 * The Fight library contains functions that facilitate combat in the game.
 */

/**
 * The master fight function. An overweight behemoth that handles combat.
 */
function fight()
{
    global $user, $control, $link, $db;

    if ($user['action'] != 'Fighting') { redirect('index.php'); }

    $page = [];
    $dead = false;
    
    $page['magicList'] = '';
    $userSpells = explode(',', $user['spells']);

    $spells = query('select id, name from {{ table }}', 'spells', $link);
    foreach ($spells->fetchAll() as $spellId => $spellName) {
        foreach ($userSpells as $knownId) {
            if ($knownId === $spellId) {
                $page['magicList'] .= "<option value=\"{$spellId}\">{$spellName}</option>";
            }
        }
    }

    if ($page['magicList'] == '') { $page['magiclist'] = '<option value="0">None</option>'; }

    $firstStrikeChance = 1;

    // First, check to see if we need to pick a monster.
    $fight = $db->quick('select * from {{ table }} where user_id=?', 'fights', [$user['id']]);
    dd($fight);
    $fight = $fight->fetch();

    if ($user["currentfight"] == 1) {
        if ($user["latitude"] < 0) { $user["latitude"] *= -1; } // Equalize negatives.
        if ($user["longitude"] < 0) { $user["longitude"] *= -1; } // Ditto.
        $maxlevel = floor(max($user["latitude"]+5, $user["longitude"]+5) / 5); // One mlevel per five spaces.
        if ($maxlevel < 1) { $maxlevel = 1; }
        $minlevel = $maxlevel - 2;
        if ($minlevel < 1) { $minlevel = 1; }
        
        // Pick a monster.
        $monster = prepare('select * from {{ table }} where level >= ? and level <= ? order by rand() limit 1', 'monsters', $link);
        $monster = execute($monster, [$minlevel, $maxlevel])->fetch();

        $user["currentmonster"] = $monster["id"];
        $user["currentmonsterhp"] = rand((($monster["maxhp"] / 5) * 4),$monster["maxhp"]);
        if ($user["difficulty"] == 2) { $user["currentmonsterhp"] = ceil($user["currentmonsterhp"] * $control["diff2mod"]); }
        if ($user["difficulty"] == 3) { $user["currentmonsterhp"] = ceil($user["currentmonsterhp"] * $control["diff3mod"]); }
        $user["currentmonstersleep"] = 0;
        $user["currentmonsterimmune"] = $monster["immune"];
        
        $firstStrikeChance = rand(1,10) + ceil(sqrt($user["dexterity"]));
        if ($firstStrikeChance > (rand(1,7) + ceil(sqrt($monster["maxdam"])))) { $firstStrikeChance = 1; } else { $firstStrikeChance = 0; }
        
        unset($monster);
    }
    
    // Next, get the monster statistics.
    $monster = prepare('select * from {{ table }} where id = ?', 'monsters', $link);
    $monster = execute($monster, [$user['currentmonster']])->fetch();

    $pagearray["monstername"] = $monster["name"];
    
    // Do run stuff.
    if (isset($_POST["run"])) {

        $chancetorun = rand(4,10) + ceil(sqrt($user["dexterity"]));
        if ($chancetorun > (rand(1,5) + ceil(sqrt($monster["maxdam"])))) { $chancetorun = 1; } else { $chancetorun = 0; }
        
        if ($chancetorun == 0) { 
            $pagearray["yourturn"] = "You tried to run away, but were blocked in front!<br /><br />";
            $pagearray["monsterhp"] = "Monster's HP: " . $user["currentmonsterhp"] . "<br /><br />";
            $pagearray["monsterturn"] = "";
            if ($user["currentmonstersleep"] != 0) { // Check to wake up.
                $chancetowake = rand(1,15);
                if ($chancetowake > $user["currentmonstersleep"]) {
                    $user["currentmonstersleep"] = 0;
                    $pagearray["monsterturn"] .= "The monster has woken up.<br />";
                } else {
                    $pagearray["monsterturn"] .= "The monster is still asleep.<br />";
                }
            }
            if ($user["currentmonstersleep"] == 0) { // Only do this if the monster is awake.
                $tohit = ceil(rand($monster["maxdam"]*.5,$monster["maxdam"]));
                if ($user["difficulty"] == 2) { $tohit = ceil($tohit * $control["diff2mod"]); }
                if ($user["difficulty"] == 3) { $tohit = ceil($tohit * $control["diff3mod"]); }
                $toblock = ceil(rand($user["defensepower"]*.75,$user["defensepower"])/4);
                $tododge = rand(1,150);

                if ($tododge <= sqrt($user["dexterity"])) {
                    $tohit = 0; $pagearray["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                    $persondamage = 0;
                } else {
                    $persondamage = $tohit - $toblock;
                    if ($persondamage < 1) { $persondamage = 1; }
                    if ($user["currentuberdefense"] != 0) {
                        $persondamage -= ceil($persondamage * ($user["currentuberdefense"]/100));
                    }
                    if ($persondamage < 1) { $persondamage = 1; }
                }

                $pagearray["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
                $user["currenthp"] -= $persondamage;

                if ($user["currenthp"] <= 0) {
                    $newgold = ceil($user["gold"]/2);
                    $newhp = ceil($user["maxhp"]/4);

                    $query = "update {{ table }} set currenthp=?, currentaction='In Town', currentmonster='0', currentmonsterhp='0', currentmonstersleep='0', currentmonsterimmune='0', currentfight='0', latitude='0', longitude='0', gold=? where id=?";
                    quick($query, 'users', [$newhp, $newgold, $user['id']], $link);

                    $dead = 1;
                }
            }
        }

        quick("update {{ table }} set currentaction='Exploring' where id=?", 'users', [$user['id']], $link);
        
        redirect('index.php');
        
    // Do fight stuff.
    } elseif (isset($_POST["fight"])) {
        
        // Your turn.
        $pagearray["yourturn"] = "";
        $tohit = ceil(rand($user["attackpower"]*.75,$user["attackpower"])/3);
        $toexcellent = rand(1,150);
        if ($toexcellent <= sqrt($user["strength"])) { $tohit *= 2; $pagearray["yourturn"] .= "Excellent hit!<br />"; }
        $toblock = ceil(rand($monster["armor"]*.75,$monster["armor"])/3);        
        $tododge = rand(1,200);
        if ($tododge <= sqrt($monster["armor"])) { 
            $tohit = 0; $pagearray["yourturn"] .= "The monster is dodging. No damage has been scored.<br />"; 
            $monsterdamage = 0;
        } else {
            $monsterdamage = $tohit - $toblock;
            if ($monsterdamage < 1) { $monsterdamage = 1; }
            if ($user["currentuberdamage"] != 0) {
                $monsterdamage += ceil($monsterdamage * ($user["currentuberdamage"]/100));
            }
        }
        $pagearray["yourturn"] .= "You attack the monster for $monsterdamage damage.<br /><br />";
        $user["currentmonsterhp"] -= $monsterdamage;
        $pagearray["monsterhp"] = "Monster's HP: " . $user["currentmonsterhp"] . "<br /><br />";
        if ($user["currentmonsterhp"] <= 0) {
            quick("update {{ table }} set currentmonsterhp='0' where id=?", 'users', [$user['id']], $link);

            redirect('index.php?do=victory');
        }
        
        // Monster's turn.
        $pagearray["monsterturn"] = "";
        if ($user["currentmonstersleep"] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $user["currentmonstersleep"]) {
                $user["currentmonstersleep"] = 0;
                $pagearray["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $pagearray["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($user["currentmonstersleep"] == 0) { // Only do this if the monster is awake.
            $tohit = ceil(rand($monster["maxdam"]*.5,$monster["maxdam"]));
            if ($user["difficulty"] == 2) { $tohit = ceil($tohit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $tohit = ceil($tohit * $control["diff3mod"]); }
            $toblock = ceil(rand($user["defensepower"]*.75,$user["defensepower"])/4);
            $tododge = rand(1,150);
            if ($tododge <= sqrt($user["dexterity"])) {
                $tohit = 0; $pagearray["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                $persondamage = $tohit - $toblock;
                if ($persondamage < 1) { $persondamage = 1; }
                if ($user["currentuberdefense"] != 0) {
                    $persondamage -= ceil($persondamage * ($user["currentuberdefense"]/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $pagearray["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user["currenthp"] -= $persondamage;
            if ($user["currenthp"] <= 0) {
                $newgold = ceil($user["gold"]/2);
                $newhp = ceil($user["maxhp"]/4);

                $query = "update {{ table }} set currenthp=?, currentaction='In Town', currentmonster='0', currentmonsterhp='0', currentmonstersleep='0', currentmonsterimmune='0', currentfight='0', latitude='0', longitude='0', gold=? where id=?";
                quick($query, 'users', [$newhp, $newgold, $user['id']], $link);

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
        if ($user["currentmp"] < $newspellrow["mp"]) { display("You do not have enough Magic Points to cast this spell. Please go back and try again.", "Error"); die(); }
        
        if ($newspellrow["type"] == 1) { // Heal spell.
            $newhp = $user["currenthp"] + $newspellrow["attribute"];
            if ($user["maxhp"] < $newhp) { $newspellrow["attribute"] = $user["maxhp"] - $user["currenthp"]; $newhp = $user["currenthp"] + $newspellrow["attribute"]; }
            $user["currenthp"] = $newhp;
            $user["currentmp"] -= $newspellrow["mp"];
            $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and gained ".$newspellrow["attribute"]." Hit Points.<br /><br />";
        } elseif ($newspellrow["type"] == 2) { // Hurt spell.
            if ($user["currentmonsterimmune"] == 0) {
                $monsterdamage = rand((($newspellrow["attribute"]/6)*5), $newspellrow["attribute"]);
                $user["currentmonsterhp"] -= $monsterdamage;
                $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell for $monsterdamage damage.<br /><br />";
            } else {
                $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, but the monster is immune to it.<br /><br />";
            }
            $user["currentmp"] -= $newspellrow["mp"];
        } elseif ($newspellrow["type"] == 3) { // Sleep spell.
            if ($user["currentmonsterimmune"] != 2) {
                $user["currentmonstersleep"] = $newspellrow["attribute"];
                $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell. The monster is asleep.<br /><br />";
            } else {
                $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, but the monster is immune to it.<br /><br />";
            }
            $user["currentmp"] -= $newspellrow["mp"];
        } elseif ($newspellrow["type"] == 4) { // +Damage spell.
            $user["currentuberdamage"] = $newspellrow["attribute"];
            $user["currentmp"] -= $newspellrow["mp"];
            $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and will gain ".$newspellrow["attribute"]."% damage until the end of this fight.<br /><br />";
        } elseif ($newspellrow["type"] == 5) { // +Defense spell.
            $user["currentuberdefense"] = $newspellrow["attribute"];
            $user["currentmp"] -= $newspellrow["mp"];
            $pagearray["yourturn"] = "You have cast the ".$newspellrow["name"]." spell, and will gain ".$newspellrow["attribute"]."% defense until the end of this fight.<br /><br />";            
        }
            
        $pagearray["monsterhp"] = "Monster's HP: " . $user["currentmonsterhp"] . "<br /><br />";

        if ($user["currentmonsterhp"] <= 0) {
            $query = "update {{ table }} set currentmonsterhp='0', currenthp=?, currentmp=? WHERE id=?";
            quick($query, 'users', [$user['currenthp'], $user['currentmp'], $user['id']], $link);
            
            redirect('index.php?do=victory');
        }
        
        // Monster's turn.
        $pagearray["monsterturn"] = "";
        if ($user["currentmonstersleep"] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $user["currentmonstersleep"]) {
                $user["currentmonstersleep"] = 0;
                $pagearray["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $pagearray["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($user["currentmonstersleep"] == 0) { // Only do this if the monster is awake.
            $tohit = ceil(rand($monster["maxdam"]*.5,$monster["maxdam"]));
            if ($user["difficulty"] == 2) { $tohit = ceil($tohit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $tohit = ceil($tohit * $control["diff3mod"]); }
            $toblock = ceil(rand($user["defensepower"]*.75,$user["defensepower"])/4);
            $tododge = rand(1,150);
            if ($tododge <= sqrt($user["dexterity"])) {
                $tohit = 0; $pagearray["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                if ($tohit <= $toblock) { $tohit = $toblock + 1; }
                $persondamage = $tohit - $toblock;
                if ($user["currentuberdefense"] != 0) {
                    $persondamage -= ceil($persondamage * ($user["currentuberdefense"]/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $pagearray["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user["currenthp"] -= $persondamage;

            if ($user["currenthp"] <= 0) {
                $newgold = ceil($user["gold"]/2);
                $newhp = ceil($user["maxhp"]/4);

                $query = "update {{ table }} set currenthp=?, currentaction='In Town', currentmonster='0', currentmonsterhp='0', currentmonstersleep='0', currentmonsterimmune='0', currentfight='0', latitude='0', longitude='0', gold=? where id=?";
                quick($query, 'users', [$newhp, $newgold, $user['id']], $link);
                
                $dead = 1;
            }
        }
    
    // Do a monster's turn if person lost the chance to swing first. Serves him right!
    } elseif ( $firstStrikeChance == 0 ) {
        $pagearray["yourturn"] = "The monster attacks before you are ready!<br /><br />";
        $pagearray["monsterhp"] = "Monster's HP: " . $user["currentmonsterhp"] . "<br /><br />";
        $pagearray["monsterturn"] = "";
        if ($user["currentmonstersleep"] != 0) { // Check to wake up.
            $chancetowake = rand(1,15);
            if ($chancetowake > $user["currentmonstersleep"]) {
                $user["currentmonstersleep"] = 0;
                $pagearray["monsterturn"] .= "The monster has woken up.<br />";
            } else {
                $pagearray["monsterturn"] .= "The monster is still asleep.<br />";
            }
        }
        if ($user["currentmonstersleep"] == 0) { // Only do this if the monster is awake.
            $tohit = ceil(rand($monster["maxdam"]*.5,$monster["maxdam"]));
            if ($user["difficulty"] == 2) { $tohit = ceil($tohit * $control["diff2mod"]); }
            if ($user["difficulty"] == 3) { $tohit = ceil($tohit * $control["diff3mod"]); }
            $toblock = ceil(rand($user["defensepower"]*.75,$user["defensepower"])/4);
            $tododge = rand(1,150);
            if ($tododge <= sqrt($user["dexterity"])) {
                $tohit = 0; $pagearray["monsterturn"] .= "You dodge the monster's attack. No damage has been scored.<br />";
                $persondamage = 0;
            } else {
                $persondamage = $tohit - $toblock;
                if ($persondamage < 1) { $persondamage = 1; }
                if ($user["currentuberdefense"] != 0) {
                    $persondamage -= ceil($persondamage * ($user["currentuberdefense"]/100));
                }
                if ($persondamage < 1) { $persondamage = 1; }
            }
            $pagearray["monsterturn"] .= "The monster attacks you for $persondamage damage.<br /><br />";
            $user["currenthp"] -= $persondamage;
            if ($user["currenthp"] <= 0) {
                $newgold = ceil($user["gold"]/2);
                $newhp = ceil($user["maxhp"]/4);

                $query = "update {{ table }} set currenthp=?, currentaction='In Town', currentmonster='0', currentmonsterhp='0', currentmonstersleep='0', currentmonsterimmune='0', currentfight='0', latitude='0', longitude='0', gold=? where id=?";
                quick($query, 'users', [$newhp, $newgold, $user['id']], $link);

                $dead = 1;
            }
        }

    } else {
        $pagearray["yourturn"] = "";
        $pagearray["monsterhp"] = "Monster's HP: " . $user["currentmonsterhp"] . "<br /><br />";
        $pagearray["monsterturn"] = "";
    }
    
    $newmonster = $user["currentmonster"];

    $newmonsterhp = $user["currentmonsterhp"];
    $newmonstersleep = $user["currentmonstersleep"];
    $newmonsterimmune = $user["currentmonsterimmune"];
    $newuberdamage = $user["currentuberdamage"];
    $newuberdefense = $user["currentuberdefense"];
    $newfight = $user["currentfight"] + 1;
    $newhp = $user["currenthp"];
    $newmp = $user["currentmp"];    
    
if ($dead != 1) { 
$pagearray["command"] = <<<END
Command?<br /><br />
<form action="index.php?do=fight" method="post">
    <button type="submit" name="fight" class="button mb-4">Fight</button>

    <div>
        <select name="userspell" class="select-input"><option value="0">Choose One</option>$magiclist</select> 
        <button type="submit" name="spell" class="button mb-4">Cast</button>
    </div>

    <button type="submit" name="run" class="button mb-4">Run</button>
</form>
END;
    $query = "update {{ table }} set currentaction='Fighting', currenthp=?, currentmp=?, currentfight=?, currentmonster=?, currentmonsterhp=?, currentmonstersleep=?, currentmonsterimmune=?, currentuberdamage=?, currentuberdefense=? WHERE id=?";
    quick($query, 'users', [
        $newhp,
        $newmp,
        $newfight,
        $newmonster,
        $newmonsterhp,
        $newmonstersleep,
        $newmonsterimmune,
        $newuberdamage,
        $newuberdefense,
        $user['id']
    ], $link);
} else {
    $pagearray["command"] = "<b>You have died.</b><br /><br />As a consequence, you've lost half of your gold. However, you have been given back a portion of your hit points to continue your journey.<br /><br />You may now continue back to <a href=\"index.php\">town</a>, and we hope you fair better next time.";
}
    
    // Finalize page and display it.
    $template = gettemplate("fight");
    $page = parsetemplate($template,$pagearray);
    
    display($page, "Fighting");
}

/**
 * Handles the user's victory in a fight.
 */
function victory()
{
    global $user, $control, $link;
    
    if ($user["currentmonsterhp"] != 0) { header("Location: index.php?do=fight"); die(); }
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
            $newhp = $user["maxhp"] + $levelrow[$user["class"]."_hp"];
            $newmp = $user["maxmp"] + $levelrow[$user["class"]."_mp"];
            $newtp = $user["maxtp"] + $levelrow[$user["class"]."_tp"];
            $newstrength = $user["strength"] + $levelrow[$user["class"]."_strength"];
            $newdexterity = $user["dexterity"] + $levelrow[$user["class"]."_dexterity"];
            $newattack = $user["attackpower"] + $levelrow[$user["class"]."_strength"];
            $newdefense = $user["defensepower"] + $levelrow[$user["class"]."_dexterity"];
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
            $newhp = $user["maxhp"];
            $newmp = $user["maxmp"];
            $newtp = $user["maxtp"];
            $newstrength = $user["strength"];
            $newdexterity = $user["dexterity"];
            $newattack = $user["attackpower"];
            $newdefense = $user["defensepower"];
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
        $user['id']
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
            if ($old1[0] == "strength") { $user["attackpower"] -= $old1[1]; }
            if ($old1[0] == "dexterity") { $user["defensepower"] -= $old1[1]; }
            if ($old2[0] == "strength") { $user["attackpower"] -= $old2[1]; }
            if ($old2[0] == "dexterity") { $user["defensepower"] -= $old2[1]; }
            
            $user[$new1[0]] += $new1[1];
            $user[$new2[0]] += $new2[1];
            if ($new1[0] == "strength") { $user["attackpower"] += $new1[1]; }
            if ($new1[0] == "dexterity") { $user["defensepower"] += $new1[1]; }
            if ($new2[0] == "strength") { $user["attackpower"] += $new2[1]; }
            if ($new2[0] == "dexterity") { $user["defensepower"] += $new2[1]; }
            
            if ($user["currenthp"] > $user["maxhp"]) { $user["currenthp"] = $user["maxhp"]; }
            if ($user["currentmp"] > $user["maxmp"]) { $user["currentmp"] = $user["maxmp"]; }
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
                $user["attackpower"],
                $user["defensepower"],
                $user["currenthp"],
                $user["currentmp"],
                $user["currenttp"],
                $user['id']
            ];
            quick($query, 'users', $data, $link);
        } else {
            $new1 = explode(",",$droprow["attribute1"]);
            if ($droprow["attribute2"] != "X") { $new2 = explode(",",$droprow["attribute2"]); } else { $new2 = array(0=>"maxhp",1=>0); }
            
            $user[$new1[0]] += $new1[1];
            $user[$new2[0]] += $new2[1];
            if ($new1[0] == "strength") { $user["attackpower"] += $new1[1]; }
            if ($new1[0] == "dexterity") { $user["defensepower"] += $new1[1]; }
            if ($new2[0] == "strength") { $user["attackpower"] += $new2[1]; }
            if ($new2[0] == "dexterity") { $user["defensepower"] += $new2[1]; }
            
            $newname = addslashes($droprow["name"]);
            $s = $_POST['slot'];
            $query = "update {{ table }} set slot{$s}name=?, slot{$s}id=?, {$new1[0]}=?, {$new2[0]}=?, attackpower=?, defensepower=?, dropcode='0' WHERE id=?";
            $data = [
                $newname,
                $droprow['id'],
                $user[$new1[0]],
                $user[$new2[0]],
                $user["attackpower"],
                $user["defensepower"],
                $user['id']
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