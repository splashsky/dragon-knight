<?php

function loadEnv(string $path): void
{
    if (!file_exists($path) || !is_readable($path)) {
        throw new \InvalidArgumentException(sprintf('%s does not exist', $path));
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    foreach ($lines as $line) {
        // Skip past commented lines
        if (strpos(trim($line), '#') === 0) { continue; }

        // Get the key/value pair of each line
        list($name, $value) = explode('=', $line, 2);
        $name = trim($name);
        $value = trim($value, "\"' \t\n\r\0\x0B");

        // Persist the key/value pair to the environment if it doesn't already exist
        if (!array_key_exists($name, $_SERVER) && !array_key_exists($name, $_ENV)) {
            putenv(sprintf('%s=%s', $name, $value));
            $_ENV[$name] = $value;
            $_SERVER[$name] = $value;
        }
    }
}

/**
 * Neat function to return a properly typed environment variable.
 */
function env(string $key): mixed
{
    $value = getenv($key);

    $value = strtolower($value) == 'true' ? true : $value;
    $value = strtolower($value) == 'false' ? false : $value;
    $value = is_numeric($value) ? (int) $value : $value;

    return $value;
}