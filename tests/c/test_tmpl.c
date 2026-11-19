/* test_tmpl.c :: compile templates -> load in Lua -> render, check output and line mapping. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "tmpl.h"
#include "minitest.h"

static lua_State *L;
static char   result[65536];
static size_t result_len;

static const char HELPERS[] =
    "local map = {['&']='&amp;', ['<']='&lt;', ['>']='&gt;', ['\"']='&quot;', [\"'\"]='&#39;'}\n"
    "H = setmetatable({\n"
    "  escape = function(v) if v == nil then return '' end\n"
    "    return (tostring(v):gsub('[&<>\"\\']', map)) end,\n"
    "  upper = string.upper,\n"
    "}, {__index = _G})\n";

static const char *setres(const char *prefix, const char *s, size_t n)
{
    size_t pl = strlen(prefix);
    if (pl + n >= sizeof result) n = sizeof result - pl - 1;
    memcpy(result, prefix, pl);
    memcpy(result + pl, s, n);
    result_len = pl + n;
    result[result_len] = '\0';
    return result;
}

/* Renders tpl (len bytes) with ctx = (Lua expression ctx_src). Returns the output, or
 * "COMPILE: ...", "LOAD: ...", "ERR: ..." on failure. ctx is left in global CTX. */
static const char *render_n(const char *tpl, size_t len, const char *ctx_src)
{
    sbuf b;
    char err[256];
    sb_init(&b);
    lua_settop(L, 0);
    if (tmpl_compile(tpl, len, "t", &b, err, sizeof err) < 0) {
        sb_free(&b);
        return setres("COMPILE: ", err, strlen(err));
    }
    if (luaL_loadbuffer(L, b.p, b.len, "@t.html") != LUA_OK) {
        size_t n;
        const char *m = lua_tolstring(L, -1, &n);
        sb_free(&b);
        return setres("LOAD: ", m, n);
    }
    sb_free(&b);
    if (lua_pcall(L, 0, 1, 0) != LUA_OK || !lua_isfunction(L, -1))
        return setres("CHUNK: ", "", 0);

    char code[1024];
    snprintf(code, sizeof code, "CTX = (%s) return CTX", ctx_src ? ctx_src : "{}");
    if (luaL_dostring(L, code) != LUA_OK) return setres("CTX: ", lua_tostring(L, -1), strlen(lua_tostring(L, -1)));
    lua_getglobal(L, "H");
    size_t n;
    if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
        const char *m = lua_tolstring(L, -1, &n);
        return setres("ERR: ", m ? m : "?", m ? n : 1);
    }
    const char *s = lua_tolstring(L, -1, &n);
    if (!s) return setres("NOTSTRING", "", 0);
    return setres("", s, n);
}

static const char *render(const char *tpl, const char *ctx_src)
{
    return render_n(tpl, strlen(tpl), ctx_src);
}

static int lua_true(const char *expr)
{
    char code[512];
    snprintf(code, sizeof code, "return %s", expr);
    if (luaL_dostring(L, code) != LUA_OK) return 0;
    int r = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return r;
}

static void test_output(void)
{
    CHECK_STR_EQ(render("Hello {{ name }}!", "{name = '<b>\"Tom\" & \\'J\\'</b>'}"),
                 "Hello &lt;b&gt;&quot;Tom&quot; &amp; &#39;J&#39;&lt;/b&gt;!");
    CHECK_STR_EQ(render("{{{ html }}}|{{{ missing }}}|{{ missing }}|{{{ 42 }}}|{{ 1.5 }}|{{{ true }}}",
                        "{html = '<i>x</i>'}"),
                 "<i>x</i>|||42|1.5|true");
    CHECK_STR_EQ(render("no tags at all", NULL), "no tags at all");
    CHECK_STR_EQ(render("", NULL), "");
    CHECK_STR_EQ(render("{{ a }}{{ b }}{{{ a }}}", "{a = 1, b = 2}"), "121");
    /* Multiple return values are truncated to one. */
    CHECK_STR_EQ(render("{{{ f() }}}{{ f() }}", "{f = function() return 'a', 'b' end}"), "aa");
    /* Lone braces in text and braces in expressions. */
    CHECK_STR_EQ(render("a { b } {{ '{' }} }} %} #} c{", NULL), "a { b } { }} %} #} c{");
}

