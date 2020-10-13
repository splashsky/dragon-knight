<?php

// Most of the functionality we need can be found in the Game script...
require 'app/Game.php';

dieIfNotInstalled();
dieIfGameClosed($control);

// These are the libraries for various game functions.
require 'app/Libs/Explore.php';
require 'app/Libs/Towns.php';
require 'app/Libs/Fight.php';

// Get the user if their cookie exists.
$user = getUserIfLoggedInByCookie($link);
$inventory = getUserInventory($user['id']);

// Force verify if the user isn't verified yet.
redirectIfNotVerified($user['verified'], $control['verify_email']);
dieIfBanned($user['role']);

// Get the requested action, or default to the user's current action.
$request = GET('do', 'default');

// Town Functions
if ($request == "inn") { inn(); }
elseif ($request == "itemShop") { itemShop(); }
elseif ($request == "buyItem") { buyitem(); }
elseif ($request == "giveItem") { giveItem(); }
//elseif ($request == "sell") { sell(); }
elseif ($request == "maps") { maps(); }
elseif ($request == "buymap") { buyMap(); }
elseif ($request == "givemap") { giveMap(); }
elseif ($request == "goto") { travelTo(); }

// Exploration functions
elseif ($request == "move") { move(); }

// Fight functions
elseif ($request == "fight") { fight(); }
elseif ($request == "victory") { victory(); }
elseif ($request == "drop") { drop(); }
elseif ($request == "dead") { dead(); }

// Other functions
elseif ($request == "verify") { header("Location: users.php?do=verify"); }
elseif ($request == "spell") { include('app/Libs/Heal.php'); healspells(''); }
elseif ($request == "extendedStats") { extendedStats(); }
elseif ($request == "onlinechar") { onlinechar(''); }
elseif ($request == "showmap") { showmap(); }
elseif ($request == "babblebox") { babblebox(); }
elseif ($request == "ninja") { ninja(); }
elseif ($request == 'gameClosed') { gameClosed(); }

// Default function
else { doCurrentAction(); }

/**
 * This function determines what action to take if no action was requested.
 */
function doCurrentAction()
{
    global $user;
    $currently = $user['action'];

    if ($currently == 'In Town') { $page = townSquare(); }
    elseif ($currently == "Exploring") { $page = displayExplore(); }
    elseif ($currently == "Fighting") { redirect('index.php?do=fight'); }
    else { $page = 'There was an error in the current action.'; }
    
    display($page, $currently);
}

function extendedStats()
{
    global $user, $link;
    
    // Format various userrow stuffs.
    $user['experience'] = number_format($user['experience']);
    $user['gold'] = number_format($user['gold']);

    $bonus = $user['exp_bonus'] > 0 ? "+{$user['exp_bonus']}" : $user['exp_bonus'];
    $user['plus_exp'] = "<span class=\"light\">({$bonus}%)</span>";

    $bonus = $user['gold_bonus'] > 0 ? "+{$user['gold_bonus']}" : $user['gold_bonus'];
    $user['plus_gold'] = "<span class=\"light\">({$bonus}%)</span>";
    
    $exp = getExpForNextLevel($user['level'], $user['experience'], $user['class']);
    $user['next_level'] = $user['level'] < 99 ? number_format($exp) : "<span class=\"light\">Max Level</span>";

    $user['class'] = config("classes.{$user['class']}")['title'];
    $user['difficulty'] = config("game.difficulties.{$user['difficulty']}")['title'];
    
    $spells = query('select id, name from {{ table }}', 'spells', $link);
    $userspells = explode(",", $user["spells"]);
    $user['magic_list'] = "";
    foreach ($spells->fetchAll() as $spellrow) {
        $spell = false;
        foreach($userspells as $a => $b) {
            if ($b == $spellrow["id"]) { $spell = true; }
        }
        if ($spell == true) {
            $user['magic_list'] .= $spellrow["name"]."<br />";
        }
    }
    if ($user['magic_list'] == "") { $user['magic_list'] = "None"; }
    
    $page = view('showchar', $user);
    echo view('minimal', ['content' => $page, 'title' => 'Player Info']);
}

