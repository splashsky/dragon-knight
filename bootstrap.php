<?php

session_start();

// Import all the things
require 'app/tools/library.php';
require 'app/tools/env.php';
require 'app/tools/autoload.php';

// Register our primitive autoloader
Autoload::register(__DIR__.'/app/');

// Load our env vars
loadEnv(__DIR__.'/.env');

// Instantiate the most important classes
$view = new View(__DIR__ . '/views/', __DIR__ . '/cache/');
$router = new Router();
$DB = new Database();
$session = new Session();

// Check for any flash messages that need to be removed
checkFlashes();