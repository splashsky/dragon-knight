<!-- Cached on 4th April 2023 02:59:36 PM -->
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    
        <title>Dragon Knight - Login</title>
    

    

    <link rel="stylesheet" href="/css/vollkorn.css">
    <link rel="stylesheet" href="/css/main.css">
</head>
<body>
    <div id="container" class="container max-w-5xl mx-auto">
        <header class="flex justify-between">
            <img src="/img/dk.png" alt="Dragon Knight" class="max-w-xs">
            <nav class="flex items-center">
                <a class="mr-2" href="/login">Log in</a>
                <a class="mr-2" href="/register">Register</a>
                <a href="/help">Help</a>
            </nav>
        </header>

        <main class="my-4">
            
<h1>Login</h1>

<form method="POST" action="/auth/login">
    <div class="form-group">
        <label for="email">Email</label>
        <input type="email" class="form-control" id="email" name="email" placeholder="Email">
    </div>
    <div class="form-group">
        <label for="password">Password</label>
        <input type="password" class="form-control" id="password" name="password" placeholder="Password">
    </div>
    <button type="submit" class="btn btn-default">Login</button>
</form>

        </main>
    </div>
</body>
</html>



