<?php

function getItemById(int $id, $link = null, string $fields = '*')
{
    $link = openLinkIfNull($link);

    $item = prepare("select {$fields} from {{ table }} where id=?", 'items', $link);
    $item = execute($item, [$id])->fetch();

    return $item;
}

function getItemNameById(int $id, $link = null)
{
    $link = openLinkIfNull($link);
    $item = getItemById($id, $link, 'name');
    return $item ? $item['name'] : 'None';
}