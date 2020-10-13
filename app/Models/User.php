<?php

function createUser(array $data, $link = null)
{
    $link = openLinkIfNull($link);

    $fields = '';
    foreach (array_keys($data) as $k) { $fields .= "{$k}=?, "; }
    $fields = rtrim($fields, ', ');

    $new = prepare("INSERT INTO {{ table }} SET {$fields};", 'users', $link);
    execute($new, array_values($data));
    
    $id = $link->lastInsertId();

    quick('INSERT INTO {{ table }} SET user_id=?;', 'inventories', [$id], $link);
}

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

function isBanned(string $auth)
{
    return $auth == 'banned';
}

function dieIfBanned(string $auth)
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

function redirectIfNotAuthorized($role, $level)
{
    if ($role != $level) {
        redirect('index.php');
    }
}

function checkAuthLevel($user, $level)
{
    return (int) $user >= (int) $level;
}

function getUserInventory(int $id, $link = null)
{
    $link = openLinkIfNull($link);

    $equipment = prepare('select * from {{ table }} where user_id=?', 'inventories', $link);
    return execute($equipment, [$id])->fetch();
}

function userHasItemInSlot(string $type, array $inventory)
{
    return $inventory["{$type}_id"] != 0;
}

function userHasEquipped(int $itemId, array $inventory)
{
    return in_array($itemId, $inventory);
}

function getItemIdForSlot(string $type, array $inventory)
{
    return (int) $inventory["{$type}_id"];
}

function getItemNameForSlot(string $type, array $inventory)
{
    return $inventory["{$type}_name"];
}

function equipItemOnUser(array $item, array $user, array $inventory, $link = null)
{
    $link = openLinkIfNull($link);

    if (userHasItemInSlot($item['type'], $inventory)) {
        $equipped = getItemIdForSlot($item['type'], $inventory);
        userUnequipItem($user['id'], $equipped, $link);
    }

    $equip = prepare("UPDATE {{ table }} SET {$item['type']}_id=?, {$item['type']}_name=? WHERE user_id=?", 'inventories', $link);
    execute($equip, [$item['id'], $item['name'], $user['id']], $link);

    if ($item['type'] == 'weapon') {
        $user['attack'] += $item['attribute'];
    } else {
        $user['defense'] += $item['attribute'];
    }

    // TODO handle adding specials on equip

    return userSave($user['id'], $user);
}

function userUnequipItem(int $userId, int $itemId, $link = null)
{
    $link = openLinkIfNull($link);

    $item = getItemById($itemId, $link);
    $user = getUserFromId($userId, $link);

    $unequip = prepare("UPDATE {{ table }} SET {$item['type']}_id='0', {$item['type']}_name='' WHERE user_id=?", 'inventories', $link);
    execute($unequip, [$userId], $link);

    if ($item['type'] == 'weapon') {
        $user['attack'] -= $item['attribute'];
    } else {
        $user['defense'] -= $item['attribute'];
    }

    // TODO handle removing specials on unequip

    return userSave($userId, $user, $link);
}

function userSave(int $user, array $data, $link = null)
{
    $link = openLinkIfNull($link);

    $restricted = ['id', 'username', 'email', 'password'];

    $fields = '';
    $props = [];
    foreach ($data as $k => $d) {
        if (! in_array($k, $restricted)) {
            $fields .= "{$k}=?, ";
            $props[] = $d;
        }
    }
    $fields = rtrim($fields, ', ');
    $props[] = $user;

    $update = prepare("UPDATE {{ table }} SET {$fields} WHERE id=?", 'users', $link);
    return execute($update, $props);
}