function onlinechar($id)
{
    global $control, $link;

    $user = getUserFromId($id, $link);
    
    // Format various userrow stuffs.
    $user['experience'] = number_format($user['experience']);
    $user['gold'] = number_format($user['gold']);
    if ($user['exp_bonus'] > 0) { 
        $user["plusexp"] = "<span class=\"light\">(+".$user['exp_bonus']."%)</span>"; 
    } elseif ($user['exp_bonus'] < 0) {
        $user["plusexp"] = "<span class=\"light\">(".$user['exp_bonus']."%)</span>";
    } else { $user["plusexp"] = ""; }
    if ($user['gold_bonus'] > 0) { 
        $user['plus_gold'] = "<span class=\"light\">(+".$user['gold_bonus']."%)</span>"; 
    } elseif ($user['gold_bonus'] < 0) { 
        $user['plus_gold'] = "<span class=\"light\">(".$user['gold_bonus']."%)</span>";
    } else { $user['plus_gold'] = ""; }
    
    $exp = prepare("select {$user['class']}_exp from {{ table }} where id=? limit 1", 'levels', $link);
    $levelrow = execute($exp, [$user['level'] + 1])->fetch();
    $user['next_level'] = number_format($levelrow[$user['class']."_exp"]);

    if ($user['class'] == 1) { $user['class'] = $control["class1name"]; }
    elseif ($user['class'] == 2) { $user['class'] = $control["class2name"]; }
    elseif ($user['class'] == 3) { $user['class'] = $control["class3name"]; }
    
    if ($user['difficulty'] == 1) { $user['difficulty'] = $control["diff1name"]; }
    elseif ($user['difficulty'] == 2) { $user['difficulty'] = $control["diff2name"]; }
    elseif ($user['difficulty'] == 3) { $user['difficulty'] = $control["diff3name"]; }
    
    $charsheet = gettemplate("onlinechar");
    $page = parsetemplate($charsheet, $user);
    display($page, "Character Information");
}

function showmap()
{
    $page = gettemplate("minimal");
    $array = array("content"=>"<div style=\"padding: 1rem;\"><img src=\"resources/img/map.gif\" alt=\"Map\"></div>", "title" => "Map");
    echo parsetemplate($page, $array);
}

function babblebox()
{
    global $user, $link;
    
    if (isset($_POST['babble'])) {
        if (! empty($_POST['babble'])) {
            $insert = prepare('insert into {{ table }} set posttime=now(), author=?, babble=?', 'babble', $link);
            execute($insert, [$user['username'], $_POST['babble']]);
        }

        redirect('index.php?do=babblebox');
    }
    
    $babblebox = ['content' => ''];
    $babbles = query('select * from {{ table }} order by id desc limit 20', 'babble');

    foreach ($babbles->fetchAll() as $babble) {
        $message = safe($babble['babble']);
        $new = "<div><b>{$babble['author']}</b> {$message}</div>\n";
        $babblebox["content"] = $new . $babblebox["content"];
    }

    $babblebox["content"] .= "<form action=\"index.php?do=babblebox\" method=\"post\" class=\"w-full text-center py-4\"><input type=\"text\" name=\"babble\" maxlength=\"120\" class=\"mb-2\" style=\"background-color: rgba(0, 0, 0, 0.1); outline: none; border: none; padding: 0.5rem;\" /><br /><input type=\"submit\" name=\"submit\" value=\"Babble\" class=\"button mr-2\" /> <input type=\"reset\" name=\"reset\" value=\"Clear\" class=\"button\" /></form>";
    
    $page = gettemplate("babblebox");
    echo parsetemplate($page, $babblebox);
}

function gameClosed()
{
    display('The game is currently closed for maintanence. Please check back later.', 'Game Closed');
}

function ninja()
{
    redirect('http://www.se7enet.com/img/shirtninja.jpg');
}