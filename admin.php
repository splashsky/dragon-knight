<?php // admin.php :: primary administration script.

require 'app/Libs/Helpers.php';
require 'app/Models/Items.php';
require 'app/Models/Drops.php';

$link = openLink();
$control = getControl($link);

// See if the game is closed; die if it is.
dieIfGameClosed($control);

// See if the user is logged in. If not, redirect. If so, get their data.
$user = getUserIfLoggedInByCookie($link);

// Perform usual authentication checks.
redirectIfNotVerified($user['verified'], $control['verify_email']);
dieIfBanned($user['role']);
redirectIfNotAuthorized($user['role'], 'admin');

// Get the requested action, or default to the user's current action.
$do = GET('do', 'default');

if ($do == "main") { main(); }
elseif ($do == "items") { items(); }
elseif ($do == "edititem") { edititem($do[1]); }
elseif ($do == "drops") { drops(); }
elseif ($do == "editdrop") { editdrop($do[1]); }
elseif ($do == "towns") { towns(); }
elseif ($do == "edittown") { edittown($do[1]); }
elseif ($do == "monsters") { monsters(); }
elseif ($do == "editmonster") { editmonster($do[1]); }
elseif ($do == "levels") { levels(); }
elseif ($do == "editlevel") { editlevel(); }
elseif ($do == "spells") { spells(); }
elseif ($do == "editspell") { editspell($do[1]); }
elseif ($do == "users") { users(); }
elseif ($do == "edituser") { editUser(); }
elseif ($do == "news") { news(); }
elseif ($do == 'test') { test(); }
else { intro(); }

function test()
{
    $page = gettemplate('admin/intro');
    echo buildAdmin($page, 'Test', 'new message', 'dark');
}

function intro()
{
    $page = gettemplate('admin/intro');
    buildAdmin($page, 'Intro');
}

function getMainSelections(array $data)
{
    // Forum type selection
    $data['selecttype0'] = $data['forum_type'] == 0 ? 'selected' : ''; 
    $data['selecttype1'] = $data['forum_type'] == 1 ? 'selected' : ''; 
    $data['selecttype2'] = $data['forum_type'] == 2 ? 'selected' : '';

    // Email verification selection
    $data['selectverify0'] = $data['verify_email'] == 0 ? 'selected' : '';
    $data['selectverify1'] = $data['verify_email'] == 1 ? 'selected' : '';

    // Show news selection
    $data['selectnews0'] = $data['show_news'] == 0 ? 'selected' : '';
    $data['selectnews1'] = $data['show_news'] == 1 ? 'selected' : '';

    // Show who's online selection
    $data['selectonline0'] = $data['show_online'] == 0 ? 'selected' : '';
    $data['selectonline1'] = $data['show_online'] == 1 ? 'selected' : '';

    // Show babblebox selection
    $data['selectbabble0'] = $data['show_babble'] == 0 ? 'selected' : '';
    $data['selectbabble1'] = $data['show_babble'] == 1 ? 'selected' : '';

    // Game open selection
    $data['open0select'] = $data['game_open'] == 0 ? 'selected' : '';
    $data['open1select'] = $data['game_open'] == 1 ? 'selected' : '';

    return $data;
}

function generateAuthLevelList($userAuth)
{
    $levels = config('auth');
    $list = '';
    $count = 0;

    foreach ($levels as $key => $val) {
        $current = $userAuth == $val ? 'selected' : '';
        $tag = ucfirst($key);
        $list .= "<option value=\"{$count}\" {$current}>{$tag}</option>";
        $count++;
    }

    return $list;
}

function main()
{
    global $control, $link;

    $page = gettemplate('admin/main');
    $title = 'Main Settings';

    if (isset($_POST["submit"])) {
        extract($_POST);

        $data = getMainSelections($_POST);
        $page = parsetemplate($page, $data);

        $errors = '';
        if ($game_name == '') { $errors .= "Game name is required.<br />"; }
        if (($game_size % 5) != 0) { $errors .= "Map size must be divisible by five.<br />"; }
        if (! is_numeric($game_size)) { $errors .= "Map size must be a number.<br />"; }
        if ($forum_type == 2 && $forum_address == '') { $errors .= "You must specify a forum address when using the External setting.<br />"; }
        
        if (! empty($errors)) {
            buildAdmin($page, $title, $errors, 'error');
            return;
        }

        $query = prepare("update {{ table }} set game_name=?, game_size=?, forum_type=?, forum_address=?, game_open=?, verify_email=?, game_url=?, admin_email=?, show_news=?, show_online=?, show_babble=? WHERE id='1'", 'control', $link);
        execute($query, [
            $game_name,
            $game_size,
            $forum_type,
            $forum_address,
            $game_open,
            $verify_email,
            $game_url,
            $admin_email,
            $show_news,
            $show_online,
            $show_babble
        ]);

        buildAdmin($page, $title, 'Successfully updated.', 'success');
        return;
    }

    $control = getMainSelections($control);

    $page = parsetemplate($page, $control);
    buildAdmin($page, $title);
    return;
}

