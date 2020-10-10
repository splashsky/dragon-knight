<?php

/**
 * Get the user's data from the cookie.
 */
function getUserFromCookie($link = null)
{
    $link = openLinkIfNull($link);

    /**
     * Cookie Format
     * {user id} {username} {password from login} {remember me}
     */
    $cookie = explode(' ', $_COOKIE['dkgame']);

    $user = prepare('select * from {{ table }} where id=?', 'users', $link);
    $user = execute($user, [$cookie[0]])->fetch();
    return $user;
}

/**
 * Get the user with the given id
 */
function getUserFromId(int $id, $link = null, string $fields = '*')
{
    $link = openLinkIfNull($link);

    $user = prepare("select {$fields} from {{ table }} where id=?", 'users', $link);
    $user = execute($user, [$id])->fetch();
    return $user;
}

function getUserIfLoggedInByCookie($link = null)
{
    $link = openLinkIfNull($link);

    if (! checkcookies()) { redirect('users.php?do=login'); }

    return getUserFromCookie($link);
}

function isBanned(int $auth)
{
    return $auth <= config('auth.banned');
}

function dieIfBanned(int $auth)
{
    if (isBanned($auth)) {
        die('You have been banned. Try again later.');
    }
}

function redirectIfNotVerified($status, $control)
{
    if ((bool) $control && ! (bool) $status) {
        redirect('users.php?do=verify');
    }
}

function redirectIfNotAuthorized($user, $level)
{
    if (! checkAuthLevel($user, $level)) {
        redirect('index.php');
    }
}

function checkAuthLevel($user, $level)
{
    return (int) $user >= (int) $level;
}