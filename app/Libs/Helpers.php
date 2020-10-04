<?php

/**
 * Debug flag; when set to true, full errror reporting is
 * enabled and the game won't check for the installation
 * file
 */
define('DEBUG', false);

if (DEBUG) {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);
}

/**
 * On every page we use the Helpers library, we'll likely use the Database
 * library. As such, we'll require it here. We'll also open a link to the
 * database, since almost every page requires it.
 */
require 'app/Libs/Database.php';

$config = require 'app/config.php';
$starttime = getmicrotime();
$queryCount = 0;
$version = config('general.version');
$build = config('general.build');

/**
 * This helper function allows us to access config values
 * by dot notation. For example, instead of $config['db']['username']
 * we can do config('db.username')
 */
function config(string $key = '')
{
    global $config;

    if (empty($key)) {
        return $config;
    }

    if (array_key_exists($key, $config)) {
        return $config[$key];
    }

    $result = $config;

    foreach (explode('.', $key) as $segment) {
        if (!is_array($result) || !array_key_exists($segment, $result)) {
            return null;
        }

        $result = &$result[$segment];
    }

    return $result;
}

/**
 * This function takes whatever variable is passed to it, including
 * arrays, and spits it out as a preformatted var_dump. It then
 * kills the script. Great for debugging!
 */
function dd($variable = '', bool $die = true) {
    echo '<pre>';
    echo var_export($variable, true);
    echo '</pre>';
    if ($die) { die(); }
}

/**
 * Redirect a user to a given location.
 */
function redirect(string $location)
{
    header("Location: {$location}");
    exit;
}

/**
 * Increments the query count by 1.
 */
function incrementQueryCount()
{
    global $queryCount;
    $queryCount++;
}

/**
 * Gets the current query count.
 */
function getQueryCount()
{
    global $queryCount;
    return $queryCount;
}

/**
 * Retrieve a template from the template directory
 */
function gettemplate(string $template) {
    $path = 'resources/templates/' . $template . '.html';

    if (!is_readable($path)) {
        throw new Exception('Unable to get template <<' . $template . '>>');
    }

    return file_get_contents($path);
}

/**
 * Get the control row from the database.
 */
function getControl($link = null)
{
    $link = openLinkIfNull($link);
    return query('select * from {{ table }} where id=1', 'control', $link)->fetch();
}

/**
 * Determine whether a town exists at the given coordinates.
 */
function townExists(int $latitude, int $longitude, $link = null)
{
    $link = openLinkIfNull($link);
    $town = prepare('select id from {{ table }} where latitude=? and longitude=? limit 1', 'towns', $link);
    $town = execute($town, [$latitude, $longitude])->fetch();
    return $town ? true : false;
}

/**
 * Get town data for given coordinates.
 */
function getTown(int $latitude, int $longitude, $link = null)
{
    $link = openLinkIfNull($link);
    $town = prepare('select * from {{table}} where latitude=? and longitude=? limit 1', 'towns');
    return execute($town, [$latitude, $longitude])->fetch();
}

/**
 * Parse a template with all the correct data
 */
function parsetemplate($template, $array) {
    return preg_replace_callback(
        '/{{\s*([A-Za-z0-9_-]+)\s*}}/',
        function($match) use ($array) {
            return isset($array[$match[1]]) ? $array[$match[1]] : $match[0];
        },
        $template
    );
}

function getmicrotime() { // Used for timing script operations.

    list($usec, $sec) = explode(" ",microtime()); 
    return ((float)$usec + (float)$sec); 

}

/**
 * Format MySQL datetime stamps into something friendlier
 */
function prettydate($uglydate) {
    $date = new DateTime($uglydate);

    return $date->format('F j, Y');
}

/**
 * Alias for prettydate()
 */
function prettyforumdate($uglydate) {
    prettydate($uglydate);
}

/**
 * Validate the formatting of an email address
 */
function is_email(string $email)
{
    return filter_var($email, FILTER_VALIDATE_EMAIL);
}

/**
 * Ensure no XSS attacks can occur by sanitizing strings
 * However, this doesn't prevent some JS eval() attacks
 */
