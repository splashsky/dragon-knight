/* tmpl.c :: template -> Lua source compiler (see PLAN.md "Template language").
 *
 * Generated chunk layout (template line N == Lua line N):
 *   line 1: prelude (captures table.concat/tostring/setmetatable, returns the render
 *           function, installs the ctx/h _ENV proxy) followed by line 1's content
 *   ...     literal text -> `__n = __n + 1; __o[__n] = "<escaped>"` + one real newline per
 *           template newline it (or trimmed whitespace) contained
 *   last:   ` return __tc(__o) end`
 *
 * Tag bodies are scanned with a small Lua lexer so close markers inside Lua strings,
 * long brackets, comments and table constructors don't end the tag early. A trailing
 * `-- line comment` in a tag is rewritten into a long comment so it can't swallow the
 * code generated after it on the same line. */
#include "tmpl.h"

#include <stdio.h>
#include <string.h>

#define NONE ((size_t)-1)

static const char PRELUDE[] =
    "local __tc, __ts, __sm = table.concat, tostring, setmetatable; "
    "local function __r(v) if v == nil then return \"\" end return __ts(v) end; "
    "return function(__ctx, __h) "
    "__ctx = __ctx or {}; __h = __h or {}; "
    "local __e = __h.escape; "
    "local __o, __n = {}, 0; "
    "local _ENV = __sm({}, {__index = function(_, k) "
    "local v = __ctx[k]; if v == nil then v = __h[k] end; return v end}); ";

static const char EPILOGUE[] = " return __tc(__o) end\n";

typedef struct {
    const char *s;
    size_t      n;
    sbuf       *out;
    int         oom;
} cstate;

static void put(cstate *cs, const char *p, size_t n)
{
    if (!cs->oom && sb_append(cs->out, p, n) < 0) cs->oom = 1;
}

static void puts_(cstate *cs, const char *p) { put(cs, p, strlen(p)); }

static size_t count_nl(const char *s, size_t from, size_t to)
{
    size_t k = 0;
    for (size_t i = from; i < to; i++) k += s[i] == '\n';
    return k;
}

static void put_newlines(cstate *cs, size_t k)
{
    while (k--) put(cs, "\n", 1);
}

/* Literal text as a quoted Lua string; newlines are escaped (caller emits real ones). */
static void emit_literal(cstate *cs, size_t from, size_t to)
{
    if (from >= to) return;
    puts_(cs, "__n = __n + 1; __o[__n] = \"");
    size_t run = from;
    for (size_t i = from; i < to; i++) {
        unsigned char c = (unsigned char)cs->s[i];
        const char *esc = NULL;
        char num[5];
        if (c == '"') esc = "\\\"";
        else if (c == '\\') esc = "\\\\";
        else if (c == '\n') esc = "\\n";
        else if (c == '\r') esc = "\\r";
        else if (c == '\t') esc = "\\t";
        else if (c < 0x20 || c == 0x7f) {
            snprintf(num, sizeof num, "\\%03u", (unsigned)c);
            esc = num;
        }
        if (esc) {
            put(cs, cs->s + run, i - run);
            puts_(cs, esc);
            run = i + 1;
        }
    }
    put(cs, cs->s + run, to - run);
    puts_(cs, "\"; ");
}

/* Copy Lua code verbatim, except that a lone CR (which Lua counts as a line break but
 * we don't) becomes a space so line numbers stay aligned. */
static void put_code(cstate *cs, size_t from, size_t to)
{
    size_t run = from;
    for (size_t i = from; i < to; i++) {
        if (cs->s[i] == '\r' && !(i + 1 < to && cs->s[i + 1] == '\n')) {
            put(cs, cs->s + run, i - run);
            put(cs, " ", 1);
            run = i + 1;
        }
    }
    put(cs, cs->s + run, to - run);
}

/* Does s[from,to) contain "]" + level*"=" + "]"? */
static int has_closer(const char *s, size_t from, size_t to, size_t level)
{
    for (size_t i = from; i + level + 2 <= to; i++) {
        if (s[i] != ']') continue;
        size_t j = i + 1;
        while (j < i + 1 + level && s[j] == '=') j++;
        if (j == i + 1 + level && s[j] == ']') return 1;
    }
    return 0;
}

/* Emit tag code [from,to); if lcomment != NONE, the code ends in a line comment starting
 * at lcomment ("--"), which is turned into a long comment. */
