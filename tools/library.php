<?php

////////////////////////////////////////////////////////////////////////////////
//
// A hyper generic but useful repo of hand-built functions used throughout
// the game.
//
////////////////////////////////////////////////////////////////////////////////

/**
 * Use random_bytes with a minimum length of 4 to generate a crypto-secure
 * token string.
 */
function makeToken(int $length = 32): string
{
    $length = $length < 4 ? 4 : $length;
    return bin2hex(random_bytes($length));
}

/**
 * Wrapper for header() and the Location attribute.
 */
function redirect(string $location = '/')
{
    header("Location: $location");
}