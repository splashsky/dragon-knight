<?php

class Autoload
{
    public static function register(string $appDirectory)
    {
        spl_autoload_register(function ($class) use ($appDirectory) {
            // If the class exists in controllers, load it
            if (file_exists($appDirectory . 'controllers/' . $class . '.php')) {
                require $appDirectory . 'controllers/' . $class . '.php';
            }
        
            // If the class is in tools, load it
            if (file_exists($appDirectory . 'tools/' . $class . '.php')) {
                require $appDirectory . 'tools/' . $class . '.php';
            }
        });
    }
}