static void emit_code(cstate *cs, size_t from, size_t to, size_t lcomment)
{
    if (lcomment == NONE) {
        put_code(cs, from, to);
        return;
    }
    size_t body = lcomment + 2, level = 0;
    while (has_closer(cs->s, body, to, level)) level++;
    put_code(cs, from, body);
    put(cs, "[", 1);
    for (size_t i = 0; i < level; i++) put(cs, "=", 1);
    put(cs, "[", 1);
    put_code(cs, body, to);
    put(cs, " ]", 2);
    for (size_t i = 0; i < level; i++) put(cs, "=", 1);
    put(cs, "]", 1);
}

/* If s[i] opens a long bracket "[==[", return the index just after it and set *level. */
static size_t long_open(const char *s, size_t n, size_t i, size_t *level)
{
    if (i >= n || s[i] != '[') return 0;
    size_t j = i + 1;
    while (j < n && s[j] == '=') j++;
    if (j >= n || s[j] != '[') return 0;
    *level = j - i - 1;
    return j + 1;
}

/* Index just past the matching long-bracket closer, or n if unterminated. */
static size_t skip_long(const char *s, size_t n, size_t i, size_t level)
{
    for (; i + level + 2 <= n; i++) {
        if (s[i] != ']') continue;
        size_t j = i + 1;
        while (j < i + 1 + level && s[j] == '=') j++;
        if (j == i + 1 + level && s[j] == ']') return j + 1;
    }
    return n;
}

/* Index just past a short string starting at quote s[i]; stops at a newline (Lua will
 * report the error), n if unterminated. */
static size_t skip_short(const char *s, size_t n, size_t i)
{
    char q = s[i];
    for (size_t j = i + 1; j < n; j++) {
        if (s[j] == '\\') {
            if (++j >= n) return n;
        } else if (s[j] == q) {
            return j + 1;
        } else if (s[j] == '\n') {
            return j;
        }
    }
    return n;
}

/* Scan Lua code from i for the close marker at brace depth 0 (when braces) and outside
 * strings/comments. On success: *end = index of the close marker (or of its '-' trim
 * prefix), *trim set, *lcomment = start of a trailing line comment or NONE. */
static int scan_code(const char *s, size_t n, size_t i, const char *close, int braces,
                     size_t *end, int *trim, size_t *lcomment)
{
    size_t cl = strlen(close);
    int depth = 0;
    *lcomment = NONE;
    while (i < n) {
        char c = s[i];
        if (depth == 0) {
            if (c == '-' && i + 1 + cl <= n && memcmp(s + i + 1, close, cl) == 0) {
                *end = i;
                *trim = 1;
                return 0;
            }
            if (i + cl <= n && memcmp(s + i, close, cl) == 0) {
                *end = i;
                *trim = 0;
                return 0;
            }
        }
        if (*lcomment != NONE) {
            if (c == '\n') *lcomment = NONE;
            i++;
            continue;
        }
        size_t level, j;
        switch (c) {
        case '"':
        case '\'':
            i = skip_short(s, n, i);
            continue;
        case '[':
            if ((j = long_open(s, n, i, &level)) != 0) {
                i = skip_long(s, n, j, level);
                continue;
            }
            break;
        case '-':
            if (i + 1 < n && s[i + 1] == '-') {
                if ((j = long_open(s, n, i + 2, &level)) != 0) {
                    i = skip_long(s, n, j, level);
                } else {
                    *lcomment = i;
                    i += 2;
                }
                continue;
            }
            break;
        case '{':
            if (braces) depth++;
            break;
        case '}':
            if (braces && depth > 0) depth--;
            break;
        default:
            break;
        }
        i++;
    }
    return -1;
}

static int only_space(const char *s, size_t from, size_t to)
{
    for (size_t i = from; i < to; i++)
        if (s[i] != ' ' && s[i] != '\t' && s[i] != '\r' && s[i] != '\n') return 0;
    return 1;
}

/* Next "{{", "{%" or "{#" at or after i; n if none. */
static size_t find_open(const char *s, size_t n, size_t i)
{
    while (i + 1 < n) {
        const char *p = memchr(s + i, '{', n - i - 1);
        if (!p) return n;
        i = (size_t)(p - s);
        char c = s[i + 1];
        if (c == '{' || c == '%' || c == '#') return i;
        i++;
    }
    return n;
}

/* End of the literal before a '{X-' tag: strip trailing spaces/tabs and one preceding
 * newline (LF or CRLF), only if that run is pure whitespace. If the literal is all
 * spaces/tabs (tag-adjacent or at file start) it is stripped entirely. */
