<?php

require 'app/Game.php';

$db = new Database(config('game.db'));
$user = new User($db);
$user = $user->getById(2);
$user->gold = 10000;
$user->save();

$validate = new Validator([
    'username' => '1',
    'password' => '',
    'email' => 'sky@sky'
]);

echo $validate->validate([
    'username' => 'required|min:2|alpha',
    'password' => 'required|min:8',
    'email' => 'required|email'
]);

dd($validate->errors('username'));