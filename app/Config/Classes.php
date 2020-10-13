<?php

return [

    'warrior' => [
        'title' => 'Warrior',
        'exp' => function($x) {
            return $x * 10;
        },
    ],

    'mage' => [
        'title' => 'Mage',
        'exp' => function($x) {
            return $x * 100;
        },
    ],

    'paladin' => [
        'title' => 'Paladin',
        'exp' => function($x) {
            return $x * 1000;
        },
    ]

];