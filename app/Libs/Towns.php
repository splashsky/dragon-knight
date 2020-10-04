<?php

/**
 * This script contains the functions that operate town features such as
 * the inn, shop, and more.
 */

 /**
  * Handle either displaying the inn or resting at the inn. Resting at the inn
  * sets all meters back to full.
  */
function inn()
{
    global $user, $link;

    $townrow = getTown($user['latitude'], $user['longitude'], $link);
    
    if ($user["gold"] < $townrow["innprice"]) { display("You do not have enough gold to stay at this Inn tonight. <br><br> You may return to <a href=\"index.php\">town</a>, or use the direction buttons on the left to start exploring.", "Inn"); die(); }
    
    if (isset($_POST["submit"])) {
        $newgold = $user["gold"] - $townrow["innprice"];
        $rested = prepare('update {{ table }} set gold=?, currenthp=?, currentmp=?, currenttp=? where id=?', 'users', $link);
        execute($rested, [$newgold, $user['maxhp'], $user['maxmp'], $user['maxtp'], $user['id']]);
        $page = "You wake up feeling refreshed and ready for action.<br /><br />You may return to <a href=\"index.php\">town</a>, or use the direction buttons on the left to start exploring.";
    } elseif (isset($_POST["cancel"])) {
        redirect('index.php');
    } else {
        $page = gettemplate('inn');
        $page = parsetemplate($page, $townrow);
    }
    
    display($page, 'Inn');
}

/**
 * Handles displaying the list of items for sale in a given town.
 */
function buy()
{
    global $user, $link;
    
    $townrow = getTown($user['latitude'], $user['longitude'], $link);
    
    $itemslist = explode(",", $townrow["itemslist"]);
    $querystring = "";
    foreach($itemslist as $id) {
        $querystring .= "id='{$id}' OR ";
    }
    $querystring = rtrim($querystring, " OR ");
    
    $query = query("select * from {{ table }} where {$querystring}", 'items');
    $page = "Buying weapons will increase your Attack Power. Buying armor and shields will increase your Defense Power.<br /><br />Click an item name to purchase it.<br /><br />The following items are available at this town:<br /><br />\n";
    $page .= "<table width=\"80%\">\n";
    foreach ($query->fetchAll() as $itemsrow) {
        if ($itemsrow["type"] == 1) { $attrib = "Attack Power:"; } else  { $attrib = "Defense Power:"; }
        $page .= "<tr><td width=\"4%\">";
        if ($itemsrow["type"] == 1) { $page .= "<img src=\"resources/images/icon_weapon.gif\" alt=\"weapon\" /></td>"; }
        if ($itemsrow["type"] == 2) { $page .= "<img src=\"resources/images/icon_armor.gif\" alt=\"armor\" /></td>"; }
        if ($itemsrow["type"] == 3) { $page .= "<img src=\"resources/images/icon_shield.gif\" alt=\"shield\" /></td>"; }
        if ($user["weaponid"] == $itemsrow["id"] || $user["armorid"] == $itemsrow["id"] || $user["shieldid"] == $itemsrow["id"]) {
            $page .= "<td width=\"32%\"><span class=\"light\">".$itemsrow["name"]."</span></td><td width=\"32%\"><span class=\"light\">$attrib ".$itemsrow["attribute"]."</span></td><td width=\"32%\"><span class=\"light\">Already purchased</span></td></tr>\n";
        } else {
            if ($itemsrow["special"] != "X") { $specialdot = "<span class=\"highlight\">&#42;</span>"; } else { $specialdot = ""; }
            $page .= "<td width=\"32%\"><b><a href=\"index.php?do=buy2:".$itemsrow["id"]."\">".$itemsrow["name"]."</a>$specialdot</b></td><td width=\"32%\">$attrib <b>".$itemsrow["attribute"]."</b></td><td width=\"32%\">Price: <b>".$itemsrow["buycost"]." gold</b></td></tr>\n";
        }
    }
    $page .= "</table><br />\n";
    $page .= "If you've changed your mind, you may also return back to <a href=\"index.php\">town</a>.\n";
    
    display($page, 'Buy Items');
}

