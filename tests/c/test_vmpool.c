/* test_vmpool.c :: runtime integration: codecache + watcher + vmpool + dk API + db, and the
 * arena allocator behind pool VMs (snapshot/restore). */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "arena.h"
#include "bind.h"
#include "codecache.h"
#include "config.h"
#include "http.h"
#include "lauxlib.h"
#include "minitest.h"
#include "stats.h"
#include "util.h"
#include "vmpool.h"

static char root[256];
static dk_config cfg;
static sqlite3 *db;

static void sleep_ms(int ms)
{
	struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
	while (nanosleep(&ts, &ts) < 0 && errno == EINTR) {}
}

static void mkdirs(const char *rel)
{
	char p[512];
	snprintf(p, sizeof p, "%s/%s", root, rel);
	for (char *s = p + 1; *s; s++) {
		if (*s == '/') { *s = 0; mkdir(p, 0755); *s = '/'; }
	}
	mkdir(p, 0755);
}

static void put(const char *rel, const char *content)
{
	char p[512];
	snprintf(p, sizeof p, "%s/%s", root, rel);
	FILE *f = fopen(p, "w");
	if (!f) { perror(p); exit(1); }
	fputs(content, f);
	fclose(f);
}

/* Write a file and wait until the watcher has bumped the generation. */
static int put_and_wait(const char *rel, const char *content)
{
	uint64_t g = codecache_generation();
	put(rel, content);
	for (int i = 0; i < 400; i++) {
		if (codecache_generation() != g) return 1;
		sleep_ms(5);
	}
	return 0;
}

typedef struct {
	int   status;
	char  body[8192];
	char  headers[2048];
} result;

static int request_full(result *out, const char *method, const char *target,
						dk_header *hdrs, size_t nh, const char *body)
{
	char path[512], query[512] = "";
	snprintf(path, sizeof path, "%s", target);
	char *q = strchr(path, '?');
	if (q) { snprintf(query, sizeof query, "%s", q + 1); *q = 0; }
	dk_request req = {
		.method = method, .target = target, .path = path, .query = query,
		.headers = hdrs, .nheaders = nh, .body = body, .body_len = body ? strlen(body) : 0,
		.remote_addr = "127.0.0.1",
	};
	dk_response resp;
	resp_init(&resp);
	char err[2048];
	dk_vm *vm = vmpool_acquire(err, sizeof err);
	memset(out, 0, sizeof *out);
	if (!vm) {
		out->status = -1;
		snprintf(out->body, sizeof out->body, "%s", err);
		resp_free(&resp);
		return -1;
	}
	bind_handle(vm_state(vm), &cfg, db, &req, &resp);
	vmpool_release(vm);
	out->status = resp.status;
	snprintf(out->body, sizeof out->body, "%s", resp.body.p ? resp.body.p : "");
	size_t off = 0;
	for (size_t i = 0; i < resp.nheaders && off < sizeof out->headers; i++)
		off += (size_t)snprintf(out->headers + off, sizeof out->headers - off, "%s: %s\n",
								resp.headers[i].name, resp.headers[i].value);
	resp_free(&resp);
	return 0;
}

static result R;
static const char *get(const char *target)
{
	request_full(&R, "GET", target, NULL, 0, NULL);
	return R.body;
}

