<?php

return [

    'unverified' => [
        'title' => 'Unverified',
        'can' => ['play']
    ],

    'member' => [
        'title' => 'Member',
        'can' => ['play', 'chat']
    ],

    'admin' => [
        'title' => 'Game Master',
        'can' => ['play', 'chat', 'admin']
    ],

    'banned' => [
        'title' => 'Banned',
        'can' => []
    ]

];