function items()
{
    global $link;

    $query = query('select id, name from {{ table }}', 'items', $link);
    $page = "<b><u>Edit Items</u></b><br />Click an item's name to edit it.<br /><br /><table width=\"50%\">\n";
    $count = 1;
    $items = $query->fetchAll();

    if (count($items) > 0) {
        foreach ($items as $row) {
            if ($count == 1) { $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">".$row["id"]."</td><td style=\"background-color: #eeeeee;\"><a href=\"admin.php?do=edititem:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 2; }
            else { $page .= "<tr><td width=\"8%\" style=\"background-color: #ffffff;\">".$row["id"]."</td><td style=\"background-color: #ffffff;\"><a href=\"admin.php?do=edititem:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 1; }
        }
    } else {
        $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">No items found.</td></tr>\n";
    }
    
    $page .= "</table>";
    buildAdmin($page, "Edit Items");
}

function edititem($id)
{
    global $link;

    if (isset($_POST["submit"])) {
        $data = trimData($_POST);
        
        $errors = '';

        if ($data['name'] == '') { $errors .= "Name is required.<br />"; }
        if ($data['buycost'] == '') { $errors .= "Cost is required.<br />"; }
        if (!is_numeric($data['buycost'])) { $errors .= "Cost must be a number.<br />"; }
        if ($data['attribute'] == '') { $errors .= "Attribute is required.<br />"; }
        if (!is_numeric($data['attribute'])) { $errors .= "Attribute must be a number.<br />"; }

        if ($data['special'] == '' || $data['special'] == " ") { $data['special'] = "X"; }
        
        if (! empty($errorlist)) {
            buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit Items");
        }

        $query = prepare('update {{ table }} set name=?, type=?, buycost=?, attribute=?, special=? where id=?', 'items', $link);
        execute($query, [$data['name'], $data['type'], $data['buycost'], $data['attribute'], $data['special'], $id]);
        
        buildAdmin("Item updated.","Edit Items");
    }   
        
    $row = quick('select * from {{ table }} where id=?', 'items', [$id], $link)->fetch();

    $page = gettemplate('admin/editItem');
    
    if ($row["type"] == 1) { $row["type1select"] = 'selected'; } else { $row["type1select"] = ''; }
    if ($row["type"] == 2) { $row["type2select"] = 'selected'; } else { $row["type2select"] = ''; }
    if ($row["type"] == 3) { $row["type3select"] = 'selected'; } else { $row["type3select"] = ''; }
    
    $page = parsetemplate($page, $row);
    buildAdmin($page, "Edit Items");
}

function drops()
{
    global $link;

    $query = query('select id, name from {{ table }}', 'drops', $link);
    $page = "<b><u>Edit Drops</u></b><br />Click an item's name to edit it.<br /><br /><table width=\"50%\">\n";
    $count = 1;
    $drops = $query->fetchAll();

    if ($drops && count($drops) > 0) {
        foreach ($drops as $row) {
            if ($count == 1) { $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">".$row["id"]."</td><td style=\"background-color: #eeeeee;\"><a href=\"admin.php?do=editdrop:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 2; }
            else { $page .= "<tr><td width=\"8%\" style=\"background-color: #ffffff;\">".$row["id"]."</td><td style=\"background-color: #ffffff;\"><a href=\"admin.php?do=editdrop:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 1; }
        }
    } else {
        $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">No drops found.</td></tr>\n";
    }

    $page .= "</table>";
    buildAdmin($page, "Edit Drops");
}

function editdrop($id)
{
    global $link;

    if (isset($_POST["submit"])) {
        extract($_POST);
        $errorlist = '';

        if ($name == '') { $errors .= "Name is required.<br />"; }
        if ($mlevel == '') { $errors .= "Monster level is required.<br />"; }
        if (!is_numeric($mlevel)) { $errors .= "Monster level must be a number.<br />"; }
        if ($attribute1 == '' || $attribute1 == " " || $attribute1 == "X") { $errors .= "First attribute is required.<br />"; }

        if ($attribute2 == '' || $attribute2 == " ") { $attribute2 = "X"; }
        
        if (! empty($errorlist)) {
            buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit Drops");
        }

        $query = prepare('update {{ table }} set name=?, mlevel=?, attribute1=?, attribute2=? where id=?', 'drops', $link);
        execute($query, [$name, $mlevel, $attribute1, $attribute2, $id]);
        
        buildAdmin("Drop updated.","Edit Drops");
    }
    
    $row = quick('select * from {{ table }} where id=?', 'drops', [$id], $link)->fetch();

    $page = gettemplate('admin/editDrop');
    $page = parsetemplate($page, $row);

    buildAdmin($page, "Edit Drops");
}

function towns()
{
    global $link;

    $query = query('select id, name from {{ table }}', 'towns', $link);
    $page = "<b><u>Edit Towns</u></b><br />Click a town's name to edit it.<br /><br /><table width=\"50%\">\n";
    $count = 1;
    $towns = $query->fetchAll();

    if ($towns && count($towns) > 0) {
        foreach ($towns as $row) {
            if ($count == 1) { $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">".$row["id"]."</td><td style=\"background-color: #eeeeee;\"><a href=\"admin.php?do=edittown:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 2; }
            else { $page .= "<tr><td width=\"8%\" style=\"background-color: #ffffff;\">".$row["id"]."</td><td style=\"background-color: #ffffff;\"><a href=\"admin.php?do=edittown:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 1; }
        }
    } else {
        $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">No towns found.</td></tr>\n";
    }
    
    $page .= "</table>";
    buildAdmin($page, "Edit Towns");
}

function edittown($id)
{
    global $link;

    if (isset($_POST["submit"])) {
        extract($_POST);
        $errors = 0;
        $errorlist = '';
        if ($name == '') { $errors .= "Name is required.<br />"; }
        if ($latitude == '') { $errors .= "Latitude is required.<br />"; }
        if (!is_numeric($latitude)) { $errors .= "Latitude must be a number.<br />"; }
        if ($longitude == '') { $errors .= "Longitude is required.<br />"; }
        if (!is_numeric($longitude)) { $errors .= "Longitude must be a number.<br />"; }
        if ($innprice == '') { $errors .= "Inn Price is required.<br />"; }
        if (!is_numeric($innprice)) { $errors .= "Inn Price must be a number.<br />"; }
        if ($mapprice == '') { $errors .= "Map Price is required.<br />"; }
        if (!is_numeric($mapprice)) { $errors .= "Map Price must be a number.<br />"; }

        if ($travelpoints == '') { $errors .= "Travel Points is required.<br />"; }
        if (!is_numeric($travelpoints)) { $errors .= "Travel Points must be a number.<br />"; }
        if ($itemslist == '') { $errors .= "Items List is required.<br />"; }
        
        if ($errors == 0) {
            $query = prepare('update {{ table }} set name=?, latitude=?, longitude=?, innprice=?, mapprice=?, travelpoints=?, itemslist=? where id=?', 'towns', $link);
            execute($query, [$name, $latitude, $longitude, $innprice, $mapprice, $travelpoints, $itemslist, $id]);

            buildAdmin("Town updated.","Edit Towns");
        }
        
        buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit Towns");
    }
    
    $row = quick('select * from {{ table }} where id=?', 'towns', [$id], $link)->fetch();

    $page = gettemplate('admin/editTown');
    $page = parsetemplate($page, $row);

    buildAdmin($page, "Edit Towns");
}

function monsters()
{
    global $control, $link;
    
    $statrow = query('select * from {{ table }} order by level desc limit 1', 'monsters', $link)->fetch();
    $query = query('select id, name from {{ table }}', 'monsters', $link);

    $page = "<b><u>Edit Monsters</u></b><br />";
    
    if (($control["gamesize"] / 5) != $statrow["level"]) {
        $page .= "<span class=\"highlight\">Note:</span> Your highest monster level does not match with your entered map size. Highest monster level should be ".($control["gamesize"]/5).", yours is ".$statrow["level"].". Please fix this before opening the game to the public.<br /><br />";
    } else { $page .= "Monster level and map size match. No further actions are required for map compatibility.<br /><br />"; }
    
    $page .= "Click a monster's name to edit it.<br /><br /><table width=\"50%\">\n";
    $count = 1;
    $monsters = $query->fetchAll();

    if($monsters && count($monsters) > 0) {
        foreach ($monsters as $row) {
            if ($count == 1) { $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">".$row["id"]."</td><td style=\"background-color: #eeeeee;\"><a href=\"admin.php?do=editmonster:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 2; }
            else { $page .= "<tr><td width=\"8%\" style=\"background-color: #ffffff;\">".$row["id"]."</td><td style=\"background-color: #ffffff;\"><a href=\"admin.php?do=editmonster:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 1; }
        }
    } else {
        $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">No towns found.</td></tr>\n";
    }

    $page .= "</table>";

    buildAdmin($page, "Edit Monster");
}

function editmonster($id)
{
    global $link;

    if (isset($_POST["submit"])) {
        extract($_POST);
        $errors = 0;
        $errorlist = '';
        if ($name == '') { $errors .= "Name is required.<br />"; }
        if ($maxhp == '') { $errors .= "Max HP is required.<br />"; }
        if (!is_numeric($maxhp)) { $errors .= "Max HP must be a number.<br />"; }
        if ($maxdam == '') { $errors .= "Max Damage is required.<br />"; }
        if (!is_numeric($maxdam)) { $errors .= "Max Damage must be a number.<br />"; }
        if ($armor == '') { $errors .= "Armor is required.<br />"; }
        if (!is_numeric($armor)) { $errors .= "Armor must be a number.<br />"; }
        if ($level == '') { $errors .= "Monster Level is required.<br />"; }
        if (!is_numeric($level)) { $errors .= "Monster Level must be a number.<br />"; }
        if ($maxexp == '') { $errors .= "Max Exp is required.<br />"; }
        if (!is_numeric($maxexp)) { $errors .= "Max Exp must be a number.<br />"; }
        if ($maxgold == '') { $errors .= "Max Gold is required.<br />"; }
        if (!is_numeric($maxgold)) { $errors .= "Max Gold must be a number.<br />"; }
        
        if (! empty($errorlist)) {
            buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit monsters");
        }

        $query = prepare('update {{ table }} set name=?, maxhp=?, maxdam=?, armor=?, level=?, maxexp=?, maxgold=?, immune=? where id=?', 'monsters', $link);
        execute($query, [$name, $maxhp, $maxdam, $armor, $level, $maxexp, $maxgold, $immune, $id]);
        
        buildAdmin("Monster updated.","Edit monsters");
    }   
        
    $row = quick('select * from {{ table }} where id=?', 'monsters', [$id], $link)->fetch();
    $page = gettemplate('admin/editMonster');
    
    if ($row["immune"] == 1) { $row["immune1select"] = 'selected'; } else { $row["immune1select"] = ''; }
    if ($row["immune"] == 2) { $row["immune2select"] = 'selected'; } else { $row["immune2select"] = ''; }
    if ($row["immune"] == 3) { $row["immune3select"] = 'selected'; } else { $row["immune3select"] = ''; }
    
    $page = parsetemplate($page, $row);
    buildAdmin($page, "Edit Monsters");
}

function spells()
{
    global $link;

    $query = query('select id, name from {{ table }}', 'spells', $link);
    $page = "<b><u>Edit Spells</u></b><br />Click a spell's name to edit it.<br /><br /><table width=\"50%\">\n";
    $count = 1;
    $spells = $query->fetchAll();

    if ($spells && count($spells) > 0) {
        foreach ($spells as $row) {
            if ($count == 1) { $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">".$row["id"]."</td><td style=\"background-color: #eeeeee;\"><a href=\"admin.php?do=editspell:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 2; }
            else { $page .= "<tr><td width=\"8%\" style=\"background-color: #ffffff;\">".$row["id"]."</td><td style=\"background-color: #ffffff;\"><a href=\"admin.php?do=editspell:".$row["id"]."\">".$row["name"]."</a></td></tr>\n"; $count = 1; }
        }
    } else {
        $page .= "<tr><td width=\"8%\" style=\"background-color: #eeeeee;\">No spells found.</td></tr>\n";
    }

    $page .= "</table>";

    buildAdmin($page, "Edit Spells");
}

function editspell($id)
{
    global $link;

    if (isset($_POST["submit"])) {
        extract($_POST);
        $errors = 0;
        $errorlist = '';

        if ($name == '') { $errors .= "Name is required.<br />"; }
        if ($mp == '') { $errors .= "MP is required.<br />"; }
        if (!is_numeric($mp)) { $errors .= "MP must be a number.<br />"; }
        if ($attribute == '') { $errors .= "Attribute is required.<br />"; }
        if (!is_numeric($attribute)) { $errors .= "Attribute must be a number.<br />"; }
        
        if (! empty($errorlist)) {
            buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit Spells");
        }

        $query = prepare('update {{ table }} set name=?, mp=?, attribute=?, type=? where id=?', 'spells', $link);
        execute($query, [$name, $mp, $attribute, $type, $id]);
        
        buildAdmin("Spell updated.","Edit Spells");
    }   
        
    $row = quick('select * from {{ table }} where id=?', 'spells', [$id], $link)->fetch();

    $page = gettemplate('admin/editSpell');

    if ($row["type"] == 1) { $row["type1select"] = 'selected'; } else { $row["type1select"] = ''; }
    if ($row["type"] == 2) { $row["type2select"] = 'selected'; } else { $row["type2select"] = ''; }
    if ($row["type"] == 3) { $row["type3select"] = 'selected'; } else { $row["type3select"] = ''; }
    if ($row["type"] == 4) { $row["type4select"] = 'selected'; } else { $row["type4select"] = ''; }
    if ($row["type"] == 5) { $row["type5select"] = 'selected'; } else { $row["type5select"] = ''; }
    
    $page = parsetemplate($page, $row);

    buildAdmin($page, "Edit Spells");
}

function levels()
{
    global $link;

    $row = query('select id from {{ table }} order by id desc limit 1', 'levels', $link)->fetch();
    
    $options = '';
    for($i = 2; $i < $row["id"]; $i++) {
        $options .= "<option value=\"{$i}\">{$i}</option>\n";
    }
    
    $page = gettemplate('admin/levelsDropdown');
    $page = parsetemplate($page, ['options' => $options]);

    buildAdmin($page, "Edit Levels");
}

function editlevel()
{
    global $link, $control;

    if (!isset($_POST["level"])) { buildAdmin("No level to edit.", "Edit Levels"); }
    $id = $_POST["level"];
    
    if (isset($_POST["submit"])) {
        extract($_POST);
        $errors = 0;
        $errorlist = '';
        if ($_POST["one_exp"] == '') { $errors .= "Class 1 Experience is required.<br />"; }
        if ($_POST["one_hp"] == '') { $errors .= "Class 1 HP is required.<br />"; }
        if ($_POST["one_mp"] == '') { $errors .= "Class 1 MP is required.<br />"; }
        if ($_POST["one_tp"] == '') { $errors .= "Class 1 TP is required.<br />"; }
        if ($_POST["one_strength"] == '') { $errors .= "Class 1 Strength is required.<br />"; }
        if ($_POST["one_dexterity"] == '') { $errors .= "Class 1 Dexterity is required.<br />"; }
        if ($_POST["one_spells"] == '') { $errors .= "Class 1 Spells is required.<br />"; }
        if (!is_numeric($_POST["one_exp"])) { $errors .= "Class 1 Experience must be a number.<br />"; }
        if (!is_numeric($_POST["one_hp"])) { $errors .= "Class 1 HP must be a number.<br />"; }
        if (!is_numeric($_POST["one_mp"])) { $errors .= "Class 1 MP must be a number.<br />"; }
        if (!is_numeric($_POST["one_tp"])) { $errors .= "Class 1 TP must be a number.<br />"; }
        if (!is_numeric($_POST["one_strength"])) { $errors .= "Class 1 Strength must be a number.<br />"; }
        if (!is_numeric($_POST["one_dexterity"])) { $errors .= "Class 1 Dexterity must be a number.<br />"; }
        if (!is_numeric($_POST["one_spells"])) { $errors .= "Class 1 Spells must be a number.<br />"; }

        if ($_POST["two_exp"] == '') { $errors .= "Class 2 Experience is required.<br />"; }
        if ($_POST["two_hp"] == '') { $errors .= "Class 2 HP is required.<br />"; }
        if ($_POST["two_mp"] == '') { $errors .= "Class 2 MP is required.<br />"; }
        if ($_POST["two_tp"] == '') { $errors .= "Class 2 TP is required.<br />"; }
        if ($_POST["two_strength"] == '') { $errors .= "Class 2 Strength is required.<br />"; }
        if ($_POST["two_dexterity"] == '') { $errors .= "Class 2 Dexterity is required.<br />"; }
        if ($_POST["two_spells"] == '') { $errors .= "Class 2 Spells is required.<br />"; }
        if (!is_numeric($_POST["two_exp"])) { $errors .= "Class 2 Experience must be a number.<br />"; }
        if (!is_numeric($_POST["two_hp"])) { $errors .= "Class 2 HP must be a number.<br />"; }
        if (!is_numeric($_POST["two_mp"])) { $errors .= "Class 2 MP must be a number.<br />"; }
        if (!is_numeric($_POST["two_tp"])) { $errors .= "Class 2 TP must be a number.<br />"; }
        if (!is_numeric($_POST["two_strength"])) { $errors .= "Class 2 Strength must be a number.<br />"; }
        if (!is_numeric($_POST["two_dexterity"])) { $errors .= "Class 2 Dexterity must be a number.<br />"; }
        if (!is_numeric($_POST["two_spells"])) { $errors .= "Class 2 Spells must be a number.<br />"; }
                
        if ($_POST["three_exp"] == '') { $errors .= "Class 3 Experience is required.<br />"; }
        if ($_POST["three_hp"] == '') { $errors .= "Class 3 HP is required.<br />"; }
        if ($_POST["three_mp"] == '') { $errors .= "Class 3 MP is required.<br />"; }
        if ($_POST["three_tp"] == '') { $errors .= "Class 3 TP is required.<br />"; }
        if ($_POST["three_strength"] == '') { $errors .= "Class 3 Strength is required.<br />"; }
        if ($_POST["three_dexterity"] == '') { $errors .= "Class 3 Dexterity is required.<br />"; }
        if ($_POST["three_spells"] == '') { $errors .= "Class 3 Spells is required.<br />"; }
        if (!is_numeric($_POST["three_exp"])) { $errors .= "Class 3 Experience must be a number.<br />"; }
        if (!is_numeric($_POST["three_hp"])) { $errors .= "Class 3 HP must be a number.<br />"; }
        if (!is_numeric($_POST["three_mp"])) { $errors .= "Class 3 MP must be a number.<br />"; }
        if (!is_numeric($_POST["three_tp"])) { $errors .= "Class 3 TP must be a number.<br />"; }
        if (!is_numeric($_POST["three_strength"])) { $errors .= "Class 3 Strength must be a number.<br />"; }
        if (!is_numeric($_POST["three_dexterity"])) { $errors .= "Class 3 Dexterity must be a number.<br />"; }
        if (!is_numeric($_POST["three_spells"])) { $errors .= "Class 3 Spells must be a number.<br />"; }

        if (! empty($errorlist)) {
            buildAdmin("<b>Errors:</b><br /><div style=\"color:red;\">$errorlist</div><br />Please go back and try again.", "Edit Spells");
        }

        $query = "update {{ table }} set
            1_exp=?, 1_hp=?, 1_mp=?, 1_tp=?, 1_strength=?, 1_dexterity=?, 1_spells=?,
            2_exp=?, 2_hp=?, 2_mp=?, 2_tp=?, 2_strength=?, 2_dexterity=?, 2_spells=?,
            3_exp=?, 3_hp=?, 3_mp=?, 3_tp=?, 3_strength=?, 3_dexterity=?, 3_spells=?
            WHERE id=?";
        $data = [
            $one_exp, $one_hp, $one_mp, $one_tp, $one_strength, $one_dexterity, $one_spells,
            $two_exp, $two_hp, $two_mp, $two_tp, $two_strength, $two_dexterity, $two_spells,
            $three_exp, $three_hp, $three_mp, $three_tp, $three_strength, $three_dexterity, $three_spells,
            $id
        ];
        
        quick($query, 'levels', $data, $link);

        buildAdmin("Level updated.","Edit Levels");
    }   
        
    $row = quick('select * from {{ table }} where id=?', 'levels', [$id], $link)->fetch();

    $row['class1name'] = $control["class1name"];
    $row['class2name'] = $control["class2name"];
    $row['class3name'] = $control["class3name"];

    $page = gettemplate('admin/editLevel');
    $page = parsetemplate($page, $row);

    buildAdmin($page, "Edit Levels");
}

function users()
{
    global $link;

    $page = gettemplate('admin/userList');
    $query = query('select id, username from {{ table }}', 'users', $link);
    $users = $query->fetchAll();
    $list = '';

    if ($users && count($users) > 0) {
        foreach ($users as $user) {
            $list .= "<tr><td class=\"pr-8\">{$user->id}</td> <td class=\"pb-4\"><a href=\"admin.php?do=edituser&user={$user->id}\">{$user['username']}</a></td></tr>";
        }
    } else {
        $list = '<tr><td>No users found.</td></tr>';
    }

    $page = parsetemplate($page, ['list' => $list]);
    buildAdmin($page, 'Edit Users');
}

function editUser()
{
    global $link, $control;

    // Get the user id we're working on, otherwise redirect to the user list
    $id = GET('user', fn() => redirect('admin.php?do=user'));

    $row = getUserFromId($id, $link);

    $row['diff1name'] = $control["diff1name"];
    $row['diff2name'] = $control["diff2name"];
    $row['diff3name'] = $control["diff3name"];
    $row['class1name'] = $control["class1name"];
    $row['class2name'] = $control["class2name"];
    $row['class3name'] = $control["class3name"];

    $page = gettemplate('admin/editUser');
    $title = "Edit {$row['username']}";

    if (isset($_POST['resetData'])) {
        $query = "update {{ table }} set currentaction='In Town', latitude='0', longitude='0', currentfight='0' where id=?";
        quick($query, 'users', [$id], $link);

        $row = getUserFromId($id, $link);

        $row['diff1name'] = $control["diff1name"];
        $row['diff2name'] = $control["diff2name"];
        $row['diff3name'] = $control["diff3name"];
        $row['class1name'] = $control["class1name"];
        $row['class2name'] = $control["class2name"];
        $row['class3name'] = $control["class3name"];

        $page = parsetemplate($page, $row);
        buildAdmin($page, $title, 'Player reset.');
        return;
    }

    if (isset($_POST["submit"])) {
        $data = trimData($_POST);
        extract($data);
        
        $errors = '';
        if ($email == '') { $errors .= "Email is required.<br />"; }
        if ($verify == '') { $errors .= "Verify is required.<br />"; }
        if ($authlevel == '') { $errors .= "Auth Level is required.<br />"; }
        if ($latitude == '') { $errors .= "Latitude is required.<br />"; }
        if ($longitude == '') { $errors .= "Longitude is required.<br />"; }
        if ($difficulty == '') { $errors .= "Difficulty is required.<br />"; }
        if ($class == '') { $errors .= "Character Class is required.<br />"; }

        if ($currenthp == '') { $errors .= "Current HP is required.<br />"; }
        if ($currentmp == '') { $errors .= "Current MP is required.<br />"; }
        if ($currenttp == '') { $errors .= "Current TP is required.<br />"; }
        if ($maxhp == '') { $errors .= "Max HP is required.<br />"; }

        if ($maxmp == '') { $errors .= "Max MP is required.<br />"; }
        if ($maxtp == '') { $errors .= "Max TP is required.<br />"; }
        if ($level == '') { $errors .= "Level is required.<br />"; }
        if ($gold == '') { $errors .= "Gold is required.<br />"; }
        if ($experience == '') { $errors .= "Experience is required.<br />"; }
        if ($goldbonus == '') { $errors .= "Gold Bonus is required.<br />"; }
        if ($expbonus == '') { $errors .= "Experience Bonus is required.<br />"; }
        if ($strength == '') { $errors .= "Strength is required.<br />"; }
        if ($dexterity == '') { $errors .= "Dexterity is required.<br />"; }
        if ($attackpower == '') { $errors .= "Attack Power is required.<br />"; }
        if ($defensepower == '') { $errors .= "Defense Power is required.<br />"; }

        if ($weaponid == '') { $errors .= "Weapon ID is required.<br />"; }
        if ($armorid == '') { $errors .= "Armor ID is required.<br />"; }
        if ($shieldid == '') { $errors .= "Shield ID is required.<br />"; }
        if ($slot1id == '') { $errors .= "Slot 1 ID is required.<br />"; }
        if ($slot2id == '') { $errors .= "Slot 2 ID is required.<br />"; }
        if ($slot3id == '') { $errors .= "Slot 3 ID is required.<br />"; }

        if ($spells == '') { $errors .= "Spells is required.<br />"; }
        if ($towns == '') { $errors .= "Towns is required.<br />"; }
        
        if (!is_numeric($authlevel)) { $errors .= "Auth Level must be a number.<br />"; }
        if (!is_numeric($latitude)) { $errors .= "Latitude must be a number.<br />"; }
        if (!is_numeric($longitude)) { $errors .= "Longitude must be a number.<br />"; }
        if (!is_numeric($difficulty)) { $errors .= "Difficulty must be a number.<br />"; }
        if (!is_numeric($class)) { $errors .= "Character Class must be a number.<br />"; }

        if (!is_numeric($currenthp)) { $errors .= "Current HP must be a number.<br />"; }
        if (!is_numeric($currentmp)) { $errors .= "Current MP must be a number.<br />"; }
        if (!is_numeric($currenttp)) { $errors .= "Current TP must be a number.<br />"; }
        if (!is_numeric($maxhp)) { $errors .= "Max HP must be a number.<br />"; }
        if (!is_numeric($maxmp)) { $errors .= "Max MP must be a number.<br />"; }
        if (!is_numeric($maxtp)) { $errors .= "Max TP must be a number.<br />"; }
        if (!is_numeric($level)) { $errors .= "Level must be a number.<br />"; }
        
        if (!is_numeric($gold)) { $errors .= "Gold must be a number.<br />"; }
        if (!is_numeric($experience)) { $errors .= "Experience must be a number.<br />"; }
        if (!is_numeric($goldbonus)) { $errors .= "Gold Bonus must be a number.<br />"; }
        if (!is_numeric($expbonus)) { $errors .= "Experience Bonus must be a number.<br />"; }
        if (!is_numeric($strength)) { $errors .= "Strength must be a number.<br />"; }
        if (!is_numeric($dexterity)) { $errors .= "Dexterity must be a number.<br />"; }
        if (!is_numeric($attackpower)) { $errors .= "Attack Power must be a number.<br />"; }
        if (!is_numeric($defensepower)) { $errors .= "Defense Power must be a number.<br />"; }
        if (!is_numeric($weaponid)) { $errors .= "Weapon ID must be a number.<br />"; }
        if (!is_numeric($armorid)) { $errors .= "Armor ID must be a number.<br />"; }
        
        if (!is_numeric($shieldid)) { $errors .= "Shield ID must be a number.<br />"; }
        if (!is_numeric($slot1id)) { $errors .= "Slot 1 ID  must be a number.<br />"; }
        if (!is_numeric($slot2id)) { $errors .= "Slot 2 ID must be a number.<br />"; }
        if (!is_numeric($slot3id)) { $errors .= "Slot 3 ID must be a number.<br />"; }

        $data['verified'] = $row['verify'] == 1 ? 'checked' : '';
        $data['notverified'] = $row['verify'] == 0 ? 'checked' : '';

        $data['authlevellist'] = generateAuthLevelList($row['authlevel']);
        
        if (! empty($errors)) {
            $data = array_merge($data, $row);
            $page = parsetemplate($page, $data);
            buildAdmin($page, $title, $errors, 'error');
            return;
        }

        $weaponname = getItemNameById($weaponid);
        $armorname = getItemNameById($armorid);
        $shieldname = getItemNameById($shieldid);
        $slot1name = getDropNameById($slot1id);
        $slot2name = getDropNameById($slot2id);
        $slot3name = getDropNameById($slot3id);

        $query = "update {{ table }} set
            email=?, verify=?, authlevel=?, latitude=?, longitude=?, difficulty=?, class=?, currenthp=?, currentmp=?, currenttp=?, 
            maxhp=?, maxmp=?, maxtp=?, level=?, gold=?, experience=?, goldbonus=?, expbonus=?, strength=?, dexterity=?, attackpower=?, 
            defensepower=?, weaponid=?, armorid=?, shieldid=?, slot1id=?, slot2id=?, slot3id=?, weaponname=?, armorname=?, shieldname=?, 
            slot1name=?, slot2name=?, slot3name=?, spells=?, towns=? WHERE id=?";
        $queryData = [
            $email, $verify, $authlevel, $latitude, $longitude, $difficulty, $class, $currenthp, $currentmp, $currenttp, 
            $maxhp, $maxmp, $maxtp, $level, $gold, $experience, $goldbonus, $expbonus, $strength, $dexterity, $attackpower, 
            $defensepower, $weaponid, $armorid, $shieldid, $slot1id, $slot2id, $slot3id, $weaponname, $armorname, $shieldname, 
            $slot1name, $slot2name, $slot3name, $spells, $towns, $id
        ];

        quick($query, 'users', $queryData, $link);

        $data = array_merge($data, $row);
        $page = parsetemplate($page, $data);
        buildAdmin($page, $title, 'User updated!', 'success');
        return;
    }

    if ($row["authlevel"] == 0) { $row["auth0select"] = 'selected'; } else { $row["auth0select"] = ''; }
    if ($row["authlevel"] == 1) { $row["auth1select"] = 'selected'; } else { $row["auth1select"] = ''; }
    if ($row["authlevel"] == 2) { $row["auth2select"] = 'selected'; } else { $row["auth2select"] = ''; }
    if ($row["class"] == 1) { $row["class1select"] = 'selected'; } else { $row["class1select"] = ''; }
    if ($row["class"] == 2) { $row["class2select"] = 'selected'; } else { $row["class2select"] = ''; }
    if ($row["class"] == 3) { $row["class3select"] = 'selected'; } else { $row["class3select"] = ''; }
    if ($row["difficulty"] == 1) { $row["diff1select"] = 'selected'; } else { $row["diff1select"] = ''; }
    if ($row["difficulty"] == 2) { $row["diff2select"] = 'selected'; } else { $row["diff2select"] = ''; }
    if ($row["difficulty"] == 3) { $row["diff3select"] = 'selected'; } else { $row["diff3select"] = ''; }

    $row['verified'] = $row['verify'] == 1 ? 'checked' : '';
    $row['notverified'] = $row['verify'] == 0 ? 'checked' : '';

    $row['authlevellist'] = generateAuthLevelList($row['authlevel']);
    
    $page = parsetemplate($page, $row);
    buildAdmin($page, $title);
}

function news()
{
    global $link, $user;

    $page = gettemplate('admin/addNews');
    $title = 'Add News';

    if (isset($_POST["submit"])) {
        $content = trim($_POST['content']);

        $errors = empty($content) ? 'Content is required.' : '';
        
        if (! empty($errors)) {
            buildAdmin($page, $title, $errors, 'error');
            return;
        }

        $query = prepare('insert into {{ table }} set user_id=?, posted=now(), content=?', 'news', $link);
        execute($query, [$user->id, $content]);

        buildAdmin($page, $title, 'News post added.', 'success');
        return;
    }
    
    buildAdmin($page, $title);
}

/**
 * Build and display the admin page, with proper content
 * and title.
 */
function buildAdmin(string $content, string $title, string $flash = '', string $flashType = 'info')
{
    global $queries, $start, $version, $build, $control;
    
    $template = gettemplate('admin/layout');

    $flash = ! empty($flash) ? generateFlash($flash, $flashType) : '';

    $data = [
        'title' => $title,
        'content' => $content,
        'flash' => $flash,
        'flashType' => $flashType,
        'game' => $control['game_name'],
        'time' => round(getmicrotime() - $start, 4),
        'queries' => $queries,
        'version' => $version,
        'build' => $build
    ];

    $page = parsetemplate($template, $data);
    echo $page;
}