<!doctype html>
<html lang="en">
<head>
<title><?php echo $control['game_name']; ?> Help</title>
    <link rel="stylesheet" href="resources/css/game.css">
</head>
<body>
<a name="top"></a>
<h1><?php echo $control['game_name']; ?> Help: Items & Drops</h1>
[ <a href="help.php">Return to Help</a> | <a href="index.php">Return to the game</a> ]

<br /><br /><hr />

<table width="60%" style="border: solid 1px black" cellspacing="0" cellpadding="0">
<tr><td colspan="5" bgcolor="#ffffff"><center><b>Items</b></center></td></tr>
<tr><td><b>Type</b></td><td><b>Name</b></td><td><b>Cost</b></td><td><b>Attribute</b></td><td><b>Special</b></td></tr>
<?php
    $count = 1;
    $items = query('select * from {{ table }} order by id', 'items', $link);
    foreach ($items->fetchAll() as $itemsrow) {
        if ($count == 1) { $color = "bgcolor=\"#ffffff\""; $count = 2; } else { $color = ""; $count = 1; }
        if ($itemsrow["type"] == 'weapon') { $image = "weapon"; $power = "Attack"; } elseif ($itemsrow["type"] == 'armor') { $image = "armor"; $power = "Defense"; } else { $image = "shield"; $power = "Defense"; }
        if (!empty($itemsrow["special"])) {
            $special = explode(",",$itemsrow["special"]);
            if ($special[0] == "maxhp") { $attr = "Max HP"; }
            elseif ($special[0] == "maxmp") { $attr = "Max MP"; }
            elseif ($special[0] == "maxtp") { $attr = "Max TP"; }
            elseif ($special[0] == "goldbonus") { $attr = "Gold Bonus (%)"; }
            elseif ($special[0] == "expbonus") { $attr = "Experience Bonus (%)"; }
            elseif ($special[0] == "strength") { $attr = "Strength"; }
            elseif ($special[0] == "dexterity") { $attr = "Dexterity"; }
            elseif ($special[0] == "attackpower") { $attr = "Attack Power"; }
            elseif ($special[0] == "defensepower") { $attr = "Defense Power"; }
            else { $attr = $special[0]; }
            if ($special[1] > 0) { $stat = "+" . $special[1]; } else { $stat = $special[1]; }
            $bigspecial = "$attr $stat";
        } else { $bigspecial = "<span class=\"light\">None</span>"; }
        echo "<tr><td $color width=\"5%\"><img src=\"resources/img/icon_$image.gif\" alt=\"$image\"></td><td $color width=\"30%\">".$itemsrow["name"]."</td><td $color width=\"20%\">".$itemsrow["value"]." Gold</td><td $color width=\"20%\">".$itemsrow["attribute"]." $power Power</td><td $color width=\"25%\">$bigspecial</td></tr>\n";
    }
?>
</table>
<br />
<br />
<table width="60%" style="border: solid 1px black" cellspacing="0" cellpadding="0">
<tr><td colspan="4" bgcolor="#ffffff"><center><b>Drops</b></center></td></tr>
<tr><td><b>Name</b></td><td><b>Monster Level</b></td><td><b>Attribute 1</b></td><td><b>Attribute 2</b></td></tr>
<?php
$count = 1;
$drops = query('select * from {{ table }} order by id', 'drops', $link);
foreach ($drops->fetchAll() as $itemsrow) {
    if ($count == 1) { $color = "bgcolor=\"#ffffff\""; $count = 2; } else { $color = ""; $count = 1; }
    if (! empty($itemsrow["special_1"])) {
        $special1 = explode(",",$itemsrow["special_1"]);
        if ($special1[0] == "maxhp") { $attr1 = "Max HP"; }
        elseif ($special1[0] == "maxmp") { $attr1 = "Max MP"; }
        elseif ($special1[0] == "maxtp") { $attr1 = "Max TP"; }
        elseif ($special1[0] == "goldbonus") { $attr1 = "Gold Bonus (%)"; }
        elseif ($special1[0] == "expbonus") { $attr1 = "Experience Bonus (%)"; }
        elseif ($special1[0] == "strength") { $attr1 = "Strength"; }
        elseif ($special1[0] == "dexterity") { $attr1 = "Dexterity"; }
        elseif ($special1[0] == "attackpower") { $attr1 = "Attack Power"; }
        elseif ($special1[0] == "defensepower") { $attr1 = "Defense Power"; }
        else { $attr1 = $special1[0]; }
        if ($special1[1] > 0) { $stat1 = "+" . $special1[1]; } else { $stat1 = $special1[1]; }
        $bigspecial1 = "$attr1 $stat1";
    } else { $bigspecial1 = "<span class=\"light\">None</span>"; }
    if (! empty($itemsrow["special_2"])) {
        $special2 = explode(",",$itemsrow["special_2"]);
        if ($special2[0] == "maxhp") { $attr2 = "Max HP"; }
        elseif ($special2[0] == "maxmp") { $attr2 = "Max MP"; }
        elseif ($special2[0] == "maxtp") { $attr2 = "Max TP"; }
        elseif ($special2[0] == "goldbonus") { $attr2 = "Gold Bonus (%)"; }
        elseif ($special2[0] == "expbonus") { $attr2 = "Experience Bonus (%)"; }
        elseif ($special2[0] == "strength") { $attr2 = "Strength"; }
        elseif ($special2[0] == "dexterity") { $attr2 = "Dexterity"; }
        elseif ($special2[0] == "attackpower") { $attr2 = "Attack Power"; }
        elseif ($special2[0] == "defensepower") { $attr2 = "Defense Power"; }
        else { $attr2 = $special2[0]; }
        if ($special2[1] > 0) { $stat2 = "+" . $special2[1]; } else { $stat2 = $special2[1]; }
        $bigspecial2 = "$attr2 $stat2";
    } else { $bigspecial2 = "<span class=\"light\">None</span>"; }
    echo "<tr><td $color width=\"25%\">".$itemsrow["name"]."</td><td $color width=\"15%\">".$itemsrow["level"]."</td><td $color width=\"30%\">$bigspecial1</td><td $color width=\"30%\">$bigspecial2</td></tr>\n";
}
?>
</table>
<br />
<table class="copyright" width="100%"><tr>
<td width="50%" align="center">Powered by <a href="http://dragon.se7enet.com/dev.php" target="_new">Dragon Knight</a></td><td width="50%" align="center">&copy; 2003-2006 by renderse7en</td>
</tr></table>
</body>
</html>