static const char *MAIN_LUA =
	"local M = {}\n"
	"M['/counter'] = function() counter = (counter or 0) + 1; return tostring(counter) end\n"
	"M['/mod'] = function() return require('lib.mod').v end\n"
	"M['/dbtest'] = function() return require('dbtest')() end\n"
	"M['/insert'] = function(req)\n"
	"  dk.db:exec('INSERT INTO t2(v) VALUES (?)', req.query.v)\n"
	"  if req.query.fail then error('fail after insert') end\n"
	"  return 'inserted'\n"
	"end\n"
	"M['/count'] = function() return tostring(dk.db:value('SELECT count(*) FROM t2')) end\n"
	"M['/render'] = function(req) return dk.render('page', {x = req.query.x, y = '<i>raw</i>', items = {'a<', 'b'}}) end\n"
	"M['/render_h'] = function() return dk.render('hh', {}, {escape = dk.html, shout = function(s) return s:upper() end}) end\n"
	"M['/req'] = function(req)\n"
	"  local f = function(t) local k = {} for n, v in pairs(t) do k[#k+1] = n .. '=' .. v end table.sort(k) return table.concat(k, ',') end\n"
	"  return req.method .. '|' .. req.path .. '|' .. f(req.query) .. '|' .. f(req.form) .. '|' .. f(req.cookies) .. '|' .. (req.headers['x-test'] or '') .. '|' .. req.body\n"
	"end\n"
	"M['/resp'] = function() return {status = 201, headers = {{'X-A', '1'}, {'Set-Cookie', 'a=1'}, {'Set-Cookie', 'b=2'}}, body = 'made'} end\n"
	"M['/inject'] = function() return {headers = {{'X-A', 'x\\r\\nEvil: 1'}}, body = 'x'} end\n"
	"M['/missing'] = function() return require('nope.nothere') end\n"
	"M['/badname'] = function() return dk.render('../etc/passwd', {}) end\n"
	"M['/crypto'] = function()\n"
	"  local c = dk.crypto\n"
	"  return c.hex(c.sha256('abc')) .. '|' .. #c.random(16) .. '|' .. tostring(c.eq('a', 'a')) .. tostring(c.eq('a', 'b')) .. tostring(c.eq('a', 'ab'))\n"
	"    .. '|' .. dk.html('<\"&\\'>') .. '|' .. dk.html(nil) .. '|' .. dk.html(5) .. '|' .. dk.urlencode('a b/ü') .. '|' .. dk.urldecode('a+b%2F%C3%BC')\n"
	"    .. '|' .. math.type(dk.now()) .. '|' .. math.type(dk.clock()) .. '|' .. tostring(dk.config.custom_key)\n"
	"end\n"
	"M['/stats'] = function() local s = dk.vmstats() return s.built .. ',' .. s.generation end\n"
	"M['/boot'] = function() local s = dk.vmstats() return s.boot_id end\n"
	"M['/list'] = function(req) return table.concat(dk.list_modules(req.query.p or ''), ',') end\n"
	"M['/hog'] = function() local t = {} for i = 1, 1e7 do t[i] = i end return 'x' end\n"
	"M['/fin'] = function(req)\n"
	"  setmetatable({}, {__gc = function() local f = io.open(req.query.path, 'w') f:write('finalized') f:close() end})\n"
	"  return 'ok'\n"
	"end\n"
	"M['/leak'] = function(req) io.open(req.query.path, 'w'):write('flushed at close') return 'ok' end\n"
	"M['/buf'] = function() return tostring(#string.rep('ab', 100000) + #table.concat({'x', 'y'}, ',')) end\n"
	"return function(req)\n"
	"  local f = M[req.path]\n"
	"  if not f then return {status = 404, body = 'nf'} end\n"
	"  local r = f(req)\n"
	"  if type(r) == 'string' then return {status = 200, headers = {{'Content-Type', 'text/plain'}}, body = r} end\n"
	"  return r\n"
	"end\n";