function safe(string $string = '')
{
    return htmlentities($string, ENT_QUOTES);
}

/**
 * A function that can loop through an array and run trim() on it.
 * Usually used to pull $_POST data into a friendlier-to-use variable.
 */
function trimData(array $data)
{
    $result = [];

    foreach ($data as $k => $d) {
        if (is_string($d)) { $d = trim($d); }
        $result[$k] = $d;
    }

    return $result;
}

/**
 * Check whether or not the user's "dkgame" cookie is authorized/valid.
 */
function checkcookies($link = null)
{
    $link = openLinkIfNull($link);

    if (isset($_COOKIE["dkgame"])) {
        $authorized = true;

        /**
         * Cookie Format
         * {user id} {username} {password from login} {remember me}
         */
        $cookie = explode(' ', $_COOKIE['dkgame']);

        // Query the database for the user
        $user = prepare('select password from {{ table }} where id=?', 'users', $link);
        $user = execute($user, [$cookie[0]])->fetch();

        // If the user doesn't exist, return not authorized
        if (! $user) { $authorized = false; }

        // If the password in the cookie doesn't match the password in the database, return not authoried
        if (! password_verify($cookie[2], $user['password'])) { $authorized = false; }
        
        if ($authorized) {
            // Condense our cookie back down to create a new one, and determine our expiration time.
            $new = implode(' ', $cookie);
            $expireTime = $cookie[3] == 1 ? time() + 31536000 : 0;

            // Create the new cookie
            setcookie('dkgame', $new, $expireTime, '/', '', 0);

            // Update the user's logged in time
            quick('update {{ table }} set onlinetime=now() where id=?', 'users', [$cookie[0]], $link);

            return true;
        }
    }
    
    deleteCookie();
    return false;
}

/**
 * Set the 'dkgame' cookie to a time in the past to clear it.
 */
function deleteCookie()
{
    setcookie('dkgame', '', time() - 10000, '', '', '');
}

/**
 * Get the user's data from the cookie.
 */
function getUserFromCookie($link = null)
{
    $link = openLinkIfNull($link);

    /**
     * Cookie Format
     * {user id} {username} {password from login} {remember me}
     */
    $cookie = explode(' ', $_COOKIE['dkgame']);

    $user = prepare('select * from {{ table }} where id=?', 'users', $link);
    $user = execute($user, [$cookie[0]])->fetch();
    return $user;
}

/**
 * Get the user with the given id
 */
function getUserFromId(int $id, $link = null)
{
    $link = openLinkIfNull($link);

    $user = prepare('select * from {{ table }} where id=?', 'users', $link);
    $user = execute($user, [$id])->fetch();
    return $user;
}

function admindisplay($content, $title) { // Finalize page and output to browser.
    
    global $queryCount, $user, $control, $starttime, $version, $build, $link;
    
    $template = gettemplate("admin");
    
    // Make page tags for XHTML validation.
    $xml = "<!DOCTYPE html>\n"
    . "<html lang=\"en\">\n";

    $finalarray = array(
        "title"=>$title,
        "content"=>$content,
        "totaltime"=>round(getmicrotime() - $starttime, 4),
        "numqueries"=>$queryCount,
        "version"=>$version,
        "build"=>$build);
    $page = parsetemplate($template, $finalarray);
    $page = $xml . $page;

    echo $page;
    die();
    
}

