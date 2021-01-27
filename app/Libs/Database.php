<?php

class Database
{
    public PDO $conn;
    public string $prefix = '';
    public int $queries = 0;

    public function __construct(array $config, array $opts = [])
    {
        $this->prefix = $config['prefix'];
        $dsn = "mysql:host={$config['server']};dbname={$config['database']};charset=utf8mb4";

        $opts = ! empty($opts) ? $opts : [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ];

        try {
            $this->conn = new PDO($dsn, $config['user'], $config['password'], $opts);
            return $this;
        } catch (PDOException $e) {
            if (DEBUG) { throw new Exception($e->getMessage(), $e->getCode()); }
        }
    }

    public function parse(string $query, $tokens = []): string
    {
        // If only a string was passed to $tokens, we'll assume it was the table
        // name for the query.
        $tokens = is_string($tokens) ? ['table' => $tokens] : $tokens;

        return parse($query, $tokens);
    }

    public function prepare(string $query, $tokens): PDOStatement
    {
        $query = $this->parse($query, $tokens);
        return $this->conn->prepare($query);
    }

    public function query(string $query, $tokens = ''): PDOStatement
    {
        $this->incrementQueries();
        $query = $this->parse($query, $tokens);
        return $this->conn->query($query);
    }

    public function quick(string $query, $tokens, array $params = []): PDOStatement
    {
        $this->incrementQueries();
        $query = $this->parse($query, $tokens);
        $query = $this->prepare($query, $tokens);
        $query->execute($params);
        return $query;
    }

    public function incrementQueries(int $amount = 1): void
    {
        $this->queries += $amount;
    }

    public function queryCount(): int
    {
        return $this->queries;
    }

    public function lastInsertId(): int
    {
        return (int) $this->conn->lastInsertId();
    }

    public function fieldsForQuery(array $props = []): string
    {
        $fields = '';
        foreach ($props as $k) { $fields .= "{$k}=?, "; }
        return rtrim($fields, ', ');
    }
}

function openLink(array $opts = [])
{
    $config = config('game.db');

    // We're initializing the DSN, or a string containing connection info.
    // Our host is our db.server config, the database we're accessing is named
    // according to the db.database config. We're also telling PDO we want to
    // use the modern utf8mb4 charset, which includes support for emoji.
    $dsn = "mysql:host={$config['server']};dbname={$config['database']};charset=utf8mb4";

    // We're defining some configs specifically for our PDO connection,
    // such as making all PDO errors come up as Exceptions, and setting
    // our default fetch mode (for SELECT statements) to associative arrays
    // (e.g. $key => $value)
    $opts = !empty($opts) ? $opts : [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ];

    // We'll now attempt to connect to the database. If we're successful,
    // we'll return our connection instance. If we failed, we'll throw a PDO exception 
    // with the error message and code, if DEBUG is enabled.
    try {
        return new PDO($dsn, $config['user'], $config['password'], $opts);
    } catch (PDOException $e) {
        if (DEBUG) { throw new PDOException($e->getMessage(), $e->getCode()); }
    }
}

function openLinkIfNull($link = null)
{
    return is_null($link) ? openLink() : $link;
}

function prefix(string $table)
{
    $prefix = config('db.prefix');
    if (empty($table)) { return $table; }
    return empty($prefix) ? $table : $prefix.'_'.$table;
}

function parseQuery(string $query, string $table = '')
{
    return preg_replace('/{{\s*table\s*}}/', prefix($table), $query);
}

function query(string $query, string $table = '', $link = null)
{
    incrementQueries();

    $link = openLinkIfNull($link);
    $query = parseQuery($query, $table);
    return $link->query($query);
}

function prepare(string $query, string $table = '', $link = null)
{
    $link = openLinkIfNull($link);
    $query = parseQuery($query, $table);
    return $link->prepare($query);
}

function execute($prepared, array $params = [])
{
    incrementQueries();
    
    $prepared->execute($params);
    return $prepared;
}

function quick(string $query, string $table = '', array $params = [], $link = null)
{
    incrementQueries();

    $link = openLinkIfNull($link);
    $query = prepare($query, $table, $link);
    return execute($query, $params);
}