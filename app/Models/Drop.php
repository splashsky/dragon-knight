<?php

function getDropById(int $id, $link = null, string $fields = '*')
{
    $link = openLinkIfNull($link);

    $drop = prepare("select {$fields} from {{ table }} where id=?", 'drops', $link);
    $drop = execute($drop, [$id])->fetch();

    return $drop;
}

function getDropNameById(int $id, $link = null)
{
    $link = openLinkIfNull($link);
    $drop = getDropById($id, $link, 'name');
    return $drop ? $drop['name'] : 'None';
}