<?php

class User
{
    private Database $db;
    private array $hidden = ['id', 'password'];
    public int $id = 0;
    public array $props;

    public function __construct(Database $db)
    {
        $this->db = $db;
    }

    /**
     * Create a user with data passed to the $data parameter. The keys in $data must be column names
     * for the user table, or it will fail.
     */
    public function create(array $data): User
    {
        $fields = $this->db->fieldsForQuery(array_keys($data));

        $new = $this->db->prepare("INSERT INTO {{ table }} SET {$fields};", 'users');
        $new->execute(array_values($data));

        $id = $this->db->lastInsertId();
        $this->id = $id;

        $this->db->quick('INSERT INTO {{ table }} SET user_id=?;', 'inventories', [$id]);

        return $this->getById($id);
    }

    /**
     * Attempts to locate the user by the passed $id. If the user does not exist and DEBUG is true,
     * this function will throw an exception. Otherwise it will return the user instance with no data.
     */
    public function getById(int $id): User
    {
        $user = $this->db->prepare('SELECT * FROM {{ table }} WHERE id=?', 'users');
        $user->execute([$id]);

        if ($user = $user->fetch()) {
            $this->id = $id;

            foreach ($user as $k => $v) {
                if (! in_array($k, $this->hidden)) {
                    $this->{$k} = $v;
                    $this->props[] = $k;
                }
            }
        } elseif (DEBUG) {
            throw new Exception('User not found by id '.$id);
        }

        return $this;
    }

    /**
     * Takes all the properties on the current User instance and persists them to the database. Returns
     * the result of the query, i.e. true/PDO object on success, false on failure.
     */
    public function save(): bool
    {
        $fields = $this->db->fieldsForQuery($this->props);

        $data = [];
        foreach ($this->props as $k) { $data[] = $this->{$k}; }
        $data[] = $this->id;

        $save = $this->db->prepare("UPDATE {{ table }} SET {$fields} WHERE id=?", 'users');
        return $save->execute($data);
    }

    /**
     * The more conservative version of the save() method; takes an array of data (with keys that match actual columns) and an
     * optional $save (defaults to true) and will update those values on the User instance. If $save is true, the updated data
     * will be persisted to the database.
     */
    public function update(array $data, bool $save = true): bool
    {
        foreach ($data as $k => $v) { $this->{$k} = $v; }

        if ($save) {
            $fields = $this->db->fieldsForQuery(array_keys($data));

            $save = $this->db->prepare("UPDATE {{ table }} SET {$fields} WHERE id=?", 'users');
            return $save->execute($data);
        }

        return true;
    }
}

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