static const char *DBTEST_LUA =
	"return function()\n"
	"  local db = dk.db\n"
	"  db:exec('CREATE TABLE IF NOT EXISTS ty (i INTEGER, r REAL, s TEXT, b BLOB, n TEXT, t INTEGER)')\n"
	"  db:exec('DELETE FROM ty')\n"
	"  local ch, id = db:exec('INSERT INTO ty VALUES (?, ?, ?, ?, ?, ?)', 42, 1.5, 'str', 'a\\0b', nil, true)\n"
	"  assert(ch == 1 and math.type(id) == 'integer', 'exec returns')\n"
	"  local rows = db:query('SELECT * FROM ty')\n"
	"  assert(#rows == 1, 'one row')\n"
	"  local r = rows[1]\n"
	"  assert(math.type(r.i) == 'integer' and r.i == 42, 'int')\n"
	"  assert(math.type(r.r) == 'float' and r.r == 1.5, 'real')\n"
	"  assert(r.s == 'str', 'text')\n"
	"  assert(r.b == 'a\\0b' and #r.b == 3, 'blob with NUL')\n"
	"  assert(r.n == nil, 'null absent')\n"
	"  assert(r.t == 1, 'boolean -> 1')\n"
	"  local n = 0 for _ in pairs(r) do n = n + 1 end\n"
	"  assert(n == 5, 'null key absent')\n"
	"  assert(db:first('SELECT * FROM ty WHERE i = ?', 99) == nil, 'first nil')\n"
	"  assert(db:first('SELECT i FROM ty WHERE i = ?', 42).i == 42, 'first')\n"
	"  assert(db:value('SELECT s FROM ty') == 'str', 'value')\n"
	"  assert(db:value('SELECT s FROM ty WHERE 0') == nil, 'value nil')\n"
	"  assert(#db:query('SELECT * FROM ty WHERE 0') == 0, 'empty query')\n"
	"  for k = 1, 100 do db:value('SELECT ? + 1', k) end\n"
	"  assert(db:value('SELECT ? + 1', 41) == 42, 'cached stmt rebinding')\n"
	"  local ok, e = pcall(db.query, db, 'SELEC nonsense')\n"
	"  assert(not ok and e:find('SQL error', 1, true) and e:find('SELEC nonsense', 1, true), 'syntax err: ' .. tostring(e))\n"
	"  ok, e = pcall(db.query, db, 'SELECT ?', 1, 2)\n"
	"  assert(not ok and e:find('expects 1 parameter', 1, true), 'param count: ' .. tostring(e))\n"
	"  ok, e = pcall(db.exec, db, 'SELECT 1; SELECT 2')\n"
	"  assert(not ok and e:find('multiple statements', 1, true), 'multi: ' .. tostring(e))\n"
	"  ok, e = pcall(db.exec, db, 'INSERT INTO ty(i) VALUES (?)', {})\n"
	"  assert(not ok and e:find('unsupported type table', 1, true), 'bad param: ' .. tostring(e))\n"
	"  ok, e = pcall(function() return db:exec('INSERT INTO nosuch VALUES (1)') end)\n"
	"  assert(not ok and e:find('no such table', 1, true) and e:find('dbtest.lua', 1, true), 'where: ' .. tostring(e))\n"
	"  db:exec_script('CREATE TABLE IF NOT EXISTS s1(a); INSERT INTO s1 VALUES (1); INSERT INTO s1 VALUES (2);')\n"
	"  assert(db:value('SELECT sum(a) FROM s1') == 3, 'exec_script')\n"
	"  return 'ok'\n"
	"end\n";

static void setup(void)
{
	const char *tmp = getenv("TMPDIR");
	snprintf(root, sizeof root, "%s/dk-test-vmpool-%d", tmp && *tmp ? tmp : "/tmp", (int)getpid());
	mkdirs("app/lib");
	mkdirs("templates");
	char conf[2048];
	snprintf(conf, sizeof conf,
			 "return { app_dir = '%s/app', template_dir = '%s/templates', db_path = '%s/data/t.db',\n"
			 "  workers = 1, spares = 2, dev = true, custom_key = 'v1', vm_memory_limit = 16777216 }\n",
			 root, root, root);
	put("config.lua", conf);
	put("app/main.lua", MAIN_LUA);
	put("app/lib/mod.lua", "return { v = 'one' }\n");
	put("app/dbtest.lua", DBTEST_LUA);
	put("templates/page.html",
		"<p>{{ x }}</p>{{{ y }}}\n{% for i, it in ipairs(items) do %}[{{ i }}:{{ it }}]{% end %}\n");
	put("templates/hh.html", "{{ shout('hi') }}");

	char path[512], err[512];
	snprintf(path, sizeof path, "%s/config.lua", root);
	if (config_load(&cfg, path, err, sizeof err) < 0) { fprintf(stderr, "%s\n", err); exit(1); }
	db = db_open(cfg.db_path, err, sizeof err);
	if (!db) { fprintf(stderr, "%s\n", err); exit(1); }
	sqlite3_exec(db, "CREATE TABLE t2(v TEXT)", NULL, NULL, NULL);
	CHECK(codecache_init(&cfg) == 0);
	CHECK(codecache_watch_start(vmpool_on_change, NULL) == 0);
	CHECK(vmpool_init(&cfg) == 0);
}

