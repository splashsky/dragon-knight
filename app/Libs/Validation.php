<?php

class Validator
{
    public array $_data;
    public array $_bag = [];
    public string $_key = '';
    public string $_field = '';
    
    private Database $db;

    public function __construct(array $data = [])
    {
        $data = $this->trimData($data);
        $this->_data = $data;

        foreach ($data as $k => $v) {
            $this->{$k} = $v;
        }
    }

    public function validate(array $rules = []): bool
    {
        $valid = true;

        foreach ($rules as $key => $value) {
            $rules = explode('|', $value);

            foreach ($rules as $rule) {
                if (isset($this->_data[$key])) {
                    $this->_key = $key;
                    $this->_field = $this->parseFieldName($key);
                    $result = $this->processRule($rule, $this->_data[$key]);

                    if (! $result) { $valid = false; }
                }
            }
        }

        return $valid;
    }

    public function processRule(string $rule, $data): bool
    {
        if ($rule == 'required') { return $this->required($data); }

        if (strpos($rule, 'min') !== false) { return $this->minimum($data, $rule); }

        if (strpos($rule, 'max') !== false) { return $this->maximum($data, $rule); }

        if (strpos($rule, 'range') !== false) { return $this->range($data, $rule); } 

        if ($rule == 'alphanum') { return $this->alphanum($data); }

        if ($rule == 'alpha') { return $this->alpha($data); }

        if ($rule == 'numeric') { return $this->numeric($data); }

        if ($rule == 'email') { return $this->is_email($data); }

        if (strpos($rule, 'unique') !== false) { return $this->unique($data, $rule); }

        if ($rule == 'class') { return $this->is_class($data); }

        if ($rule == 'diff') { return $this->is_diff($data); }
    }

    public function required($data): bool
    {
        $valid = ! empty($data);

        if (! $valid) { $this->writeError("{$this->_field} is required"); }

        return $valid;
    }

    public function minimum($data, $rule): bool
    {
        $min = explode(':', $rule);
        $valid = strlen($data) >= $min[1];

        if (! $valid) { $this->writeError("{$this->_field} must be at least {$min[1]} characters long"); }

        return $valid;
    }

    public function maximum($data, $rule): bool
    {
        $max = explode(':', $rule);
        $valid = strlen($data) <= $max[1];

        if (! $valid) { $this->writeError("{$this->_field} must be no more than {$max[1]} characters long"); }

        return $valid;
    }

    public function alphanum($data): bool
    {
        $valid = (bool) preg_match('/^[a-zA-Z0-9][a-zA-Z0-9-_ ]+[a-zA-Z0-9]$/', $data);

        if (! $valid) { $this->writeError("{$this->_field} must be alphanumeric (letters, numbers, dashes, underscores and spaces)"); }

        return $valid;
    }

    public function alpha($data): bool
    {
        $valid = (bool) preg_match('/^[a-zA-Z][a-zA-Z-_ ]+[a-zA-Z]$/', $data);

        if (! $valid) { $this->writeError("{$this->_field} must be alphabetic (letters, dashes, underscores and spaces)"); }

        return $valid;
    }

    public function numeric($data): bool
    {
        $valid = (bool) preg_match('/^[0-9]+$/', $data);

        if (! $valid) { $this->writeError("{$this->_field} must be numeric"); }

        return $valid;
    }

    public function is_email($data): bool
    {
        $valid = filter_var($data, FILTER_VALIDATE_EMAIL);

        if (! $valid) { $this->writeError("You must provide a valid email address"); }

        return $valid;
    }

    public function unique($data, $rule): bool
    {
        $rule = explode(':', $rule);

        $query = $this->db->prepare("SELECT id FROM {{ table }} WHERE {$this->_key}=?", $rule[1]);
        $query->execute([$data]);
        $result = $query->fetch();
        
        $valid = empty($result) || $result == false;

        if (! $valid) { $this->writeError("{$this->_field} must be unique"); }

        return $valid;
    }

    public function parseFieldName(string $field): string
    {
        $new = [];
        $field = str_replace('_', ' ', $field);
        $exploded = explode(' ', $field);

        foreach ($exploded as $word) {
            $new[] = ucfirst($word);
        }

        return implode(' ', $new);
    }

    public function is_class($data): bool
    {
        $valid = array_key_exists($data, config('classes'));

        if (! $valid) { $this->writeError('Invalid class; please select from the provided list.'); }

        return $valid;
    }

    public function is_diff($data): bool
    {
        $valid = array_key_exists($data, config('game.difficulties'));

        if (! $valid) { $this->writeError('Invalid difficulty; please select from the provided list.'); }

        return $valid;
    }

    public function writeError(string $error)
    {
        $this->_bag[$this->_key][] = $error;
    }

    public function range($data, $rule): bool
    {
        $rule = explode(':', $rule);
        $range = explode('-', $rule[1]);
        $valid = (int) $data >= $range[0] && $data <= $range[1];

        if (! $valid) { $this->writeError("must be between {$range[0]} and {$range[1]}"); }

        return $valid;
    }

    public function trimData(array $data = []): array
    {
        $trimmed = [];
        foreach ($data as $k => $v) { $trimmed[$k] = trim($v); }
        return $trimmed;
    }

    public function errors(string $field = ''): array
    {
        return empty($field) ? $this->_bag : $this->_bag[$field];
    }

    public function data(string $field)
    {
        return $this->_data[$field];
    }

    public function setDb(Database $db)
    {
        $this->db = $db;
    }
}

function required(string $field)
{
    return !empty($field) ? true : false;
}

function matches(string $one, string $two)
{
    return $one == $two;
}

function is_email(string $input)
{
    return filter_var($input, FILTER_VALIDATE_EMAIL);
}