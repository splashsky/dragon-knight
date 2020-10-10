<?php

return [

    /**
     * ------------------------------------------------------------
     * Versioning Config
     * - version: the version number you want to use throughout the game
     * - build: an optional build name, you can leave it empty
     */
    'general' => [
        'version' => '1.3.0',
        'build' => '',
    ],

    /**
     * ------------------------------------------------------------
     * Database Config
     * - server: the server address that hosts your database (typically localhost)
     * - database: the name of the database you're using
     * - user: the username for your database connection
     * - password: the password for your database connection
     * - prefix: an optional prefix for your tables (e.g. dk_users), you can leave it empty 
     */
    'db' => [
        'server' => 'mariadb',
        'database' => 'testdk',
        'user' => 'root',
        'password' => 'secret',
        'prefix' => ''
    ],

    'difficulties' => [
        'easy' => [
            'title' => 'Easy',
            'mod' => 0.8
        ],

        'normal' => [
            'title' => 'Normal',
            'mod' => 1
        ],

        'hard' => [
            'title' => 'Hard',
            'mod' => 1.45
        ],
    ],

];