<?php

class Router
{
    private array $routes = [];
    private $notFound;
    private string $defaultConstraint = '([\w\-]+)';
    private string $currentPrefix = '';
    private string $lastInsertedRoute = '';

    /**
     * Create an instance of a router. The provided basePath will be the / root of all routes.
     */
    public function __construct(private string $basePath = '') {}

    /**
     * Register a GET route.
     */
    public function get(string $route, callable $action): self
    {
        $this->add($route, $action, 'GET');
        return $this;
    }

    /**
     * Register a POST route.
     */
    public function post(string $route, callable $action): self
    {
        $this->add($route, $action, 'POST');
        return $this;
    }

    /**
     * Register a PUT route.
     */
    public function put(string $route, callable $action): self
    {
        $this->add($route, $action, 'PUT');
        return $this;
    }

    /**
     * Register a PATCH route.
     */
    public function patch(string $route, callable $action): self
    {
        $this->add($route, $action, 'PATCH');
        return $this;
    }

    /**
     * Register a DELETE route.
     */
    public function delete(string $route, callable $action): self
    {
        $this->add($route, $action, 'DELETE');
        return $this;
    }

    /**
     * Return the array of registered routes.
     */
    public function routes(): array
    {
        return $this->routes;
    }

    /**
     * Set a callable for 404 responses.
     */
    public function setNotFound(callable $action)
    {
        $this->notFound = $action;
    }

    /**
     * Change the default constraint for URI parameters from ([\w\-]+)
     */
    public function setDefaultConstraint(string $constraint = '([\w\-]+)')
    {
        $this->defaultConstraint = $constraint;
    }

    private function trimRoute(string $route): string
    {
        $route = trim(trim($route), '/');
        return "/$route";
    }

    /**
     * Create a prefix group for routes. To use, pass a closure that can take one argument to $routes,
     * and define routes in that closure as normal, using the argument as the router.
     */
    public function prefix(string $prefix, callable $routes)
    {
        $this->currentPrefix = $prefix;
        $routes($this);
        $this->currentPrefix = '';
    }

    /**
     * Define a constraint for a route parameter. If only passing one parameter, 
     * provide the parameter name as first argument and constraint as second. If 
     * adding constraints for multiple parameters, pass an array of 'parameter' => 'constraint'
     * pairs.
     */
    public function with(string|array $parameter, string $constraint = ''): self
    {
        $method = $_SERVER['REQUEST_METHOD'];
        $last = $this->lastInsertedRoute;

        if (is_array($parameter)) {
            foreach ($parameter as $param => $constraint) {
                $this->routes[$method][$last]['constraints'][$param] = $constraint;
            }

            return $this;
        }

        $this->routes[$method][$last]['constraints'][$parameter] = $constraint;

        return $this;
    }

    /**
     * Tokenizes a URI according to constraint rules. 
     */
    private function tokenize(string $uri, array $constraints = []): string
    {
        preg_match_all('/(?:{([\w\-]+)})+/', $uri, $matches);
        $matches = $matches[1];

        foreach ($matches as $match) {
            $pattern = '{'.$match.'}';

            if (in_array($match, array_keys($constraints))) {
                // Do some voodoo to allow users to use parentheses in their constraints if they want
                $constraint = '('.rtrim(ltrim(trim($constraints[$match]), '('), ')').')';

                $uri = str_replace($pattern, $constraint, $uri);
            } else {
                $uri = str_replace($pattern, $this->defaultConstraint, $uri);
            }
        }

        return $uri;
    }

    /**
     * Add a route to the list of registered routes.
     */
    public function add(string $route, callable|string $action, string $method = 'GET')
    {
        // If a prefix exists, prepend it to the route
        if (!empty($this->currentPrefix)) {
            $route = $this->currentPrefix . $route;
        }

        $trimmed = $this->trimRoute($route);
        $this->lastInsertedRoute = $trimmed;

        $this->routes[$method][$trimmed] = ['action' => $action, 'constraints' => []];
    }

    /**
     * Runs the router. Returns the results of the action of the route, if found. Executes
     * the $notFound callable if there is one, or just dies with '404' if not.
     */
    public function run()
    {
        $basePath = $this->trimRoute($this->basePath);
        $uri = parse_url($_SERVER['REQUEST_URI'])['path'];
        $path = urldecode($this->trimRoute($uri));

        

        foreach ($this->routes[$_SERVER['REQUEST_METHOD']] as $route => $opts) {
            $tokenized = $this->tokenize($this->trimRoute($basePath.$route), $opts['constraints']);
            $tokenized = str_replace('/', '\/', $tokenized);
            
            if (preg_match('/^'.$tokenized.'$/', $path, $matches)) {
                array_shift($matches);
                if (is_callable($opts['action'])) {
                    return call_user_func_array($opts['action'], $matches);
                }
            }
        }

        if (is_callable($this->notFound)) {
            return call_user_func_array($this->notFound, [$path]);
        } else {
            die('404');
        }
    }
}