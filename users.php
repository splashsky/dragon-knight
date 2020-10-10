<?php // users.php :: Handles user account functions.

require 'app/Libs/Helpers.php';

$link = openLink();
$control = getControl($link);

$do = isset($_GET['do']) ? $_GET['do'] : 'login';

if ($do === 'register') { register(); }
elseif ($do === 'login') { login(); }
elseif ($do === 'verify') { verify(); }
elseif ($do === 'lostpassword') { lostpassword(); }
elseif ($do === 'changepassword') { changepassword(); }
elseif ($do === 'logout') { logout(); }
else { login(); }

/**
 * Either displays the login page, or handles the login process.
 */
function login()
{
    $error = false;
    
    if (isset($_POST['submit'])) {
        $username = trim($_POST['username']);
        $password = trim($_POST['password']);

        $user = prepare('select id, password from {{ table }} where username=?', 'users');
        $user = execute($user, [$username])->fetch();

        if (! $user) { $error = true; }

        if (! password_verify($password, $user['password'])) { $error = true; }

        if (! $error) {
            if (isset($_POST["rememberme"])) { $expiretime = time() + 31536000; $rememberme = 1; } else { $expiretime = 0; $rememberme = 0; }
            $cookie = "{$user['id']} {$username} {$password} {$rememberme}";
            setcookie('dkgame', $cookie, $expiretime, '/', '', 0);
            redirect('index.php');
        }
    }
    
    $page = gettemplate("login");
    $page = parsetemplate($page, ['error' => $error ? 'Invalid username or password. Try again.' : '']);
    display($page, 'Log in', false, false, false, false);
}

function register()
{   
    global $control, $link;
    
    if (isset($_POST['submit'])) {
        $username = trim($_POST['username']);
        $email = trim($_POST['email']);
        $emailConfirm = trim($_POST['email_confirm']);
        $password = trim($_POST['password']);
        $passwordConfirm = trim($_POST['password_confirm']);
        
        $errors = [];
        
        // Process the username
        if (empty($username)) { $errors[] = 'A username is required.'; }

        // According to this pattern, usernames must be alphanumeric. Underscores and dashes CAN be
        // used, but the username must start and end with an alphanumeric character.
        $regex = '/^[a-zA-Z0-9][a-zA-Z0-9_-]+[a-zA-Z0-9]$/';
        if (! preg_match($regex, $username)) { $errors[] = 'Username must be alphanumeric.'; }

        $usernameExists = prepare('select id from {{ table }} where username=?', 'users', $link);
        $usernameExists = execute($usernameExists, [$username])->fetch() ? true : false;
        if ($usernameExists) { $errors[] = "{$username} is already taken. Try another one."; }
    
        // Process the email address
        if (empty($email) || empty($emailConfirm)) { $errors[] = 'Email is required.'; }
        if ($email !== $emailConfirm) { $errors[] = 'Email addresses must match.'; }
        if (! filter_var($email, FILTER_VALIDATE_EMAIL)) { $errors[] = 'Must provide valid email address.'; }

        $emailExists = prepare('select id from {{ table }} where email=?', 'users', $link);
        $emailExists = execute($emailExists, [$email])->fetch() ? true : false;
        if ($emailExists) { $errors[] = "Email address is already in use. Try another one."; }
        
        // Process the password
        if (empty($password) || empty($passwordConfirm)) { $errors[] = 'Passwords are required.'; }
        if ($password !== $passwordConfirm) { $errors[] = 'Passwords must match.'; }
        $password = password_hash($password, PASSWORD_DEFAULT);
        
        if (empty($errors)) {
            
            if ($control["verifyemail"] == 1) {
                $verifycode = "";
                for ($i=0; $i<8; $i++) {
                    $verifycode .= chr(rand(65,90));
                }
            } else {
                $verifycode='1';
            }

            $insert = prepare('insert into {{ table }} set regdate=now(), verify=?, username=?, password=?, email=?, class=?, difficulty=?', 'users', $link);
            execute($insert, [
                $verifycode,
                $username,
                $password,
                $email,
                $_POST['class'],
                $_POST['difficulty'],
            ]);
            
            if ($control["verifyemail"] == 1) {
                if (sendregmail($email, $verifycode) == true) {
                    $page = "Your account was created successfully.<br /><br />You should receive an Account Verification email shortly. You will need the verification code contained in that email before you are allowed to log in. Once you have received the email, please visit the <a href=\"users.php?do=verify\">Verification Page</a> to enter your code and start playing.";
                } else {
                    $page = "Your account was created successfully.<br /><br />However, there was a problem sending your verification email. Please check with the game administrator to help resolve this problem.";
                }
            } else {
                $page = "Your account was created succesfully.<br /><br />You may now continue to the <a href=\"users.php?do=login\">Login Page</a> and continue playing ".$control["gamename"]."!";
            }
        } else {
            $errorList = '';
            foreach ($errors as $error) {
                $errorList .= "{$error} <br />";
            }

            $page = "The following error(s) occurred when your account was being made:<br /><span style=\"color:red;\">$errorList</span><br />Please go back and try again.";
        }
    } else {
        $page = gettemplate("register");
    }

    if ($control["verifyemail"] == 1) { 
        $control["verifytext"] = "<br /><span class=\"small\">A verification code will be sent to the address above, and you will not be able to log in without first entering the code. Please be sure to enter your correct email address.</span>";
    } else {
        $control["verifytext"] = "";
    }

    $page = parsetemplate($page, $control);
    
    $topnav = "<a href=\"users.php?do=login\"><img src=\"resources/img/button_login.gif\" alt=\"Log In\" border=\"0\" /></a><a href=\"users.php?do=register\"><img src=\"resources/img/button_register.gif\" alt=\"Register\" border=\"0\" /></a><a href=\"help.php\"><img src=\"resources/img/button_help.gif\" alt=\"Help\" border=\"0\" /></a>";
    display($page, "Register", false, false, false);
}