static void wait_ready(int n)
{
	vmpool_stats s;
	for (int i = 0; i < 400; i++) {
		vmpool_get_stats(&s);
		if (s.ready >= n) return;
		sleep_ms(5);
	}
}

static void test_fresh_vm(void)
{
	CHECK_STR_EQ(get("/counter"), "1");
	CHECK_STR_EQ(get("/counter"), "1");   /* global from previous request is gone */
	CHECK(R.status == 200);
}

static void test_hot_path(void)
{
	wait_ready(2);
	vmpool_stats a, b;
	vmpool_get_stats(&a);
	CHECK(a.ready == 2);
	get("/counter");
	vmpool_get_stats(&b);
	CHECK(b.hot_acquires == a.hot_acquires + 1);
	CHECK(b.cold_acquires == a.cold_acquires);
	wait_ready(2);
	vmpool_get_stats(&b);
	CHECK(b.ready == 2);
	for (int i = 0; i < 200 && b.reaped < b.built - 2; i++) { sleep_ms(5); vmpool_get_stats(&b); }
	CHECK(b.reaped == b.built - 2);        /* every used VM was closed by the warmer */
}

static void test_module_reload(void)
{
	CHECK_STR_EQ(get("/mod"), "one");
	CHECK(put_and_wait("app/lib/mod.lua", "return { v = 'two' }\n"));
	CHECK_STR_EQ(get("/mod"), "two");
	wait_ready(2);
	CHECK_STR_EQ(get("/mod"), "two");      /* warmed spare also runs new code */
	/* new subdirectory gets watched */
	mkdirs("app/sub");
	sleep_ms(50);
	put("app/sub/x.lua", "return 1\n");
	CHECK(put_and_wait("app/sub/x.lua", "return 2\n"));
}

static void test_syntax_error_recovery(void)
{
	CHECK(put_and_wait("app/main.lua", "return function(req) return {body = 'x' end\n"));
	request_full(&R, "GET", "/counter", NULL, 0, NULL);
	CHECK(R.status == -1);
	CHECK(strstr(R.body, "main.lua") != NULL);
	/* warmer must back off, not spin */
	vmpool_stats a, b;
	sleep_ms(50);
	vmpool_get_stats(&a);
	sleep_ms(150);
	vmpool_get_stats(&b);
	CHECK(a.built == b.built);
	CHECK(b.ready == 0);
	CHECK(put_and_wait("app/main.lua", MAIN_LUA));
	CHECK_STR_EQ(get("/counter"), "1");
	wait_ready(2);
	vmpool_get_stats(&b);
	CHECK(b.ready == 2);
}

static void test_db(void)
{
	CHECK_STR_EQ(get("/dbtest"), "ok");
	CHECK(R.status == 200);
	if (R.status != 200) fprintf(stderr, "%s\n", R.body);
	CHECK_STR_EQ(get("/count"), "0");
	CHECK_STR_EQ(get("/insert?v=a"), "inserted");
	CHECK_STR_EQ(get("/count"), "1");
	get("/insert?v=b&fail=1");
	CHECK(R.status == 500);
	CHECK(strstr(R.body, "fail after insert") != NULL);  /* dev: traceback shown */
	CHECK(strstr(R.body, "stack traceback") != NULL);
	CHECK_STR_EQ(get("/count"), "1");                     /* rolled back */
	CHECK(sqlite3_get_autocommit(db));
}

