<?php

/**
 * This script contains the functions that operate town features such as
 * the inn, shop, and more.
 */

 /**
  * This page is the central portion of towns. Shows various parts of the game, such as the
  * babblebox, who's online and latest news posting.
  */
function townSquare()
{
    global $user, $control, $link;

    $town = getTown($user['latitude'], $user['longitude'], $link);
    
    // Generate the news box
    if ($control["show_news"] == 1) { 
        $news = query('select * from {{ table }} order by id desc limit 1', 'news', $link);
        $news = $news->fetch();
        
        if ($news) {
            $author = getUserFromId($news['user_id'], $link, 'username')['username'];
            $posted = prettydate($news['posted']);
            $content = nl2br(safe($news['content']));
            $content = "<span class=\"light\">{$author} - {$posted}</span><br />{$content}";
        } else {
            $content = "Woah! There's no news post.";
        }
        
        $town['news'] = view('town/news', ['content' => $content]);
    } else {
        $town['news'] = '';
    }
    
    // Who's online? Shows users who've logged in within the last 10 minutes
    if ($control["show_online"] == 1) {
        $online = query('select id, username from {{ table }} where online_last >= date_sub(now(), interval 10 minute) ORDER BY username', 'users', $link);
        $online = $online->fetchAll();

        $list = '';
        foreach ($online as $user) {
            $list .= "<a href=\"index.php?do=user&user={$user['id']}\">{$user['username']}</a>, ";
        }
        $list = rtrim($list, ', ');

        $town["whosonline"] = view('town/online', ['count' => count($online), 'list' => $list]);
    } else {
        $town["whosonline"] = '';
    }
    
    // The Babblebox currently works through an IFrame. I'd like to change this soon.
    $showBabble = (bool) $control['show_babble'];
    $town['babblebox'] = $showBabble ? view('town/babbleBox') : '';
    
    return view('town/square', $town);
}

 /**
  * Handle either displaying the inn or resting at the inn. Resting at the inn
  * sets all meters back to full.
  */
function inn()
{
    if (isset($_POST['cancel'])) { redirect('index.php'); }
    
    global $user, $link;

    $town = getTown($user['latitude'], $user['longitude'], $link);
    $afford = $user['gold'] >= $town['inn_price'];
    $page = $afford ? view('town/inn/confirm', $town) : view('town/inn/cantAfford', $town);
    
    if (isset($_POST["submit"]) && $afford) {
        $gold = $user['gold'] - $town['inn_price'];
        $rested = prepare('update {{ table }} set gold=?, hp=max_hp, mp=max_mp, tp=max_tp where id=?', 'users', $link);
        execute($rested, [$gold, $user['id']]);

        $page = view('town/inn/rested', $town);
    }
    
    display($page, 'Inn');
}

/**
 * Handles displaying the list of items for sale in a given town.
 */
function itemShop()
{
    global $user, $link;
    
    $town = getTown($user['latitude'], $user['longitude'], $link);
    $items = explode(',', $town['items']);

    $query = "";
    foreach($items as $id) { $query .= "id='{$id}' OR "; }
    $query = rtrim($query, ' OR ');
    
    $items = query("select * from {{ table }} where {$query}", 'items');
    $list = '';
    foreach ($items->fetchAll() as $item) {
        $item['attrib'] = $item['type'] == 'weapon' ? 'Attack' : 'Defense';

        // if owned $list .= view('town/itemShop/ownedItem)

        $item['dot'] = ! empty($item['special']) ? '<span class="highlight">*</span>' : '';
        $list .= view('town/itemShop/itemRow', $item);
    }

    $town['itemList'] = $list;
    $page = view('town/itemShop/store', $town);
    
    display($page, 'Item Shop');
}

/**
 * Confirms whether the user is sure about buying the item they selected.
 */
function buyItem()
{
    global $user, $inventory, $link;
    
    $id = GET('item', fn() => redirect('index.php'));

    // Check and make sure the requested item is actually an item sold by this town.
    $town = getTown($user['latitude'], $user['longitude'], $link);
    $items = explode(',', $town['items']);
    if (! in_array($id, $items)) { die('Cheat attempt detected. Please go back and try again.'); }
    
    $item = getItemById($id, $link);
    $item['town_name'] = $town['name']; // This is for convenience during transactions.
    $afford = $user['gold'] >= $item['value'];

    if (! $afford) {
        $item['more'] = $item['value'] - $user['gold'];
        display(view('town/itemShop/cantAfford', $item), 'Item Shop - Can\'t Afford');
    }

    if (userHasItemInSlot($item['type'], $inventory)) {
        $item2 = getItemById(getItemIdForSlot($item['type'], $inventory), $link, 'name, value');
        $item['item2_name'] = $item2['name'];
        $item['item2_sell'] = ceil($item2['value'] / 2);
        $page = view('town/itemShop/trade', $item);
    } else {
        $page = view('town/itemShop/confirm', $item);
    }
    
    display($page, 'Item Shop - Trading');
}

/**
 * Handles updating the user's profile with their newly purchased item!
 */
