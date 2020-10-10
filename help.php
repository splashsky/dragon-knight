<?php

require 'app/Libs/Helpers.php'; 

$link = openLink();
$control = getControl($link);

$with = isset($_GET['with']) ? $_GET['with'] : 'main';
$pages = ['main', 'items', 'monsters', 'spells', 'levels'];

if (! in_array($with, $pages)) { $with = 'main'; }

ob_start();

require "resources/templates/help/{$with}.php";

echo ob_get_clean();