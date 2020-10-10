# Development Changelog
All the notable changes done for Dragon Knight's development will be recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Added a `.gitignore` to hide development-only files
- Created a fonts/ and css/ directory
- Refactored the primary and minimal templates to use the CSS file for the game

### Changed
- Moved `templates` directory to `resources`
- Moved `images` directory to `resources` and renamed to `img`
- Huge visual overhaul, now cleaner and more neutral than before

## v1.3.0 - 2020/10/03
### Added
- A new `app` directory to house libraries, vendor code, and game config
- Created a new Database library that utilizes PDO in a simple format
- A new `getControl` function that accepts a PDO link as a parameter, retrieves the game's control row
- Added two ways of retrieving user data; `getUserFromCookie` and `getUserFromId`
- Added a super-helpful debug method that formats var_dump and dies, called `dd()`
- Added two helper functions to increment and get the number of queries executed; `incrementQuerieser` and `getQueries`
- The PDO database methods now increments the global `$querieser` via `incrementQuerieser()`
- Created a new `resources` directory to contain css, images and sql query files

### Changed
- Scripts that contained only functions have been moved into `app/Libs` and are included on an as-needed basis to cut down on root directory bloat
- Took all help pages and turned them into templates in `templates/help`
- Condensed `help.php` down into one script that utilizes the new help page templates
- Release versions of the game will no longer have `DEBUG` set to true by default
- Moved functions in `login.php` to `users.php`, changed all game links accordingly
- Renamed `Lib.php` to `Helpers.php`, updated previous changelog entries to reflect this
- `makesafe()` has been refactored to `safe()`, but performs the same function
- The `$numqueries` global variable has been refactored to `$queries`
- All install pages are now contained in templates in `templates/install`
- The installation `create` and `populate` queries have been moved into the new sql directory, `resoures/sql/install`
- Errors in the admin account creation part of the installation process will now display the admin account field again, with the errors listed
- Messages, titles and usernames in the forum are now properly escaped before being output
- The admin panel's pages and forms are now in templates files in `templates/admin`
- All functionality of the game has been fully converted to the new PDO library

### Removed
- Removed the `mysql_` shim, and all functions related to/using it
- Removed `login.php` after moving all functions to `users.php`
- Removed all old XML validation content. Pages are now only made with HTML5 compliant tags.
- `charname` has been completely removed from the game - the installer has been updated to not add that column in the database. All relevant bits of code have been updated as well.
- The "fifth" page of the installation process, originally used to send a "call home" for installs, has been removed. A similar feature will be added again later.

## v1.2.0 - 2020/09/30
### Changed
- The register function and installer now use a [cryptographically secure method of hashing and storing passwords](https://www.php.net/manual/en/function.password-hash).
- Logging in now [checks against the password hash correctly](https://www.php.net/manual/en/function.password-verify.php).
- The registration function now uses an array for errors rather than a counter and string.
- The registration form now uses modern HTML5 input features, and has better code indentation.
- The login function now displays an error at the top of the form instead of die'ing at runtime.
- The installer will now drop existing tables when it creates new ones.
- Cookies now store the password used at login, and checks it against the hashed version in the database.
- The installer will now set `verifyemail` to `false` by default, changed from `true`
- The `checkcookies` function was moved to `Helpers.php`

### Deprecated
- `charname` will soon be removed, and will be replaced by `username` in all instances.

### Removed
- The two "patch" scripts have been removed due to having no use.
- The registration form no longer has a `charname` field.
- The installer no longer uses a `charname` field, and instead sets `charname` to `username`
- The `cookies.php` file has been deleted, and the `checkcookies` function moved to `Helpers.php`

## v1.1.11 - 2020/08/27
### Added
- A `mysql_` shim for PHP 7 was added in order to make the game function.

### Changed
- Updated the SQL queries in the `install.php` script so that they would run on modern MySQL servers.

## Before v1.1.11
See the [commit history for the original repo](https://github.com/renderse7en/dragon-knight/commits/master) for past changes.