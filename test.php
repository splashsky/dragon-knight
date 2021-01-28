<?php

require 'app/Game.php';
require 'app/Models/Fight.php';

$db = new Database(config('game.db'));
$fight = new Fight($db, 1);
dd($fight);