static void test_control(void)
{
    const char *t = "{% if n > 1 then %}many{% elseif n == 1 then %}one{% else %}none{% end %}";
    CHECK_STR_EQ(render(t, "{n = 2}"), "many");
    CHECK_STR_EQ(render(t, "{n = 1}"), "one");
    CHECK_STR_EQ(render(t, "{n = 0}"), "none");
    CHECK_STR_EQ(render("{% for i, v in ipairs(items) do %}[{{ i }}={{ v }}]{% end %}",
                        "{items = {'a', '<'}}"),
                 "[1=a][2=&lt;]");
    CHECK_STR_EQ(render("{% local n = #items %}{{ n }}:{% for i = 1, n do %}{{ items[i] }}{% end %}",
                        "{items = {3, 4}}"),
                 "2:34");
    CHECK_STR_EQ(render("{%\n  local function sq(x)\n    return x * x\n  end\n%}{{ sq(7) }}", NULL), "49");
    CHECK_STR_EQ(render("{% %}x", NULL), "x");
}

static void test_names(void)
{
    /* Helpers and globals via h; ctx shadows h. */
    CHECK_STR_EQ(render("{{ upper('x') }}{{ string.format('%03d', 7) }}", NULL), "X007");
    CHECK_STR_EQ(render("{{ upper }}", "{upper = 'u'}"), "u");
    /* Scratch assignment: lands in a template-local table, ctx untouched. */
    CHECK_STR_EQ(render("{% name = 'x' %}{{ name }}", "{name = 'y'}"), "x");
    CHECK(lua_true("CTX.name == 'y'"));
    CHECK_STR_EQ(render("{% total = 0 %}{% for _, v in ipairs(xs) do total = total + v end %}{{ total }}",
                        "{xs = {1, 2, 3}}"),
                 "6");
    CHECK(lua_true("CTX.total == nil and rawget(_G, 'total') == nil and H.total == nil"));
    CHECK_STR_EQ(render("{% local a = 5 %}{{ a * 2 }}", NULL), "10");
    /* ctx/h parameter names don't shadow ctx keys. */
    CHECK_STR_EQ(render("{{ h }}{{ ctx }}", "{h = 'H', ctx = 'C'}"), "HC");
    /* false in ctx is not replaced by h. */
    CHECK_STR_EQ(render("{{{ upper }}}", "{upper = false}"), "false");
}

static void test_comments(void)
{
    CHECK_STR_EQ(render("a{# hidden {{ x }} {% y %}\n multi\n #}b", NULL), "ab");
    CHECK_STR_EQ(render("a{##}b{# # } #}c", NULL), "abc");
}

static void test_trim(void)
{
    CHECK_STR_EQ(render("<ul>\n  {%- for _, v in ipairs(xs) do %}\n  <li>{{ v }}</li>\n  {%- end %}\n</ul>",
                        "{xs = {1, 2}}"),
                 "<ul>\n  <li>1</li>\n  <li>2</li>\n</ul>");
    CHECK_STR_EQ(render("{% if true then -%}\n  x\n{% end -%}  \ny", NULL), "  x\ny");
    CHECK_STR_EQ(render("a\n  {{- v -}}  \nb", "{v = 'V'}"), "aVb");
    CHECK_STR_EQ(render("a  \n {{{- v -}}}\t\r\nb", "{v = '<'}"), "a  <b");
    /* Only one newline is consumed on either side. */
    CHECK_STR_EQ(render("a\n\n{{- v -}}\n\nb", "{v = 'V'}"), "a\nV\nb");
    /* Non-whitespace before the tag on the same line: no left trim. */
    CHECK_STR_EQ(render("ab {%- if true then %}c{% end %}", NULL), "ab c");
    /* Whitespace back to file start / previous tag is removed. */
    CHECK_STR_EQ(render("  {%- if true then %}x{% end %}", NULL), "x");
    CHECK_STR_EQ(render("{{ 1 }}  {{- 2 }}", NULL), "12");
    /* Right trim without a following newline only eats spaces/tabs. */
    CHECK_STR_EQ(render("{{ 1 -}} \t x", NULL), "1x");
    /* Comments trim too. */
    CHECK_STR_EQ(render("a\n{#- c -#}\nb", NULL), "ab");
    /* CRLF newlines are trimmed as a unit. */
    CHECK_STR_EQ(render("a\r\n  {%- if true then -%}\r\nb{% end %}", NULL), "ab");
    /* Trim marker vs. minus/comment inside the expression. */
    CHECK_STR_EQ(render("{{ 5 - -1 }}|{{ 5 - 1 -}} |{{ 3 --}}", NULL), "6|4|3");
}

