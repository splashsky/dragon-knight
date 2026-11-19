/* db.c :: SQLite connection setup + small per-connection prepared statement cache.
 * A connection (and its cache) belongs to exactly one worker thread. */
#include "bind.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

#define SC_KEY  "dk.stmtcache"
#define SC_SIZE 64

typedef struct {
	char         *sql;
	size_t        len;
	unsigned      hash;
	sqlite3_stmt *st;
	int           busy;
	uint64_t      used;
} sc_ent;

typedef struct {
	sc_ent   e[SC_SIZE];
	int      n;
	uint64_t tick;
} stmt_cache;

sqlite3 *db_open(const char *path, char *err, size_t errlen)
{
	if (mkdir_parents(path) < 0) {
		snprintf(err, errlen, "cannot create directory for %s: %s", path, strerror(errno));
		return NULL;
	}
	sqlite3 *db = NULL;
	int rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
							 SQLITE_OPEN_NOMUTEX, NULL);
	if (rc != SQLITE_OK) {
		snprintf(err, errlen, "cannot open %s: %s", path, db ? sqlite3_errmsg(db) : sqlite3_errstr(rc));
		sqlite3_close(db);
		return NULL;
	}
	sqlite3_busy_timeout(db, 5000);
	char *msg = NULL;
	rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; "
						  "PRAGMA foreign_keys=ON;", NULL, NULL, &msg);
	if (rc != SQLITE_OK) {
		snprintf(err, errlen, "%s: %s", path, msg ? msg : sqlite3_errstr(rc));
		sqlite3_free(msg);
		sqlite3_close(db);
		return NULL;
	}
	stmt_cache *sc = calloc(1, sizeof *sc);
	if (sc) sqlite3_set_clientdata(db, SC_KEY, sc, NULL);
	return db;
}

void db_close(sqlite3 *db)
{
	if (!db) return;
	stmt_cache *sc = sqlite3_get_clientdata(db, SC_KEY);
	if (sc) {
		for (int i = 0; i < sc->n; i++) {
			sqlite3_finalize(sc->e[i].st);
			free(sc->e[i].sql);
		}
		sqlite3_set_clientdata(db, SC_KEY, NULL, NULL);
		free(sc);
	}
	if (sqlite3_close(db) != SQLITE_OK) {
		log_warn("db_close: connection busy, deferring close");
		sqlite3_close_v2(db);
	}
}

static unsigned sql_hash(const char *s, size_t n)
{
	unsigned h = 2166136261u;
	for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)s[i]) * 16777619u;
	return h;
}

int db_prepare(sqlite3 *db, const char *sql, size_t len, sqlite3_stmt **st, const char **tail)
{
	stmt_cache *sc = sqlite3_get_clientdata(db, SC_KEY);
	*st = NULL;
	*tail = sql + len;
	if (!sc) return sqlite3_prepare_v2(db, sql, (int)len, st, tail);
	unsigned h = sql_hash(sql, len);
	for (int i = 0; i < sc->n; i++) {
		sc_ent *e = &sc->e[i];
		if (e->hash == h && e->len == len && !e->busy && memcmp(e->sql, sql, len) == 0) {
			e->busy = 1;
			e->used = ++sc->tick;
			*st = e->st;
			return SQLITE_OK;
		}
	}
	if (len > INT_MAX) return SQLITE_TOOBIG;
	int rc = sqlite3_prepare_v3(db, sql, (int)len, SQLITE_PREPARE_PERSISTENT, st, tail);
	if (rc != SQLITE_OK || !*st || (size_t)(*tail - sql) != len) return rc;

	int slot = -1;
	if (sc->n < SC_SIZE) {
		slot = sc->n;
	} else {
		for (int i = 0; i < sc->n; i++)
			if (!sc->e[i].busy && (slot < 0 || sc->e[i].used < sc->e[slot].used)) slot = i;
		if (slot < 0) return SQLITE_OK;               /* all busy: uncached */
		sqlite3_finalize(sc->e[slot].st);
		free(sc->e[slot].sql);
		sc->e[slot].st = NULL;
		sc->e[slot].sql = NULL;
		sc->e[slot] = sc->e[--sc->n];
		slot = sc->n;
	}
	char *copy = malloc(len + 1);
	if (!copy) return SQLITE_OK;                      /* uncached; still usable */
	memcpy(copy, sql, len);
	copy[len] = '\0';
	sc->e[slot] = (sc_ent){ copy, len, h, *st, 1, ++sc->tick };
	sc->n++;
	return SQLITE_OK;
}

void db_release(sqlite3 *db, sqlite3_stmt *st)
{
	if (!st) return;
	stmt_cache *sc = sqlite3_get_clientdata(db, SC_KEY);
	if (sc) {
		for (int i = 0; i < sc->n; i++) {
			if (sc->e[i].st == st) {
				sqlite3_reset(st);
				sqlite3_clear_bindings(st);
				sc->e[i].busy = 0;
				return;
			}
		}
	}
	sqlite3_finalize(st);
}