function verify()
{
    global $link;

    if (isset($_POST['submit'])) {
        $data = trimData($_POST);

        $user = prepare('select username, email, verify from {{ table }} where username=?', 'users', $link);
        $user = execute($user, [$data['username']])->fetch();

        if (! $user) { die('No account exists with that username.'); }
        if ($user["verify"] == 1) { die("Your account is already verified."); }
        if ($user["email"] != $data['email']) { die("Incorrect email address."); }
        if ($user["verify"] != $data['verify']) { die("Incorrect verification code."); }

        // If we've made it this far, should be safe to update their account.
        $query = prepare("update {{ table }} set verify='1' where username=?", 'users', $link);
        execute($query, [$data['username']]);

        display("Your account was verified successfully.<br /><br />You may now continue to the <a href=\"users.php?do=login\">Login Page</a> and start playing the game.<br /><br />Thanks for playing!","Verify Email",false,false,false);
    }

    $page = gettemplate("verify");
    $topnav = "<a href=\"users.php?do=login\"><img src=\"resources/img/button_login.gif\" alt=\"Log In\" border=\"0\" /></a><a href=\"users.php?do=register\"><img src=\"resources/img/button_register.gif\" alt=\"Register\" border=\"0\" /></a><a href=\"help.php\"><img src=\"resources/img/button_help.gif\" alt=\"Help\" border=\"0\" /></a>";
    display($page, "Verify Email", false, false, false);
}

function lostpassword()
{
    global $link;

    if (isset($_POST['submit'])) {
        $data = trimData($_POST);

        $user = prepare('select id from {{ table }} where email=?', 'users', $link);
        $user = execute($user, [$data['email']])->fetch();

        if (! $user) { die('No account with that email address.'); }

        $new = '';
        for ($i = 0; $i < 8; $i++) {
            $new .= chr(rand(65, 90));
        }
        $hashed = password_hash($new, PASSWORD_DEFAULT);

        $update = prepare('update {{ table }} set password=? where email=?', 'users', $link);
        execute($update, [$hashed, $data['email']]);

        if (sendpassemail($data['email'], $new) == true) {
            display("Your new password was emailed to the address you provided.<br /><br />Once you receive it, you may <a href=\"users.php?do=login\">Log In</a> and continue playing.<br /><br />Thank you.","Lost Password",false,false,false);
        } else {
            display("There was an error sending your new password.<br /><br />Please check with the game administrator for more information.<br /><br />We apologize for the inconvience.","Lost Password",false,false,false);
        }

        return;
    }

    $page = gettemplate("lostpassword");
    $topnav = "<a href=\"users.php?do=login\"><img src=\"resources/img/button_login.gif\" alt=\"Log In\" border=\"0\" /></a><a href=\"users.php?do=register\"><img src=\"resources/img/button_register.gif\" alt=\"Register\" border=\"0\" /></a><a href=\"help.php\"><img src=\"resources/img/button_help.gif\" alt=\"Help\" border=\"0\" /></a>";
    display($page, "Lost Password", false, false, false);
}

