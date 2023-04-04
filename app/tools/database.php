<?php

class Database
{
    private PDO $conn; // Persistent database connection
    private int $queries = 0; // Number of queries executed this instance
    private PDOStatement|false $prepared; // Currently prepared statement.

    /**
     * Constructor - all params are optional, when no value given it will pull from env.
     */
    public function __construct(array $opts = [], string $database = '', string $user = '', string $pass = '', string $server = '', string|int $port = '')
    {
        $database = empty($database) ? getenv('db_name')   : $database;
        $user     = empty($user)     ? getenv('db_user')   : $user;
        $pass     = empty($pass)     ? getenv('db_pass')   : $pass;
        $server   = empty($server)   ? getenv('db_server') : $server;
        $port     = empty($port)     ? getenv('db_port')   : $port;

        $dsn = "mysql:dbname=$database;host=$server;port=$port";

        $opts = !empty($opts) ? $opts : [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ];

        $this->conn = new PDO($dsn, $user, $pass, $opts);
    }

    /**
     * A wrapper for PDO::exec
     */
    public function exec(string $statement): int|false
    {
        $this->queries++;
        return $this->conn->exec($statement);
    }

    /**
     * A wrapper for PDO::query
     */
    public function query(string $query, int $fetchMode = null): PDOStatement|false
    {
        $this->queries++;
        return $this->conn->query($query, $fetchMode);
    }

    /**
     * A wrapper for PDO::prepare
     */
    public function prepare(string $query, array $options = []): PDOStatement|false
    {
        $this->prepared = $this->conn->prepare($query, $options);
        return $this->prepared;
    }

    /**
     * Special wrapper for PDOStatement::execute
     * Will default to using $this->prepared, but can provide a separate PDOStatement to execute.
     * Will return the PDOStatement object rather than the usual bool. Returns false on fail.
     */
    public function execute(array $params = [], PDOStatement $query = null): PDOStatement|false
    {
        $statement = is_null($query) ? $this->prepared : $query;
        $this->queries++;
        $result = $statement->execute($params);
        return $result === false ? false : $statement;
    }

    /**
     * QuickExecute; prepare and execute a statement all in one call. Just shorthand.
     */
    public function qe(string $query, array $params = [], array $options = []): PDOStatement|false
    {
        $this->prepare($query, $options);
        return $this->execute($params);
    }

    /**
     * Use COUNT() to see if the requested entry exists in the table.
     */
    public function exists(string $table, string $column, string $value): bool
    {
        $query = "SELECT COUNT(*) FROM $table WHERE $column = ?";
        $statement = $this->qe($query, [$value]);
        return $statement->fetchColumn() > 0;
    }
}