function display($content, $title, $topnav=true, $leftnav=true, $rightnav=true, $badstart=false)
{
    global $queryCount, $user, $control, $version, $build, $link;

    if ($badstart == false) { global $starttime; } else { $starttime = $badstart; }
    
    $template = gettemplate("primary");
    
    if ($rightnav == true) { $rightnav = gettemplate("rightnav"); } else { $rightnav = ""; }
    if ($leftnav == true) { $leftnav = gettemplate("leftnav"); } else { $leftnav = ""; }
    if ($topnav == true) {
        $topnav = "<a href=\"users.php?do=logout\" class=\"title swash mr-8\">Log out</a> <a href=\"help.php\" class=\"title swash\">Help</a>";
    } else {
        $topnav = "<a href=\"users.php?do=login\"><img src=\"resources/img/button_login.gif\" alt=\"Log In\" title=\"Log In\" border=\"0\" /></a> <a href=\"users.php?do=register\"><img src=\"resources/img/button_register.gif\" alt=\"Register\" title=\"Register\" border=\"0\" /></a> <a href=\"help.php\"><img src=\"resources/img/button_help.gif\" alt=\"Help\" title=\"Help\" border=\"0\" /></a>";
    }
    
    if (isset($user)) {
        
        // Get userrow again, in case something has been updated.
        $user = quick('select * from {{ table }} where id=?', 'users', [$user['id']], $link)->fetch();
        
        // Current town name.
        if ($user["currentaction"] == "In Town") {
            $townrow = getTown($user['latitude'], $user['longitude'], $link);
            $user["currenttown"] = "Welcome to <b>".$townrow["name"]."</b>.<br /><br />";
        } else {
            $user["currenttown"] = "";
        }
        
        if ($control["forumtype"] == 0) { $user["forumslink"] = ""; }
        elseif ($control["forumtype"] == 1) { $user["forumslink"] = "<a href=\"forum.php\">Forum</a><br />"; }
        elseif ($control["forumtype"] == 2) { $user["forumslink"] = "<a href=\"".$control["forumaddress"]."\">Forum</a><br />"; }
        
        // Format various userrow stuffs...
        if ($user["latitude"] < 0) { $user["latitude"] = $user["latitude"] * -1 . "S"; } else { $user["latitude"] .= "N"; }
        if ($user["longitude"] < 0) { $user["longitude"] = $user["longitude"] * -1 . "W"; } else { $user["longitude"] .= "E"; }
        $user["experience"] = number_format($user["experience"]);
        $user["gold"] = number_format($user["gold"]);
        if ($user["authlevel"] == 1) { $user["adminlink"] = "<a href=\"admin.php\">Admin</a><br />"; } else { $user["adminlink"] = ""; }
        
        // HP/MP/TP bars.
        $stathp = ceil($user["currenthp"] / $user["maxhp"] * 100);
        if ($user["maxmp"] != 0) { $statmp = ceil($user["currentmp"] / $user["maxmp"] * 100); } else { $statmp = 0; }
        $stattp = ceil($user["currenttp"] / $user["maxtp"] * 100);
        $stattable = "<table width=\"100\"><tr><td width=\"33%\">\n";
        $stattable .= "<table cellspacing=\"0\" cellpadding=\"0\"><tr><td style=\"padding:0px; width:15px; height:100px; border:solid 1px black; vertical-align:bottom;\">\n";
        if ($stathp >= 66) { $stattable .= "<div style=\"padding:0px; height:".$stathp."px; border-top:solid 1px black; background-image:url(resources/img/bars_green.gif);\"><img src=\"resources/img/bars_green.gif\" alt=\"\" /></div>"; }
        if ($stathp < 66 && $stathp >= 33) { $stattable .= "<div style=\"padding:0px; height:".$stathp."px; border-top:solid 1px black; background-image:url(resources/img/bars_yellow.gif);\"><img src=\"resources/img/bars_yellow.gif\" alt=\"\" /></div>"; }
        if ($stathp < 33) { $stattable .= "<div style=\"padding:0px; height:".$stathp."px; border-top:solid 1px black; background-image:url(resources/img/bars_red.gif);\"><img src=\"resources/img/bars_red.gif\" alt=\"\" /></div>"; }
        $stattable .= "</td></tr></table></td><td width=\"33%\">\n";
        $stattable .= "<table cellspacing=\"0\" cellpadding=\"0\"><tr><td style=\"padding:0px; width:15px; height:100px; border:solid 1px black; vertical-align:bottom;\">\n";
        if ($statmp >= 66) { $stattable .= "<div style=\"padding:0px; height:".$statmp."px; border-top:solid 1px black; background-image:url(resources/img/bars_green.gif);\"><img src=\"resources/img/bars_green.gif\" alt=\"\" /></div>"; }
        if ($statmp < 66 && $statmp >= 33) { $stattable .= "<div style=\"padding:0px; height:".$statmp."px; border-top:solid 1px black; background-image:url(resources/img/bars_yellow.gif);\"><img src=\"resources/img/bars_yellow.gif\" alt=\"\" /></div>"; }
        if ($statmp < 33) { $stattable .= "<div style=\"padding:0px; height:".$statmp."px; border-top:solid 1px black; background-image:url(resources/img/bars_red.gif);\"><img src=\"resources/img/bars_red.gif\" alt=\"\" /></div>"; }
        $stattable .= "</td></tr></table></td><td width=\"33%\">\n";
        $stattable .= "<table cellspacing=\"0\" cellpadding=\"0\"><tr><td style=\"padding:0px; width:15px; height:100px; border:solid 1px black; vertical-align:bottom;\">\n";
        if ($stattp >= 66) { $stattable .= "<div style=\"padding:0px; height:".$stattp."px; border-top:solid 1px black; background-image:url(resources/img/bars_green.gif);\"><img src=\"resources/img/bars_green.gif\" alt=\"\" /></div>"; }
        if ($stattp < 66 && $stattp >= 33) { $stattable .= "<div style=\"padding:0px; height:".$stattp."px; border-top:solid 1px black; background-image:url(resources/img/bars_yellow.gif);\"><img src=\"resources/img/bars_yellow.gif\" alt=\"\" /></div>"; }
        if ($stattp < 33) { $stattable .= "<div style=\"padding:0px; height:".$stattp."px; border-top:solid 1px black; background-image:url(resources/img/bars_red.gif);\"><img src=\"resources/img/bars_red.gif\" alt=\"\" /></div>"; }
        $stattable .= "</td></tr></table></td>\n";
        $stattable .= "</tr><tr><td>HP</td><td>MP</td><td>TP</td></tr></table>\n";
        $user["statbars"] = $stattable;
        
        // Now make numbers stand out if they're low.
        if ($user["currenthp"] <= ($user["maxhp"]/5)) { $user["currenthp"] = "<blink><span class=\"highlight\"><b>*".$user["currenthp"]."*</b></span></blink>"; }
        if ($user["currentmp"] <= ($user["maxmp"]/5)) { $user["currentmp"] = "<blink><span class=\"highlight\"><b>*".$user["currentmp"]."*</b></span></blink>"; }

        $spellquery = query('select id, name, type from {{ table }}', 'spells', $link);
        $userspells = explode(",",$user["spells"]);
        $user["magiclist"] = "";
        foreach ($spellquery->fetchAll() as $spellrow) {
            $spell = false;
            foreach($userspells as $a => $b) {
                if ($b == $spellrow["id"] && $spellrow["type"] == 1) { $spell = true; }
            }
            if ($spell == true) {
                $user["magiclist"] .= "<a href=\"index.php?do=spell:".$spellrow["id"]."\">".$spellrow["name"]."</a><br />";
            }
        }
        if ($user["magiclist"] == "") { $user["magiclist"] = "None"; }
        
        // Travel To list.
        $townslist = explode(",",$user["towns"]);
        $townquery2 = query('select * from {{ table }}', 'towns', $link);
        $user["townslist"] = "";
        foreach ($townquery2->fetchAll() as $townrow2) {
            $town = false;
            foreach($townslist as $a => $b) {
                if ($b == $townrow2["id"]) { $town = true; }
            }
            if ($town == true) { 
                $user["townslist"] .= "<a href=\"index.php?do=gotown:".$townrow2["id"]."\">".$townrow2["name"]."</a><br />\n"; 
            }
        }
        
    } else {
        $user = array();
    }

    $finalarray = array(
        "dkgamename"=>$control["gamename"],
        "title"=>$title,
        "content"=>$content,
        "rightnav"=>parsetemplate($rightnav,$user),
        "leftnav"=>parsetemplate($leftnav,$user),
        "topnav"=>$topnav,
        "totaltime"=>round(getmicrotime() - $starttime, 4),
        "numqueries"=>$queryCount,
        "version"=>$version,
        "build"=>$build);
    $page = parsetemplate($template, $finalarray);
    
    echo $page;
    die();
}