static void test_render(void)
{
	CHECK_STR_EQ(get("/render?x=%3Cb%3E%26"), "<p>&lt;b&gt;&amp;</p><i>raw</i>\n[1:a&lt;][2:b]\n");
	CHECK_STR_EQ(get("/render"), "<p></p><i>raw</i>\n[1:a&lt;][2:b]\n");
	CHECK_STR_EQ(get("/render_h"), "HI");
	CHECK(put_and_wait("templates/page.html", "v2 {{ x }}"));
	CHECK_STR_EQ(get("/render?x=1"), "v2 1");
	put_and_wait("templates/bad.html", "{{ x ");
	get("/render");
	CHECK(R.status == 200);   /* unrelated broken template doesn't matter */
	CHECK(put_and_wait("templates/page.html", "{% if x then %}"));
	get("/render");
	CHECK(R.status == 500);
	CHECK(strstr(R.body, "page.html") != NULL);
	get("/badname");
	CHECK(R.status == 500 && strstr(R.body, "invalid template name") != NULL);
}

static void test_request_response(void)
{
	dk_header h[] = {
		{ "content-type", "application/x-www-form-urlencoded; charset=utf-8" },
		{ "cookie", "a=1; b=\"two\"; a=3" },
		{ "x-test", "t1" },
		{ "x-test", "t2" },
	};
	request_full(&R, "POST", "/req?q=1&q=2&e=a%20b&k&=bad", h, 4, "f=x+y&g=%26");
	CHECK_STR_EQ(R.body, "POST|/req|e=a b,k=,q=2|f=x y,g=&|a=1,b=two|t1, t2|f=x+y&g=%26");
	h[0].value = "multipart/form-data; boundary=x";
	request_full(&R, "POST", "/req", h, 1, "f=1");
	CHECK_STR_EQ(R.body, "POST|/req|||||f=1");

	get("/resp");
	CHECK(R.status == 201);
	CHECK_STR_EQ(R.body, "made");
	CHECK(strstr(R.headers, "X-A: 1\nSet-Cookie: a=1\nSet-Cookie: b=2\n") != NULL);
	CHECK(strstr(R.headers, "Content-Type: text/html; charset=utf-8") != NULL);
	get("/inject");
	CHECK(R.status == 500);
	CHECK(strstr(R.headers, "Evil") == NULL);
	get("/missing");
	CHECK(R.status == 500 && strstr(R.body, "nope.nothere") != NULL);
	get("/nowhere");
	CHECK(R.status == 404);
}

static void test_api(void)
{
	CHECK_STR_EQ(get("/crypto"),
				 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad|16|truefalsefalse"
				 "|&lt;&quot;&amp;&#39;&gt;||5|a%20b%2F%C3%BC|a b/\xC3\xBC|integer|float|v1");
	char conf[2048];
	snprintf(conf, sizeof conf,
			 "return { app_dir = '%s/app', template_dir = '%s/templates', db_path = '%s/data/t.db',\n"
			 "  workers = 1, spares = 2, dev = true, custom_key = 'v2', vm_memory_limit = 16777216 }\n",
			 root, root, root);
	CHECK(put_and_wait("config.lua", conf));
	CHECK(strstr(get("/crypto"), "|v2") != NULL);    /* dk.config hot reload */
}

static void test_cli(void)
{
	put("app/cli_t.lua",
		"return { run = function(a, b) dk.db:exec('INSERT INTO t2(v) VALUES (?)', a .. b) return 3 end }\n");
	put("app/cli_f.lua", "return { run = function() dk.db:exec(\"INSERT INTO t2(v) VALUES ('z')\") error('nope') end }\n");
	char err[512];
	dk_vm *vm = vm_build_ex(&cfg, 0, err, sizeof err);
	CHECK(vm != NULL);
	char *args[] = { "x", "y" };
	if (vm) CHECK(bind_run_cli(vm_state(vm), &cfg, db, "cli_t", 2, args) == 3);
	vm_destroy(vm);
	vm = vm_build_ex(&cfg, 0, err, sizeof err);
	if (vm) CHECK(bind_run_cli(vm_state(vm), &cfg, db, "cli_f", 0, NULL) == 1);
	vm_destroy(vm);
	sqlite3_stmt *st;
	sqlite3_prepare_v2(db, "SELECT count(*) FROM t2 WHERE v IN ('xy', 'z')", -1, &st, NULL);
	sqlite3_step(st);
	CHECK(sqlite3_column_int(st, 0) == 1);
	sqlite3_finalize(st);
}

