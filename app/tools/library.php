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
    return bin2hex(random_bytes($length < 4 ? 4 : $length));
}

/**
 * Wrapper for header() and the Location attribute.
 */
function redirect(string $location = '/')
{
    header("Location: $location");
}

/**
 * Access the global View instance $view and return a render.
 */
function view(string $path, array $data = []): string
{
    global $view;
    return $view->view($path, $data);
}

/**
 * Access the global Database instance $DB.
 */
function db(): Database
{
    global $DB;
    return $DB;
}

/**
 * Access the global Session instance $session.
 */
function session(): Session
{
    global $session;
    return $session;
}

/**
 * Flash a message to the current session that will persist for a single request. If $value is empty, return the value of the flash message if it exists.
 */
function flash(string $key, string $value = ''): string
{
    if (empty($value)) {
        if (isset($_SESSION['flash'][$key])) {
            return $_SESSION['flash'][$key][0];
        } else {
            return '';
        }
    }

    // persist the key => value to the session, using 0 as the lifetime
    $_SESSION['flash'][$key] = [$value, 0];
    return $value;
}

/**
 * Loop through the flash messages and remove any that have expired.
 */
function checkFlashes(): void
{
    if (isset($_SESSION['flash'])) {
        foreach ($_SESSION['flash'] as $key => $value) {
            if ($_SESSION['flash'][$key][1] >= 1) {
                unset($_SESSION['flash'][$key]);
                continue;
            }
            
            $_SESSION['flash'][$key][1] += 1;
        }
    }
}