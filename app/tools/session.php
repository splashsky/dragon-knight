<?php

/**
 * A session handler.
 * Helps create, maintain, update, and delete sessions.
 */

class Session
{
    private string $lifetime       = '';
    private string $cookieName     = '';
    private bool   $valid          = false;
    private string $token          = '';

    public function __construct()
    {
        $this->lifetime = env('session_lifetime');
        $this->cookieName = env('cookie_name');
    }

    public function verify(): bool
    {
        // cookie just doesn't exist
        if (!$this->cookieExists()) { return false; }

        // get token if cookie exists
        $this->token = $this->getToken();

        // if can't find session in db from token
        if (!$this->sessionExists()) {
            $this->clear();
            return false;
        }

        // if session was found in db, see if we can renew session
        // session will be "invalid" in db if no refresh within the lifetime
        if (!$this->renewSession()) {
            $this->clear();
            return false;
        }

        $this->setCookie();

        return $this->valid = true;
    }

    public function cookieExists(): bool
    {
        return isset($_COOKIE[$this->cookieName]);
    }

    public function valid(): bool
    {
        return $this->valid;
    }

    public function getToken(): string
    {
        return $_COOKIE[$this->cookieName];
    }

    public function sessionExists(string $token = '')
    {
        $token = empty($token) ? $this->token : $token;
        return db()->qe('select id from sessions where token = ?;', [$token]) === false ? false : true;
    }

    public function setCookie(): bool
    {
        $token = empty($this->token) ? makeToken() : $this->token;
        $this->token = $token;
        return setcookie($this->cookieName, $token, [
            'expires'  => strtotime($this->lifetime),
            'path'     => '/',
            'samesite' => 'lax'
        ]);
    }

    public function deleteCookie(): bool
    {
        return setcookie($this->cookieName, '', time() - 3600);
    }

    public function createSession(int $userID)
    {
        $this->setCookie();
        db()->qe('insert into sessions set user_id = ?, token = ?, created_at = now(), refreshed_at = now();', [$userID, $this->token]);
        return $this->sessionExists();
    }

    public function deleteSession(string $token = ''): bool
    {
        $token = empty($token) ? $this->token : $token;
        db()->qe('delete from sessions where token = ?;', [$this->token]);
        return !$this->sessionExists() ? true : false;
    }

    public function renewSession(string $token = ''): bool
    {
        $token = empty($token) ? $this->token : $token;
        $session = db()->qe('select * from sessions where token = ?;', [$token])->fetch();

        $updated = new DateTime($session['refreshed_at']);
        $future = new DateTime($session['refreshed_at']);
        $future->modify($this->lifetime);

        if ($updated < $future) {
            db()->qe('update sessions set refreshed_at = now() where token = ?;', [$token]);
            return true;
        }

        $this->deleteSession($token);
        return false;
    }

    private function clear()
    {
        $this->valid = false;
        $this->token = '';
        $this->deleteCookie();
    }
}