static void test_names(void)
{
	lua_State *L = luaL_newstate();
	CHECK(codecache_load(L, CC_MODULE, "../x") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_MODULE, "a..b") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_MODULE, "a/b") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_TEMPLATE, "/etc/passwd") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_TEMPLATE, "a/../../x") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_TEMPLATE, "a b") == LUA_ERRFILE);
	CHECK(codecache_load(L, CC_MODULE, "lib.mod") == LUA_OK);
	CHECK(codecache_load(L, CC_MODULE, "lib.mod") == LUA_OK);   /* cached path */
	lua_settop(L, 0);
	lua_close(L);
}

static void test_list_modules(void)
{
	mkdirs("app/things/sub");
	put("app/things/beta.lua", "return 2\n");
	put("app/things/alpha.lua", "return 1\n");
	put("app/things/my-mod_2.lua", "return 3\n");
	put("app/things/two.dots.lua", "return 0\n");   /* not addressable by require */
	put("app/things/.hidden.lua", "return 0\n");
	put("app/things/notes.txt", "x");
	put("app/things/sub/deep.lua", "return 0\n");    /* not recursive */
	mkdirs("app/things/dir.lua");                    /* a directory, not a module */

	char **list;
	int n = codecache_list_modules("things", &list);
	CHECK(n == 3);
	if (n == 3) {
		CHECK_STR_EQ(list[0], "things.alpha");
		CHECK_STR_EQ(list[1], "things.beta");
		CHECK_STR_EQ(list[2], "things.my-mod_2");
	}
	codecache_free_list(list, n);
	CHECK(codecache_list_modules("things.sub", &list) == 1);
	if (list) CHECK_STR_EQ(list[0], "things.sub.deep");
	codecache_free_list(list, 1);
	CHECK(codecache_list_modules("nothere.at_all", &list) == 0 && list == NULL);
	CHECK(codecache_list_modules("../x", &list) == -1);
	CHECK(codecache_list_modules("a..b", &list) == -1);
	CHECK(codecache_list_modules("a/b", &list) == -1);
	n = codecache_list_modules("", &list);           /* app root: main, dbtest, ... */
	CHECK(n >= 3);
	codecache_free_list(list, n);

	CHECK_STR_EQ(get("/list?p=things"), "things.alpha,things.beta,things.my-mod_2");
	/* a new file shows up on the next call, without a restart */
	put("app/things/gamma.lua", "return 4\n");
	CHECK_STR_EQ(get("/list?p=things"), "things.alpha,things.beta,things.gamma,things.my-mod_2");
	CHECK_STR_EQ(get("/list?p=things.nope"), "");
	get("/list?p=..%2Fetc");
	CHECK(R.status == 500 && strstr(R.body, "invalid module prefix") != NULL);

	char boot[64];
	snprintf(boot, sizeof boot, "%s", get("/boot"));
	CHECK(strlen(boot) == 32);
	CHECK_STR_EQ(get("/boot"), boot);     /* same process, same id */
}

/* Pool VMs are recycled: restored to their snapshot after each request, not rebuilt. */
static void test_recycle(void)
{
	wait_ready(2);
	vmpool_stats a, b;
	vmpool_get_stats(&a);
	for (int i = 0; i < 5; i++) CHECK_STR_EQ(get("/counter"), "1");
	wait_ready(2);
	vmpool_get_stats(&b);
	CHECK(b.built == a.built);
	CHECK(b.recycled == a.recycled + 5);
	CHECK(b.hot_acquires == a.hot_acquires + 5);
}

/* A request that needs more than vm_memory_limit fails alone; the next one is fine. A
 * finalizer the request left behind runs before the restore; a file left open is
 * closed; lauxlib buffers (finalizers that only free memory) need no collection. */
