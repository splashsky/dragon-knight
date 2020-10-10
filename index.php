<?php

require 'app/Libs/Helpers.php';

if (file_exists('install.php') && !DEBUG) {
    die('Please delete <b>install.php</b> from your Dragon Knight directory before continuing.'); 
}

require 'app/Libs/Explore.php';
require 'app/Libs/Towns.php';
require 'app/Libs/Fight.php';

$link = openLink();
$control = getControl($link);

// If the user isn't logged in, redirect to the login page
if (! checkcookies($link)) { redirect('users.php?do=login'); }

// Get the user's data based on the cookie.
$user = getUserFromCookie($link);

// Force verify if the user isn't verified yet.
if ($control['verifyemail'] == 1 && $user["verify"] != 1) { redirect('users.php?do=verify'); }

// Kill the script if the user has been banned.
if ($user["authlevel"] == 2) { die('You\'ve been banned. Try again later.'); }

// Get the requested action, or default to the user's current action.
$do = isset($_GET['do']) ? explode(':', $_GET['do']) : 'currentAction';

// If the game is closed, set our action to the correct endpoint.
if ($control['gameopen'] == 0) { $do = 'gameClosed'; }

// Town Functions
if ($do[0] == "inn") { inn(); }
elseif ($do[0] == "buy") { buy(); }
elseif ($do[0] == "buy2") { buy2($do[1]); }
elseif ($do[0] == "buy3") { buy3($do[1]); }
//elseif ($do[0] == "sell") { sell(); }
elseif ($do[0] == "maps") { maps(); }
elseif ($do[0] == "maps2") { maps2($do[1]); }
elseif ($do[0] == "maps3") { maps3($do[1]); }
elseif ($do[0] == "gotown") { travelto($do[1]); }

// Exploration functions
elseif ($do[0] == "move") { move(); }

// Fight functions
elseif ($do[0] == "fight") { fight(); }
elseif ($do[0] == "victory") { victory(); }
elseif ($do[0] == "drop") { drop(); }
elseif ($do[0] == "dead") { dead(); }

// Other functions
elseif ($do[0] == "verify") { header("Location: users.php?do=verify"); }
elseif ($do[0] == "spell") { include('app/Libs/Heal.php'); healspells($do[1]); }
elseif ($do[0] == "showchar") { showchar(); }
elseif ($do[0] == "onlinechar") { onlinechar($do[1]); }
elseif ($do[0] == "showmap") { showmap(); }
elseif ($do[0] == "babblebox") { babblebox(); }
elseif ($do[0] == "ninja") { ninja(); }
elseif ($do == 'gameClosed') { gameClosed(); }

// Default function
else { doCurrentAction(); }

/**
 * This function determines what action to take if no action was requested.
 */
function doCurrentAction()
{
    global $user;
    $currently = $user['currentaction'];

    if ($currently == 'In Town') { $page = displayTown(); }
    elseif ($currently == "Exploring") { $page = displayExplore(); }
    elseif ($currently == "Fighting") { redirect('index.php?do=fight'); }
    else { $page = 'There was an error in the current action.'; }
    
    display($page, $currently);
}

/**
 * Generate the town page.
 */
function displayTown()
{
    global $user, $control, $link, $queries;

    $townrow = getTown($user['latitude'], $user['longitude'], $link);
    
    // Generate the news box
    if ($control["shownews"] == 1) { 
        $news = query('select * from {{ table }} order by id desc limit 1', 'news', $link);
        $news = $news->fetch();
        
        $townrow['news'] = "<table width=\"95%\"><tr><td class=\"title\">Latest News</td></tr><tr><td>\n";
        $townrow['news'] .= $news ? "<span class=\"light\">".prettydate($news["postdate"])."</span><br />".nl2br($news["content"]) : "Woah! There's no news post.";
        $townrow['news'] .= "</td></tr></table>\n";
    } else {
        $townrow['news'] = '';
    }
    
    // Who's online? Shows users who've logged in within the last 10 minutes
    if ($control["showonline"] == 1) {
        $online = query('select id, username from {{ table }} where onlinetime >= date_sub(now(), interval 10 minute) ORDER BY username', 'users', $link);
        $online = $online->fetchAll();

        $townrow["whosonline"] = "<table width=\"95%\"><tr><td class=\"title\">Who's Online</td></tr><tr><td>\n";
        $townrow["whosonline"] .= "There are <b>" . count($online) . "</b> user(s) online within the last 10 minutes: ";

        foreach ($online as $user) {
            $townrow["whosonline"] .= "<a href=\"index.php?do=onlinechar:{$user['id']}\">{$user['username']}</a>, ";
        }

        $townrow["whosonline"] = rtrim($townrow["whosonline"], ", ");
        $townrow["whosonline"] .= "</td></tr></table>\n";
    } else {
        $townrow["whosonline"] = "";
    }
    
    // The Babblebox currently works through an IFrame. I'd like to change this soon.
    if ($control["showbabble"] == 1) {
        $townrow["babblebox"] = "<table width=\"95%\"><tr><td class=\"title\">Babble Box</td></tr><tr><td>\n";
        $townrow["babblebox"] .= "<iframe src=\"index.php?do=babblebox\" name=\"sbox\" width=\"100%\" height=\"250\" frameborder=\"0\" id=\"bbox\">Your browser does not support inline frames! The Babble Box will not be available until you upgrade to a newer <a href=\"http://www.mozilla.org\" target=\"_new\">browser</a>.</iframe>";
        $townrow["babblebox"] .= "</td></tr></table>\n";
    } else {
        $townrow["babblebox"] = "";
    }
    
    $page = gettemplate("town/towns");
    $page = parsetemplate($page, $townrow);
    
    return $page;
}

