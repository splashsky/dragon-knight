<!doctype html>
<html lang="en">
<head>
<title><?php echo $control["gamename"]; ?> Help</title>
    <link rel="stylesheet" href="resources/css/game.css">
</head>
<body>
<a name="top"></a>
<h1><?php echo $control["gamename"]; ?> Help: Monsters</h1>
[ <a href="help.php">Return to Help</a> | <a href="index.php">Return to the game</a> ]

<br /><br /><hr />

<table width="75%" style="border: solid 1px black" cellspacing="0" cellpadding="0">
<tr><td colspan="8" bgcolor="#ffffff"><center><b>Monsters</b></center></td></tr>
<tr><td><b>Name</b></td><td><b>Max HP</b></td><td><b>Max Damage</b></td><td><b>Armor</b></td><td><b>Level</b></td><td><b>Max Exp.</b></td><td><b>Max Gold</b></td><td><b>Immunity</b></td></tr>
<?php
$count = 1;
$monsters = query('select * from {{ table }}', 'monsters', $link);

foreach ($monsters->fetchAll() as $itemsrow) {
    if ($count == 1) { $color = "bgcolor=\"#ffffff\""; $count = 2; } else { $color = ""; $count = 1; }
    if ($itemsrow["immune"] == 0) { $immune = "<span class=\"light\">None</span>"; } elseif ($itemsrow["immune"] == 1) { $immune = "Hurt"; } else { $immune = "Hurt & Sleep"; }
    echo "<tr><td $color width=\"30%\">".$itemsrow["name"]."</td><td $color width=\"10%\">".$itemsrow["maxhp"]."</td><td $color width=\"10%\">".$itemsrow["maxdam"]."</td><td $color width=\"10%\">".$itemsrow["armor"]."</td><td $color width=\"10%\">".$itemsrow["level"]."</td><td $color width=\"10%\">".$itemsrow["maxexp"]."</td><td $color width=\"10%\">".$itemsrow["maxgold"]."</td><td $color width=\"20%\">$immune</td></tr>\n";
}
?>
</table>
<br />
<table class="copyright" width="100%"><tr>
<td width="50%" align="center">Powered by <a href="http://dragon.se7enet.com/dev.php" target="_new">Dragon Knight</a></td><td width="50%" align="center">&copy; 2003-2006 by renderse7en</td>
</tr></table>
</body>
</html>