static size_t ltrim_end(const char *s, size_t from, size_t to)
{
    size_t j = to;
    while (j > from && (s[j - 1] == ' ' || s[j - 1] == '\t')) j--;
    if (j == from) return j;
    if (s[j - 1] != '\n') return to;
    j--;
    if (j > from && s[j - 1] == '\r') j--;
    return j;
}

/* Start of the literal after a '-X}' tag: skip spaces/tabs and one newline. */
static size_t rtrim_start(const char *s, size_t n, size_t i)
{
    while (i < n && (s[i] == ' ' || s[i] == '\t')) i++;
    if (i < n && s[i] == '\n') return i + 1;
    if (i + 1 < n && s[i] == '\r' && s[i + 1] == '\n') return i + 2;
    return i;
}

enum { T_ESC, T_RAW, T_CODE, T_COMMENT };

int tmpl_compile(const char *src, size_t len, const char *name,
                 sbuf *out, char *err, size_t errlen)
{
    cstate cs = { src, len, out, 0 };
    size_t start_len = out->len;
    size_t pos = 0;      /* end of previous tag (newline accounting starts here) */
    size_t text = 0;     /* start of literal text (after right-trim) */
    size_t line = 1;
    const char *fail = NULL;
    size_t fail_line = 0;

    if (!name) name = "?";
    if (err && errlen) err[0] = '\0';
    puts_(&cs, PRELUDE);

    for (;;) {
        size_t open = find_open(src, len, text);
        size_t olen = 2;
        int kind;
        const char *close = NULL;
        if (open < len) {
            char c = src[open + 1];
            if (c == '{' && open + 2 < len && src[open + 2] == '{') {
                kind = T_RAW; olen = 3; close = "}}}";
            } else if (c == '{') {
                kind = T_ESC; close = "}}";
            } else if (c == '%') {
                kind = T_CODE; close = "%}";
            } else {
                kind = T_COMMENT; close = "#}";
            }
        } else {
            kind = T_COMMENT;
        }
        int ltrim = open < len && open + olen < len && src[open + olen] == '-';

        emit_literal(&cs, text, ltrim ? ltrim_end(src, text, open) : open);
        size_t nl = count_nl(src, pos, open);
        put_newlines(&cs, nl);
        line += nl;
        if (open >= len) break;

        size_t body = open + olen + (size_t)ltrim, end = 0, lcomment = NONE;
        int rtrim = 0;
        if (kind == T_COMMENT) {
            const char *p = NULL;
            for (size_t i = body; i + 1 < len; i++)
                if (src[i] == '#' && src[i + 1] == '}') { p = src + i; break; }
            if (!p) { fail = "unterminated '{#' comment"; fail_line = line; break; }
            end = (size_t)(p - src);
            if (end > body && src[end - 1] == '-') { end--; rtrim = 1; }
        } else if (scan_code(src, len, body, close, kind != T_CODE, &end, &rtrim, &lcomment) < 0) {
            fail = kind == T_RAW ? "unterminated '{{{' tag"
                 : kind == T_ESC ? "unterminated '{{' tag" : "unterminated '{%' tag";
            fail_line = line;
            break;
        }
        size_t tag_end = end + (size_t)rtrim + strlen(close);

        switch (kind) {
        case T_ESC:
        case T_RAW:
            if (only_space(src, body, end)) {
                fail = kind == T_RAW ? "empty expression in '{{{' tag" : "empty expression in '{{' tag";
                fail_line = line;
                break;
            }
            puts_(&cs, kind == T_RAW ? "__n = __n + 1; __o[__n] = __r((" : "__n = __n + 1; __o[__n] = __e((");
            emit_code(&cs, body, end, lcomment);
            puts_(&cs, ")); ");
            break;
        case T_CODE:
            emit_code(&cs, body, end, lcomment);
            puts_(&cs, "; ");
            break;
        default:
            put_newlines(&cs, count_nl(src, body, end));
            break;
        }
        if (fail) break;
        line += count_nl(src, open, tag_end);
        pos = tag_end;
        text = rtrim ? rtrim_start(src, len, tag_end) : tag_end;
    }

    if (!fail) puts_(&cs, EPILOGUE);
    if (fail || cs.oom) {
        if (cs.oom && !fail) { fail = "out of memory"; fail_line = line; }
        if (err && errlen) snprintf(err, errlen, "%s:%zu: %s", name, fail_line, fail);
        out->len = start_len;
        if (out->p) out->p[start_len] = '\0';
        return -1;
    }
    return 0;
}
