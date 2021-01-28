<?php // app/Libs/Heal.php :: Handles stuff from the Quick Spells menu. (Healing spells only... other spells are handled in fight.php.)

function healspells($id)
{
    global $user, $link;
    
    $userspells = explode(",",$user["spells"]);
    $spellrow = quick('select * from {{ table }} where id=?', 'spells', [$id], $link)->fetch();

    
    // All the various ways to error out.
    $spell = false;
    foreach ($userspells as $a => $b) {
        if ($b == $id) { $spell = true; }
    }
    if ($spell != true) { display("You have not yet learned this spell. Please go back and try again.", "Error"); die(); }
    if ($spellrow["type"] != 1) { display("This is not a healing spell. Please go back and try again.", "Error"); die(); }
    if ($user["currentmp"] < $spellrow["mp"]) { display("You do not have enough Magic Points to cast this spell. Please go back and try again.", "Error"); die(); }
    if ($user["currentaction"] == "Fighting") { display("You cannot use the Quick Spells list during a fight. Please go back and select the Healing Spell you wish to use from the Spells box on the main fighting screen to continue.", "Error"); die(); }
    if ($user["currenthp"] == $user["maxhp"]) { display("Your Hit Points are already full. You don't need to use a Healing spell now.", "Error"); die(); }
    
    $newhp = $user["currenthp"] + $spellrow["attribute"];
    if ($user["maxhp"] < $newhp) { $spellrow["attribute"] = $user["maxhp"] - $user["currenthp"]; $newhp = $user["currenthp"] + $spellrow["attribute"]; }
    $newmp = $user["currentmp"] - $spellrow["mp"];
    
    $update = prepare('update {{ table }} set currenthp=?, currentmp=? where id=?', 'users', $link);
    execute($update, [$newhp, $newmp, $user->id]);
    
    display("You have cast the ".$spellrow["name"]." spell, and gained ".$spellrow["attribute"]." Hit Points. You can now continue <a href=\"index.php\">exploring</a>.", "Healing Spell");
}