<?php

class Fight
{
    private Database $db;
    private array $hidden = [];
    public int $id = 0;
    public array $props = [];

    public function __construct(Database $db, int $userId = 0)
    {
        $this->db = $db;

        if ($userId !== 0) {
            if ($this->fightExistsFor($userId)) {
                return $this->getByUserId($userId);
            }
        }
    }

    public function create(array $data): Fight
    {
        $fields = $this->db->fieldsForQuery(array_keys($data));

        $new = $this->db->prepare("INSERT INTO {{ table }} SET {$fields};", 'fights');
        $new->execute(array_values($data));

        $this->id = $this->db->lastInsertId();

        return $this->getById($this->id);
    }

    public function getByUserId(int $userId): Fight
    {
        $fight = $this->db->prepare('SELECT * FROM {{ table }} WHERE user_id=?', 'fights');
        $fight->execute([$userId]);

        if ($fight = $fight->fetch()) {
            $this->populate($fight);
        } elseif (DEBUG) {
            throw new Exception('Fight not found by user_id '.$id);
        }

        return $this;
    }

    public function getById(int $id): Fight
    {
        $fight = $this->db->prepare('SELECT * FROM {{ table }} WHERE id=?', 'fights');
        $fight->execute([$id]);

        if ($fight = $fight->fetch()) {
            $this->populate($fight);
        } elseif (DEBUG) {
            throw new Exception('Fight not found by id '.$id);
        }

        return $this;
    }

    private function populate(array $data): Fight
    {
        $this->id = $data['id'];

        foreach ($data as $k => $v) {
            if (! in_array($k, $this->hidden)) {
                $this->{$k} = $v;
                $this->props[] = $k;
            }
        }

        return $this;
    }

    public function fightExistsFor(int $userId): bool
    {
        $fight = $this->db->quick('SELECT id FROM {{ table }} WHERE user_id=?', 'fights', [$userId]);
        return $fight->fetch() ? true : false;
    }

    public function isMonsterAsleep(): bool
    {
        return $this->monster_sleep == 0 ? false : true;
    }

    public function doesMonsterWakeUp(): bool
    {
        $chance = rand(1, 15);

        if ($chance > $this->monster_sleep) {
            $this->monster_sleep = 0;
            return true;
        }

        $this->monster_sleep = $this->monster_sleep <= 0 ?: $this->monster_sleep - 1;
        return false;
    }
}