/**
 * Confirms whether the user is sure about buying the item they selected.
 */
function buy2($id)
{
    global $user, $link;
    

    $townrow = getTown($user['latitude'], $user['longitude'], $link);
    $townitems = explode(",",$townrow["itemslist"]);

    if (! in_array($id, $townitems)) { display("Cheat attempt detected.<br /><br />Get a life, loser.", "Error"); }
    
    $itemsrow = quick('select * from {{ table }} where id=?', 'items', [$id], $link)->fetch();

    if ($user["gold"] < $itemsrow["buycost"]) { display("You do not have enough gold to buy this item.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=buy\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Items"); die(); }
    
    if ($itemsrow["type"] == 1) {
        if ($user["weaponid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['weaponid']], $link)->fetch();
            $page = "If you are buying the ".$itemsrow["name"].", then I will buy your ".$itemsrow2["name"]." for ".ceil($itemsrow2["buycost"]/2)." gold. Is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        } else {
            $page = "You are buying the ".$itemsrow["name"].", is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        }
    } elseif ($itemsrow["type"] == 2) {
        if ($user["armorid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['armorid']], $link)->fetch();
            $page = "If you are buying the ".$itemsrow["name"].", then I will buy your ".$itemsrow2["name"]." for ".ceil($itemsrow2["buycost"]/2)." gold. Is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        } else {
            $page = "You are buying the ".$itemsrow["name"].", is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        }
    } elseif ($itemsrow["type"] == 3) {
        if ($user["shieldid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['shieldid']], $link)->fetch();
            $page = "If you are buying the ".$itemsrow["name"].", then I will buy your ".$itemsrow2["name"]." for ".ceil($itemsrow2["buycost"]/2)." gold. Is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        } else {
            $page = "You are buying the ".$itemsrow["name"].", is that ok?<br /><br /><form action=\"index.php?do=buy3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
        }
    }
    
    display($page, 'Buy Items');
}

/**
 * Handles updating the user's profile with their newly purchased item!
 */
function buy3($id)
{
    if (isset($_POST["cancel"])) { redirect('index.php'); }
    
    global $user, $link;
    
    $townrow = getTown($user['latitude'], $user['longitude'], $link);
    $townitems = explode(",",$townrow["itemslist"]);

    if (! in_array($id, $townitems)) { display("Cheat attempt detected.<br /><br />Get a life, loser.", "Error"); }
    
    $itemsrow = quick('select * from {{ table }} where id=?', 'items', [$id], $link)->fetch();
    
    if ($user["gold"] < $itemsrow["buycost"]) { display("You do not have enough gold to buy this item.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=buy\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Items"); die(); }
    
    if ($itemsrow["type"] == 1) { // weapon
    	// Check if they already have an item in the slot.
        if ($user["weaponid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['weaponid']], $link)->fetch();
        } else {
            $itemsrow2 = array("attribute"=>0,"buycost"=>0,"special"=>"X");
        }
        
        // Special item fields.
        $specialchange1 = "";
        $specialchange2 = "";
        if ($itemsrow["special"] != "X") {
            $special = explode(",",$itemsrow["special"]);
            $tochange = $special[0];
            $user[$tochange] = $user[$tochange] + $special[1];
            $specialchange1 = "$tochange='".$user[$tochange]."',";
            if ($tochange == "strength") { $user["attackpower"] += $special[1]; }
            if ($tochange == "dexterity") { $user["defensepower"] += $special[1]; }
        }
        if ($itemsrow2["special"] != "X") {
            $special2 = explode(",",$itemsrow2["special"]);
            $tochange2 = $special2[0];
            $user[$tochange2] = $user[$tochange2] - $special2[1];
            $specialchange2 = "$tochange2='".$user[$tochange2]."',";
            if ($tochange2 == "strength") { $user["attackpower"] -= $special2[1]; }
            if ($tochange2 == "dexterity") { $user["defensepower"] -= $special2[1]; }
        }
        
        // New stats.
        $newgold = $user["gold"] + ceil($itemsrow2["buycost"]/2) - $itemsrow["buycost"];
        $newattack = $user["attackpower"] + $itemsrow["attribute"] - $itemsrow2["attribute"];
        $newid = $itemsrow["id"];
        $newname = $itemsrow["name"];
        $userid = $user["id"];
        if ($user["currenthp"] > $user["maxhp"]) { $newhp = $user["maxhp"]; } else { $newhp = $user["currenthp"]; }
        if ($user["currentmp"] > $user["maxmp"]) { $newmp = $user["maxmp"]; } else { $newmp = $user["currentmp"]; }
        if ($user["currenttp"] > $user["maxtp"]) { $newtp = $user["maxtp"]; } else { $newtp = $user["currenttp"]; }
        
        // Final update.
        $query = prepare("update {{ table }} set {$specialchange1} {$specialchange2} gold=?, attackpower=?, weaponid=?, weaponname=?, currenthp=?, currentmp=?, currenttp=? where id=?", 'users', $link);
        $data = [$newgold, $newattack, $newid, $newname, $newhp, $newmp, $newtp, $userid];
        execute($query, $data);
    } elseif ($itemsrow["type"] == 2) { // Armor
    	// Check if they already have an item in the slot.
        if ($user["armorid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['armorid']], $link)->fetch();
        } else {
            $itemsrow2 = array("attribute"=>0,"buycost"=>0,"special"=>"X");
        }
        
        // Special item fields.
        $specialchange1 = "";
        $specialchange2 = "";
        if ($itemsrow["special"] != "X") {
            $special = explode(",",$itemsrow["special"]);
            $tochange = $special[0];
            $user[$tochange] = $user[$tochange] + $special[1];
            $specialchange1 = "$tochange='".$user[$tochange]."',";
            if ($tochange == "strength") { $user["attackpower"] += $special[1]; }
            if ($tochange == "dexterity") { $user["defensepower"] += $special[1]; }
        }
        if ($itemsrow2["special"] != "X") {
            $special2 = explode(",",$itemsrow2["special"]);
            $tochange2 = $special2[0];
            $user[$tochange2] = $user[$tochange2] - $special2[1];
            $specialchange2 = "$tochange2='".$user[$tochange2]."',";
            if ($tochange2 == "strength") { $user["attackpower"] -= $special2[1]; }
            if ($tochange2 == "dexterity") { $user["defensepower"] -= $special2[1]; }
        }
        
        // New stats.
        $newgold = $user["gold"] + ceil($itemsrow2["buycost"]/2) - $itemsrow["buycost"];
        $newdefense = $user["defensepower"] + $itemsrow["attribute"] - $itemsrow2["attribute"];
        $newid = $itemsrow["id"];
        $newname = $itemsrow["name"];
        $userid = $user["id"];
        if ($user["currenthp"] > $user["maxhp"]) { $newhp = $user["maxhp"]; } else { $newhp = $user["currenthp"]; }
        if ($user["currentmp"] > $user["maxmp"]) { $newmp = $user["maxmp"]; } else { $newmp = $user["currentmp"]; }
        if ($user["currenttp"] > $user["maxtp"]) { $newtp = $user["maxtp"]; } else { $newtp = $user["currenttp"]; }
        
        // Final update.
        $query = prepare("update {{ table }} set {$specialchange1} {$specialchange2} gold=?, defensepower=?, armorid=?, armorname=?, currenthp=?, currentmp=?, currenttp=? where id=?", 'users', $link);
        $data = [$newgold, $newdefense, $newid, $newname, $newhp, $newmp, $newtp, $userid];
        execute($query, $data);
    } elseif ($itemsrow["type"] == 3) { // Shield
    	// Check if they already have an item in the slot.
        if ($user["shieldid"] != 0) { 
            $itemsrow2 = quick('select * from {{ table }} where id=?', 'items', [$user['shieldid']], $link)->fetch();
        } else {
            $itemsrow2 = array("attribute"=>0,"buycost"=>0,"special"=>"X");
        }
        
        // Special item fields.
        $specialchange1 = "";
        $specialchange2 = "";
        if ($itemsrow["special"] != "X") {
            $special = explode(",",$itemsrow["special"]);
            $tochange = $special[0];
            $user[$tochange] = $user[$tochange] + $special[1];
            $specialchange1 = "$tochange='".$user[$tochange]."',";
            if ($tochange == "strength") { $user["attackpower"] += $special[1]; }
            if ($tochange == "dexterity") { $user["defensepower"] += $special[1]; }
        }
        if ($itemsrow2["special"] != "X") {
            $special2 = explode(",",$itemsrow2["special"]);
            $tochange2 = $special2[0];
            $user[$tochange2] = $user[$tochange2] - $special2[1];
            $specialchange2 = "$tochange2='".$user[$tochange2]."',";
            if ($tochange2 == "strength") { $user["attackpower"] -= $special2[1]; }
            if ($tochange2 == "dexterity") { $user["defensepower"] -= $special2[1]; }
        }
        
        // New stats.
        $newgold = $user["gold"] + ceil($itemsrow2["buycost"]/2) - $itemsrow["buycost"];
        $newdefense = $user["defensepower"] + $itemsrow["attribute"] - $itemsrow2["attribute"];
        $newid = $itemsrow["id"];
        $newname = $itemsrow["name"];
        $userid = $user["id"];
        if ($user["currenthp"] > $user["maxhp"]) { $newhp = $user["maxhp"]; } else { $newhp = $user["currenthp"]; }
        if ($user["currentmp"] > $user["maxmp"]) { $newmp = $user["maxmp"]; } else { $newmp = $user["currentmp"]; }
        if ($user["currenttp"] > $user["maxtp"]) { $newtp = $user["maxtp"]; } else { $newtp = $user["currenttp"]; }
        
        // Final update.
        $query = prepare("update {{ table }} set {$specialchange1} {$specialchange2} gold=?, defensepower=?, shieldid=?, shieldname=?, currenthp=?, currentmp=?, currenttp=? where id=?", 'users', $link);
        $data = [$newgold, $newdefense, $newid, $newname, $newhp, $newmp, $newtp, $userid];
        execute($query, $data);        
    }
    
    display("Thank you for purchasing this item.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=buy\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Items");
}

/**
 * Displays the maps available for purchase at this town.
 */
function maps()
{
    global $user, $link;
    
    $mappedtowns = explode(",",$user["towns"]);
    
    $page = "Buying maps will put the town in your Travel To box, and it won't cost you as many TP to get there.<br /><br />\n";
    $page .= "Click a town name to purchase its map.<br /><br />\n";
    $page .= "<table width=\"90%\">\n";
    
    $towns = query('select * from {{ table }}', 'towns', $link);

    foreach ($towns->fetchAll() as $townrow) {
        if ($townrow["latitude"] >= 0) { $latitude = $townrow["latitude"] . "N,"; } else { $latitude = ($townrow["latitude"]*-1) . "S,"; }
        if ($townrow["longitude"] >= 0) { $longitude = $townrow["longitude"] . "E"; } else { $longitude = ($townrow["longitude"]*-1) . "W"; }
        
        $mapped = false;
        foreach($mappedtowns as $a => $b) {
            if ($b == $townrow["id"]) { $mapped = true; }
        }
        if ($mapped == false) {
            $page .= "<tr><td width=\"25%\"><a href=\"index.php?do=maps2:".$townrow["id"]."\">".$townrow["name"]."</a></td><td width=\"25%\">Price: ".$townrow["mapprice"]." gold</td><td width=\"50%\" colspan=\"2\">Buy map to reveal details.</td></tr>\n";
        } else {
            $page .= "<tr><td width=\"25%\"><span class=\"light\">".$townrow["name"]."</span></td><td width=\"25%\"><span class=\"light\">Already mapped.</span></td><td width=\"35%\"><span class=\"light\">Location: $latitude $longitude</span></td><td width=\"15%\"><span class=\"light\">TP: ".$townrow["travelpoints"]."</span></td></tr>\n";
        }
    }
    
    $page .= "</table><br />\n";
    $page .= "If you've changed your mind, you may also return back to <a href=\"index.php\">town</a>.\n";
    
    display($page, "Buy Maps");
}

/**
 * Confirms whether the user wants to buy the map they selected.
 */
function maps2($id)
{
    global $user, $link;
    
    $townrow = quick('select name, mapprice from {{ table }} where id=?', 'towns', [$id], $link)->fetch();
    
    if ($user["gold"] < $townrow["mapprice"]) { display("You do not have enough gold to buy this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps"); die(); }
    
    $page = "You are buying the ".$townrow["name"]." map. Is that ok?<br /><br /><form action=\"index.php?do=maps3:$id\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
    
    display($page, "Buy Maps");
}

/**
 * Add the map to the user's list of maps.
 */
function maps3($id)
{
    if (isset($_POST["cancel"])) { redirect("index.php"); }
    
    global $user, $link;
    
    $townrow = quick('select name, mapprice from {{ table }} where id=?', 'towns', [$id], $link)->fetch();
    
    if ($user["gold"] < $townrow["mapprice"]) { display("You do not have enough gold to buy this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps"); die(); }
    
    $mappedtowns = $user["towns"].",$id";
    $newgold = $user["gold"] - $townrow["mapprice"];
    
    $update = prepare('update {{ table }} set towns=?, gold=? where id=?', 'users', $link);
    execute($update, [$mappedtowns, $newgold, $user['id']]);
    
    display("Thank you for purchasing this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps");
}

/**
 * Handles the "fast travel" feature
 */
function travelto($id, $usepoints = true)
{
    global $user, $link;
    
    if ($user["currentaction"] == "Fighting") { redirect("index.php?do=fight"); }
    
    $townrow = quick('select name, travelpoints, latitude, longitude from {{ table }} where id=?', 'towns', [$id], $link)->fetch();
    
    if ($usepoints==true) { 
        if ($user["currenttp"] < $townrow["travelpoints"]) { 
            display("You do not have enough TP to travel here. Please go back and try again when you get more TP.", "Travel To"); die(); 
        }
        $mapped = explode(",",$user["towns"]);
        if (!in_array($id, $mapped)) { display("Cheat attempt detected.<br /><br />Get a life, loser.", "Error"); }
    }
    
    if (($user["latitude"] == $townrow["latitude"]) && ($user["longitude"] == $townrow["longitude"])) { display("You are already in this town. <a href=\"index.php\">Click here</a> to return to the main town screen.", "Travel To"); die(); }
    
    if ($usepoints == true) { $newtp = $user["currenttp"] - $townrow["travelpoints"]; } else { $newtp = $user["currenttp"]; }
    
    $newlat = $townrow["latitude"];
    $newlon = $townrow["longitude"];
    $newid = $user["id"];
    
    // If they got here by exploring, add this town to their map.
    $mapped = explode(",",$user["towns"]);
    $town = false;
    foreach($mapped as $a => $b) {
        if ($b == $id) { $town = true; }
    }
    $mapped = implode(",",$mapped);
    if ($town == false) { 
        $mapped .= ",$id";
        $mapped = "towns='".$mapped."',";
    } else { 
        $mapped = "towns='".$mapped."',";
    }
    
    $update = prepare("update {{ table }} set currentaction='In Town',{$mapped} currenttp=?, latitude=?, longitude=? where id=?", 'users', $link);
    execute($update, [$newtp, $newlat, $newlon, $newid]);
    
    $page = "You have travelled to ".$townrow["name"].". You may now <a href=\"index.php\">enter this town</a>.";
    display($page, "Travel To");
}