static void test_arena_limits(void)
{
	get("/hog");
	CHECK(R.status == 500 && strstr(R.body, "not enough memory") != NULL);
	CHECK_STR_EQ(get("/counter"), "1");

	char path[600], target[700];
	snprintf(path, sizeof path, "%s/finalized.txt", root);
	snprintf(target, sizeof target, "/fin?path=%s", path);
	CHECK_STR_EQ(get(target), "ok");
	size_t n;
	char *got = read_file(path, &n);
	CHECK(got && strcmp(got, "finalized") == 0);
	free(got);
	snprintf(path, sizeof path, "%s/leaked.txt", root);
	snprintf(target, sizeof target, "/leak?path=%s", path);
	CHECK_STR_EQ(get(target), "ok");
	got = read_file(path, &n);
	CHECK(got && strcmp(got, "flushed at close") == 0);
	free(got);

	uint64_t f0 = stat_get(ST_vm_finalize);
	CHECK_STR_EQ(get("/buf"), "200003");
	CHECK(stat_get(ST_vm_finalize) == f0);
}

/* The allocator itself: classes, free lists, growth in place, snapshot and restore. */
static void test_arena(void)
{
	dk_arena *a = arena_new(4u << 20);
	CHECK(a != NULL);
	if (!a) return;
	CHECK(arena_reserved(a) == (4u << 20));
	char *p1 = arena_lua_alloc(a, NULL, 0, 24);
	char *p2 = arena_lua_alloc(a, NULL, 0, 24);
	CHECK(p1 && p2 && p2 - p1 == 32 && ((uintptr_t)p1 & 15) == 0);
	memcpy(p1, "first", 6);
	CHECK(arena_lua_alloc(a, p2, 24, 0) == NULL);           /* free -> class list */
	CHECK(arena_lua_alloc(a, NULL, 0, 20) == p2);           /* same class, reused */
	/* the last block grows in place */
	char *big = arena_lua_alloc(a, NULL, 0, 1000);
	CHECK(arena_lua_alloc(a, big, 1000, 5000) == big);
	/* a block that is not last moves, keeping its bytes */
	char *mid = arena_lua_alloc(a, NULL, 0, 100);
	memcpy(mid, "move me", 8);
	arena_lua_alloc(a, NULL, 0, 64);
	char *moved = arena_lua_alloc(a, mid, 100, 3000);
	CHECK(moved && moved != mid && strcmp(moved, "move me") == 0);
	CHECK(arena_lua_alloc(a, moved, 3000, 10) == moved);    /* shrinking keeps the block */

	CHECK(arena_snapshot(a) == 0);
	size_t used = arena_used(a);
	uint64_t allocs = arena_allocs(a);
	CHECK(arena_snapshot_size(a) == used);
	char *after1 = arena_lua_alloc(a, NULL, 0, 48);
	memcpy(p1, "SECOND", 7);
	for (int i = 0; i < 1000; i++) arena_lua_alloc(a, NULL, 0, 2048);   /* 2 MB more */
	CHECK(arena_used(a) > used + (1u << 20));
	arena_restore(a);
	CHECK(strcmp(p1, "first") == 0);
	CHECK(arena_used(a) == used && arena_allocs(a) == allocs);
	CHECK(arena_lua_alloc(a, NULL, 0, 48) == after1);       /* same state, same answer */
	/* out of space is a NULL, not a crash */
	CHECK(arena_lua_alloc(a, NULL, 0, 8u << 20) == NULL);
	arena_free(a);
}

int main(void)
{
	setup();
	test_fresh_vm();
	test_hot_path();
	test_names();
	test_module_reload();
	test_syntax_error_recovery();
	test_db();
	test_render();
	test_request_response();
	test_api();
	test_cli();
	test_list_modules();
	test_recycle();
	test_arena_limits();
	test_arena();

	vmpool_shutdown();
	codecache_shutdown();
	db_close(db);
	config_free(&cfg);
	char cmd[600];
	snprintf(cmd, sizeof cmd, "rm -rf '%s'", root);
	if (system(cmd) != 0) fprintf(stderr, "cleanup failed\n");
	return TEST_SUMMARY();
}
