<?php

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