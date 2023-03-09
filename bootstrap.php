<?php

require './tools/library.php';
require './tools/env.php';
require './tools/database.php';
require './tools/session.php';

Env::load('./.env');
$DB = new Database();