static void test_literal_robustness(void)
{
    const char *t = "a]]b]=]c]==]\\d\"e'f\x01g\th\xc3\xa9\x7f\\n[[x]]";
    CHECK_STR_EQ(render(t, NULL), t);
    CHECK_STR_EQ(render("\\{{ s }}\\", "{s = '\\\\'}"), "\\\\\\");
    CHECK_STR_EQ(render("\"{{ q }}\"", "{q = '\"'}"), "\"&quot;\"");

    /* Embedded NUL survives. */
    const char nul[] = "a\0b{{ 1 }}";
    render_n(nul, sizeof nul - 1, NULL);
    CHECK(result_len == 4 && memcmp(result, "a\0b1", 4) == 0);

    /* CRLF and lone CR are preserved in output. */
    CHECK_STR_EQ(render("line1\r\n{% if x then %}\r\nyes\r\n{% end %}\r\nend\rx", "{x = true}"),
                 "line1\r\n\r\nyes\r\n\r\nend\rx");
}

static void test_close_markers_in_code(void)
{
    CHECK_STR_EQ(render("{{ \"}}\" }}|{{{ '}}}' }}}|{% local s = \"%}\" %}{{ s }}", NULL), "}}|}}}|%}");
    CHECK_STR_EQ(render("{{ 'a\\'}}' }}", NULL), "a&#39;}}");
    CHECK_STR_EQ(render("{{ #{1, 2, 3} }}|{{ ({a = {b = 1}}).a.b }}|{{{ ({x = {}}).x and 'ok' }}}", NULL),
                 "3|1|ok");
    CHECK_STR_EQ(render("{{{ [[a]] .. [==[]]}}]==] }}}", NULL), "a]]}}");
    /* Lua comments inside tags, including a trailing line comment. */
    CHECK_STR_EQ(render("{% local x = 1 -- set x %}{{ x }}", NULL), "1");
    CHECK_STR_EQ(render("{{ x -- comment ]] ]=] %} }}", "{x = 2}"), "2");
    CHECK_STR_EQ(render("{{ x --[[ }} ]] }}", "{x = 3}"), "3");
    CHECK_STR_EQ(render("{% -- just a comment -%}\nz", NULL), "z");
    CHECK_STR_EQ(render("{% local y = 1 -- c\n y = y + 1 -- d ]] %}{{ y }}", NULL), "2");
}

static void test_many_tags(void)
{
    sbuf t;
    sb_init(&t);
    for (int i = 0; i < 600; i++) CHECK(sb_puts(&t, "{{ v }}{{{ v }}}{% q = v %}.") == 0);
    render_n(t.p, t.len, "{v = 'x'}");
    CHECK(result_len == 600 * 3);
    CHECK(strncmp(result, "xx.xx.", 6) == 0);
    sb_free(&t);
}

static void test_line_mapping(void)
{
    /* Generated source has exactly the template's line count (+1 for the epilogue line). */
    const char *t = "a\n{# x\ny #}\n{%\nlocal z = 1\n%}\n  {%- if true -%}\n{{ 'q'\n }}\nlast";
    sbuf b;
    char err[128];
    sb_init(&b);
    CHECK(tmpl_compile(t, strlen(t), "t", &b, err, sizeof err) == 0);
    size_t tl = 0, gl = 0;
    for (const char *p = t; *p; p++) tl += *p == '\n';
    for (size_t i = 0; i < b.len; i++) gl += b.p[i] == '\n';
    CHECK(gl == tl + 1);
    sb_free(&b);

    CHECK(strstr(render("1\n2\n3\n4\n5\n6\n{{ nope.field }}", NULL), "t.html:7:") != NULL);
    CHECK(strstr(render("a\n{#\n\n#}\n{%\nlocal x = 1\n%}\nb {{ x }}\n\n{{ x.y }}", NULL), "t.html:10:") != NULL);
    CHECK(strstr(render("{% local t = nil\nlocal y = t.x %}", NULL), "t.html:2:") != NULL);
    CHECK(strstr(render("a\n  {%- if true then -%}\n\n{{ nil .. 'x' }}{% end %}", NULL), "t.html:4:") != NULL);
    CHECK(strstr(render("a\r\nb\r\n{{ nil + 1 }}", NULL), "t.html:3:") != NULL);
    CHECK(strstr(render("a\rb\n{{ 'x' .. '\r' }}\n{{ nil + 1 }}", NULL), "t.html:3:") != NULL);
    CHECK(strstr(render("{{ 'a' -- c\r }}\n\n{{ nil + 1 }}", NULL), "t.html:3:") != NULL);
    CHECK(strstr(render("x {{ 1 }} {{{ 2 }}}\n{% for i = 1, 2 do %}\n{{ i }}\n{% end %}\n{{ error('boom') }}", NULL),
                 "t.html:5: boom") != NULL);
    /* Lua syntax errors are reported by the loader at the right line. */
    const char *r = render("a\n\n{% if then %}", NULL);
    CHECK(strncmp(r, "LOAD: ", 6) == 0 && strstr(r, "t.html:3:") != NULL);
    r = render("a\n{{ 1 + }}\n", NULL);
    CHECK(strncmp(r, "LOAD: ", 6) == 0 && strstr(r, "t.html:2:") != NULL);
}