function changepassword()
{
    global $link;

    if (isset($_POST["submit"])) {
        $data = trimData($_POST);

        $user = prepare('select id, password from {{ table }} where username=?', 'users', $link);
        $user = execute($user, [$data['username']])->fetch();

        if (! $user) { die('No account with that username.'); }
        if (! password_verify($data['oldpass'], $user['password'])) { die('Password was incorrect.'); }
        if ($data['newpass1'] != $data['newpass2']) { die('New passwords don\'t match.'); }

        $new = password_hash($data['newpass1'], PASSWORD_DEFAULT);
        $update = prepare('update {{ table }} set password=? where username=?', 'users', $link);
        execute($update, [$new, $data['username']]);

        if (isset($_COOKIE["dkgame"])) { deleteCookie(); }

        display("Your password was changed successfully.<br /><br />You have been logged out of the game to avoid cookie errors.<br /><br />Please <a href=\"users.php?do=login\">log back in</a> to continue playing.","Change Password",false,false,false);

        return;
    }

    $page = gettemplate("changepassword");
    $topnav = "<a href=\"users.php?do=login\"><img src=\"resources/img/button_login.gif\" alt=\"Log In\" border=\"0\" /></a><a href=\"users.php?do=register\"><img src=\"resources/img/button_register.gif\" alt=\"Register\" border=\"0\" /></a><a href=\"help.php\"><img src=\"resources/img/button_help.gif\" alt=\"Help\" border=\"0\" /></a>";
    display($page, "Change Password", false, false, false); 
}

function sendpassemail($emailaddress, $password)
{
    global $control;
    
$email = <<<END
You or someone using your email address submitted a Lost Password application on the {$control['gamename']} server, located at {$control['gameurl']}. 

We have issued you a new password so you can log back into the game.

Your new password is: $password

Thanks for playing.
END;

    $status = mymail($emailaddress, "{$control['gamename']} Lost Password", $email);
    return $status;
}

function sendregmail($emailaddress, $vercode)
{
    global $control;

    $verurl = "{$control['gameurl']}?do=verify";
    
$email = <<<END
You or someone using your email address recently signed up for an account on the {$control['gamename']} server, located at {$control['gameurl']}.

This email is sent to verify your registration email. In order to begin using your account, you must verify your email address. 
Please visit the Verification Page ({$verurl}) and enter the code below to activate your account.
Verification code: {$vercode}

If you were not the person who signed up for the game, please disregard this message. You will not be emailed again.
END;

    $status = mymail($emailaddress, "{$control['gamename']} Account Verification", $email);
    return $status;
}

function mymail($to, $title, $body, $from = '')
{
    global $control;
    
    $from = trim($from);

    if (!$from) {
        $from = '<'.$control["adminemail"].'>';
    }

    $rp     = $control["adminemail"];
    $org    = $control['gameurl'];
    $mailer = 'PHP';

    $head   = '';
    $head  .= "Content-Type: text/plain \r\n";
    $head  .= "Date: ". date('r'). " \r\n";
    $head  .= "Return-Path: $rp \r\n";
    $head  .= "From: $from \r\n";
    $head  .= "Sender: $from \r\n";
    $head  .= "Reply-To: $from \r\n";
    $head  .= "Organization: $org \r\n";
    $head  .= "X-Sender: $from \r\n";
    $head  .= "X-Priority: 3 \r\n";
    $head  .= "X-Mailer: $mailer \r\n";

    $body  = str_replace("\r\n", "\n", $body);
    $body  = str_replace("\n", "\r\n", $body);

    return mail($to, $title, $body, $head);
}

/**
 * Sets the "dkgame" cookie to a time in the past in order to delete it. Is meant
 * to log the user out.
 */
function logout()
{
    deleteCookie();
    redirect('users.php?do=login');
}