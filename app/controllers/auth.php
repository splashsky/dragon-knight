<?php

class Auth
{
    public static function showLogin()
    {
        return view('auth.login');
    }

    public static function showRegister()
    {
        return view('auth.register');
    }

    public static function doLogin()
    {
        $email = $_POST['email'];
        $password = $_POST['password'];

        if (empty($email) || empty($password)) {
            die('no data');
        }
    }

    public static function doRegister()
    {
        
    }
}