static void test_syntax_errors(void)
{
    CHECK_STR_EQ(render("a\nb {{ x", NULL), "COMPILE: t:2: unterminated '{{' tag");
    CHECK_STR_EQ(render("{% x", NULL), "COMPILE: t:1: unterminated '{%' tag");
    CHECK_STR_EQ(render("x\n\n{# abc\n", NULL), "COMPILE: t:3: unterminated '{#' comment");
    CHECK_STR_EQ(render("{{{ x }}", NULL), "COMPILE: t:1: unterminated '{{{' tag");
    CHECK_STR_EQ(render("{{ 'abc }}", NULL), "COMPILE: t:1: unterminated '{{' tag");
    CHECK_STR_EQ(render("ok\n{{ [[ }}", NULL), "COMPILE: t:2: unterminated '{{' tag");
    CHECK_STR_EQ(render("{{ {1} }", NULL), "COMPILE: t:1: unterminated '{{' tag");
    CHECK_STR_EQ(render("\n{{  }}", NULL), "COMPILE: t:2: empty expression in '{{' tag");
    CHECK_STR_EQ(render("{{{-\n-}}}", NULL), "COMPILE: t:1: empty expression in '{{{' tag");

    /* On error the output buffer is restored; tiny err buffers are fine. */
    sbuf b;
    char err[8];
    sb_init(&b);
    CHECK(sb_puts(&b, "keep") == 0);
    CHECK(tmpl_compile("{{ x", 4, "name", &b, err, sizeof err) == -1);
    CHECK_STR_EQ(b.p, "keep");
    CHECK_STR_EQ(err, "name:1:");
    CHECK(tmpl_compile("{{ x }}", 7, "name", &b, NULL, 0) == 0);
    CHECK(strncmp(b.p, "keeplocal ", 10) == 0);
    sb_free(&b);
}

/* Random tag-heavy input: must never crash; on success the generated code has the same
 * number of lines and the Lua loader must not report errors beyond the template's lines. */
static void test_fuzz(void)
{
    static const char alphabet[] = "{}%#-'\"[]=\n\r xv\\;()";
    uint32_t seed = 12345;
    char t[64];
    int bad_lines = 0, bad_mapping = 0;
    for (int iter = 0; iter < 20000; iter++) {
        size_t n = (size_t)(iter % 63) + 1;
        for (size_t i = 0; i < n; i++) {
            seed = seed * 1103515245u + 12345u;
            t[i] = alphabet[(seed >> 16) % (sizeof alphabet - 1)];
        }
        sbuf b;
        char err[128];
        sb_init(&b);
        if (tmpl_compile(t, n, "f", &b, err, sizeof err) == 0) {
            size_t tl = 0, gl = 0;
            for (size_t i = 0; i < n; i++) tl += t[i] == '\n';
            for (size_t i = 0; i < b.len; i++) gl += b.p[i] == '\n';
            bad_lines += gl != tl + 1;
            if (luaL_loadbuffer(L, b.p, b.len, "=f") != LUA_OK) {
                const char *m = lua_tostring(L, -1);
                unsigned long ln = 0;
                if (m && sscanf(m, "f:%lu:", &ln) == 1 && ln > tl + 1) bad_mapping++;
            }
            lua_settop(L, 0);
        } else {
            bad_lines += strncmp(err, "f:", 2) != 0;
        }
        sb_free(&b);
    }
    CHECK(bad_lines == 0);
    CHECK(bad_mapping == 0);
}

int main(void)
{
    L = luaL_newstate();
    if (!L) return 1;
    luaL_openlibs(L);
    if (luaL_dostring(L, HELPERS) != LUA_OK) {
        fprintf(stderr, "helpers: %s\n", lua_tostring(L, -1));
        return 1;
    }
    test_output();
    test_control();
    test_names();
    test_comments();
    test_trim();
    test_literal_robustness();
    test_close_markers_in_code();
    test_many_tags();
    test_line_mapping();
    test_syntax_errors();
    test_fuzz();
    lua_close(L);
    return TEST_SUMMARY();
}