function giveItem()
{
    if (isset($_POST["cancel"])) { redirect('index.php?do=itemShop'); }
    
    global $user, $link, $inventory;
    
    $id = GET('item', fn() => redirect('index.php'));

    // Check and make sure the requested item is actually an item sold by this town.
    $town = getTown($user['latitude'], $user['longitude'], $link);
    $items = explode(',', $town['items']);
    if (! in_array($id, $items)) { die('Cheat attempt detected. Please go back and try again.'); }
    
    $item = getItemById($id, $link);
    $item['town_name'] = $town['name']; // This is for convenience during transactions.
    $afford = $user['gold'] >= $item['value'];

    if (! $afford) {
        $item['more'] = $item['value'] - $user['gold'];
        display(view('town/itemShop/cantAfford', $item), 'Item Shop - Can\'t Afford');
    }

    $discount = 0;
    if (userHasItemInSlot($item['type'], $inventory)) {
        $item2 = getItemById(getItemIdForSlot($item['type'], $inventory), $link, 'value');
        $discount = ceil($item2['value'] / 2);
    }

    equipItemOnUser($item, $user, $inventory);
    
    $newgold = $user['gold'] - ($item['value'] - $discount);
    userSave($user['id'], ['gold' => $newgold], $link);
    
    $page = view('town/itemShop/bought', $item);
    display($page, 'Item Shop - Bought!');
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
            $page .= "<tr><td width=\"25%\"><a href=\"index.php?do=buymap&map={$townrow["id"]}\">{$townrow["name"]}</a></td><td width=\"25%\">Price: {$townrow["map_price"]} gold</td><td width=\"50%\" colspan=\"2\">Buy map to reveal details.</td></tr>\n";
        } else {
            $page .= "<tr><td width=\"25%\"><span class=\"light\">".$townrow["name"]."</span></td><td width=\"25%\"><span class=\"light\">Already mapped.</span></td><td width=\"35%\"><span class=\"light\">Location: $latitude $longitude</span></td><td width=\"15%\"><span class=\"light\">TP: ".$townrow["tp_cost"]."</span></td></tr>\n";
        }
    }
    
    $page .= "</table><br />\n";
    $page .= "If you've changed your mind, you may also return back to <a href=\"index.php\">town</a>.\n";
    
    display($page, "Buy Maps");
}

/**
 * Confirms whether the user wants to buy the map they selected.
 */
function buyMap()
{
    global $user, $link;

    $id = GET('map', fn() => redirect('index.php'));
    
    $townrow = quick('select name, map_price from {{ table }} where id=?', 'towns', [$id], $link)->fetch();
    
    if ($user["gold"] < $townrow["map_price"]) { display("You do not have enough gold to buy this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps"); die(); }
    
    $page = "You are buying the ".$townrow["name"]." map. Is that ok?<br /><br /><form action=\"index.php?do=givemap&map={$id}\" method=\"post\"><input type=\"submit\" name=\"submit\" value=\"Yes\" /> <input type=\"submit\" name=\"cancel\" value=\"No\" /></form>";
    
    display($page, "Buy Maps");
}

/**
 * Add the map to the user's list of maps.
 */
function giveMap()
{
    if (isset($_POST["cancel"])) { redirect("index.php"); }
    
    global $user, $link;

    $id = GET('map', fn() => redirect('index.php'));
    
    $townrow = quick('select name, map_price from {{ table }} where id=?', 'towns', [$id], $link)->fetch();
    
    if ($user["gold"] < $townrow["map_price"]) { display("You do not have enough gold to buy this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps"); die(); }
    
    $mappedtowns = $user["towns"].",$id";
    $newgold = $user["gold"] - $townrow["map_price"];
    
    $update = prepare('update {{ table }} set towns=?, gold=? where id=?', 'users', $link);
    execute($update, [$mappedtowns, $newgold, $user['id']]);
    
    display("Thank you for purchasing this map.<br /><br />You may return to <a href=\"index.php\">town</a>, <a href=\"index.php?do=maps\">store</a>, or use the direction buttons on the left to start exploring.", "Buy Maps");
}

/**
 * Handles the "fast travel" feature
 */
function travelTo($town = 0, $usePoints = true)
{
    global $user, $link;
    
    if ($user['action'] == 'Fighting') { redirect('index.php?do=fight'); }

    $id = $town == 0 ? GET('town', fn() => redirect('index.php')) : $town;
    
    $town = townGetFromId($id, $link);
    $mapped = explode(',', $user['towns']);
    
    if ($usePoints) { 
        if ($user['tp'] < $town["tp_cost"]) {
            $page = view('town/travel/lowTp', $town);
            display($page, 'Travelling - Low TP');
        }

        if (! in_array($id, $mapped)) { die('Cheat attempt detected.'); }
    }
    
    if ($user['latitude'] == $town['latitude'] && $user['longitude'] == $town['longitude']) {
        $page = view('town/travel/alreadyHere', $town);
        display($page, 'Travelling - Already in Town');
    }

    $user['action'] = 'In Town';
    $user['tp'] = $usePoints ? $user['tp'] - $town['tp_cost'] : $user['tp'];
    $user['latitude'] = $town['latitude'];
    $user['longitude'] = $town['longitude'];
    
    // If they got here by exploring, add this town to their map.
    if (! in_array($town['id'], $mapped)) { $user['towns'] .= ",{$town['id']}"; }
    
    userSave($user['id'], $user, $link);
    
    $page = view('town/travel/arrived', $town);
    display($page, 'Travelling - Arrived');
}