function showchar()
{
    
    global $user, $control, $link;
    
    // Format various userrow stuffs.
    $user["experience"] = number_format($user["experience"]);
    $user["gold"] = number_format($user["gold"]);
    if ($user["expbonus"] > 0) { 
        $user["plusexp"] = "<span class=\"light\">(+".$user["expbonus"]."%)</span>"; 
    } elseif ($user["expbonus"] < 0) {
        $user["plusexp"] = "<span class=\"light\">(".$user["expbonus"]."%)</span>";
    } else { $user["plusexp"] = ""; }
    if ($user["goldbonus"] > 0) { 
        $user["plusgold"] = "<span class=\"light\">(+".$user["goldbonus"]."%)</span>"; 
    } elseif ($user["goldbonus"] < 0) { 
        $user["plusgold"] = "<span class=\"light\">(".$user["goldbonus"]."%)</span>";
    } else { $user["plusgold"] = ""; }
    
    $exp = prepare("select {$user['class']}_exp from {{ table }} where id=? limit 1", 'levels', $link);
    $levelrow = execute($exp, [$user['level'] + 1])->fetch();
    if ($user["level"] < 99) { $user["nextlevel"] = number_format($levelrow[$user["class"]."_exp"]); } else { $user["nextlevel"] = "<span class=\"light\">None</span>"; }

    if ($user["class"] == 1) { $user["class"] = $control["class1name"]; }
    elseif ($user["class"] == 2) { $user["class"] = $control["class2name"]; }
    elseif ($user["class"] == 3) { $user["class"] = $control["class3name"]; }
    
    if ($user["difficulty"] == 1) { $user["difficulty"] = $control["diff1name"]; }
    elseif ($user["difficulty"] == 2) { $user["difficulty"] = $control["diff2name"]; }
    elseif ($user["difficulty"] == 3) { $user["difficulty"] = $control["diff3name"]; }
    
    $spells = query('select id, name from {{ table }}', 'spells', $link);
    $userspells = explode(",", $user["spells"]);
    $user["magiclist"] = "";
    foreach ($spells->fetchAll() as $spellrow) {
        $spell = false;
        foreach($userspells as $a => $b) {
            if ($b == $spellrow["id"]) { $spell = true; }
        }
        if ($spell == true) {
            $user["magiclist"] .= $spellrow["name"]."<br />";
        }
    }
    if ($user["magiclist"] == "") { $user["magiclist"] = "None"; }
    
    // Make page tags for XHTML validation.
    $xml = "<!DOCTYPE html>\n"
    . "<html lang=\"en\">\n";
    
    $charsheet = gettemplate("showchar");
    $page = $xml . gettemplate("minimal");
    $array = ["content" => parsetemplate($charsheet, $user), "title" => "Character Information"];
    echo parsetemplate($page, $array);
}

function onlinechar($id)
{
    global $control, $link;

    $user = getUserFromId($id, $link);
    
    // Format various userrow stuffs.
    $user["experience"] = number_format($user["experience"]);
    $user["gold"] = number_format($user["gold"]);
    if ($user["expbonus"] > 0) { 
        $user["plusexp"] = "<span class=\"light\">(+".$user["expbonus"]."%)</span>"; 
    } elseif ($user["expbonus"] < 0) {
        $user["plusexp"] = "<span class=\"light\">(".$user["expbonus"]."%)</span>";
    } else { $user["plusexp"] = ""; }
    if ($user["goldbonus"] > 0) { 
        $user["plusgold"] = "<span class=\"light\">(+".$user["goldbonus"]."%)</span>"; 
    } elseif ($user["goldbonus"] < 0) { 
        $user["plusgold"] = "<span class=\"light\">(".$user["goldbonus"]."%)</span>";
    } else { $user["plusgold"] = ""; }
    
    $exp = prepare("select {$user['class']}_exp from {{ table }} where id=? limit 1", 'levels', $link);
    $levelrow = execute($exp, [$user['level'] + 1])->fetch();
    $user["nextlevel"] = number_format($levelrow[$user["class"]."_exp"]);

    if ($user["class"] == 1) { $user["class"] = $control["class1name"]; }
    elseif ($user["class"] == 2) { $user["class"] = $control["class2name"]; }
    elseif ($user["class"] == 3) { $user["class"] = $control["class3name"]; }
    
    if ($user["difficulty"] == 1) { $user["difficulty"] = $control["diff1name"]; }
    elseif ($user["difficulty"] == 2) { $user["difficulty"] = $control["diff2name"]; }
    elseif ($user["difficulty"] == 3) { $user["difficulty"] = $control["diff3name"]; }
    
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