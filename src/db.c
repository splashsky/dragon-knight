/* db.c :: SQLite connection setup + small per-connection prepared statement cache.
 * A connection (and its cache) belongs to exactly one worker thread. */
#include "bind.h"

#include <errno.h>
#include <pthread.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "stats.h"
#include "util.h"

#define SC_KEY  "dk.stmtcache"
#define WAL_RESTART_FRAMES 2000     /* about 8 MiB of 4 KiB pages */
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

/* Short sleeps first: a lock held by another process (dk backup, dk migrate) is usually
 * released within a millisecond; SQLite's default handler starts at 1 ms and grows fast. */
static int busy_handler(void *ud, int n)
{
	(void)ud;
	static const int us[] = { 50, 100, 200, 500, 1000, 2000, 5000, 10000 };
	int nsteps = (int)(sizeof us / sizeof us[0]);
	long total = 0;
	for (int i = 0; i < n && i < nsteps; i++) total += us[i];
	if (n >= nsteps) total += (long)(n - nsteps + 1) * us[nsteps - 1];
	if (total > 5000000L) return 0;         /* give up after about 5 s, as before */
	stat_inc(ST_db_busy_retries);
	struct timespec ts = { 0, (long)us[n < nsteps ? n : nsteps - 1] * 1000L };
	nanosleep(&ts, NULL);
	return 1;
}

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
	sqlite3_busy_handler(db, busy_handler, NULL);
	char *msg = NULL;
	/* Switching a new database to WAL can fail with SQLITE_BUSY without consulting the
	 * busy handler when several workers open it at the same moment: retry for a while. */
	for (int tries = 0;; tries++) {
		rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; "
							  "PRAGMA foreign_keys=ON;", NULL, NULL, &msg);
		if ((rc != SQLITE_BUSY && rc != SQLITE_LOCKED) || tries >= 200) break;
		sqlite3_free(msg);
		msg = NULL;
		sqlite3_sleep(25);
	}
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

int db_tune(sqlite3 *db, const dk_config *cfg, int background_checkpoints)
{
	char sql[256];
	snprintf(sql, sizeof sql,
			 "PRAGMA cache_size=-%d; PRAGMA mmap_size=%llu; PRAGMA temp_store=MEMORY; "
			 "PRAGMA wal_autocheckpoint=%d; PRAGMA journal_size_limit=%d;",
			 cfg->db_cache_kb, (unsigned long long)cfg->db_mmap_bytes,
			 background_checkpoints ? 0 : 1000, 64 << 20);
	return sqlite3_exec(db, sql, NULL, NULL, NULL) == SQLITE_OK ? 0 : -1;
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
			stat_inc(ST_db_stmt_hits);
			return SQLITE_OK;
		}
	}
	if (len > INT_MAX) return SQLITE_TOOBIG;
	stat_inc(ST_db_stmt_prepares);
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

/* ---- background WAL checkpoints ---- */

static struct {
	pthread_mutex_t mu;
	pthread_cond_t  cv;
	pthread_t       th;
	int             running, stop, ms;
	sqlite3        *db;
} CK = { .mu = PTHREAD_MUTEX_INITIALIZER, .cv = PTHREAD_COND_INITIALIZER };

static void *checkpointer_main(void *arg)
{
	(void)arg;
	int last_log = -1, last_ckpt = -1;
	thread_background(5);
	pthread_mutex_lock(&CK.mu);
	while (!CK.stop) {
		struct timespec until;
		clock_gettime(CLOCK_REALTIME, &until);
		until.tv_nsec += (long)(CK.ms % 1000) * 1000000L;
		until.tv_sec += CK.ms / 1000 + until.tv_nsec / 1000000000L;
		until.tv_nsec %= 1000000000L;
		pthread_cond_timedwait(&CK.cv, &CK.mu, &until);
		if (CK.stop) break;
		pthread_mutex_unlock(&CK.mu);
		double t0 = now_mono();
		int nlog = 0, nckpt = 0;
		int rc = sqlite3_wal_checkpoint_v2(CK.db, NULL, SQLITE_CHECKPOINT_PASSIVE, &nlog, &nckpt);
		if (rc == SQLITE_OK && nlog >= WAL_RESTART_FRAMES) {
			/* Writers keep appending during a passive checkpoint, so the WAL is never
			 * completely copied back and never starts over: it grows without end, and
			 * reads get slower. Copy the last few frames while no request writes; the
			 * next transaction then restarts the WAL from its beginning. */
			double t1 = now_mono();
			bind_txn_lock();
			rc = sqlite3_wal_checkpoint_v2(CK.db, NULL, SQLITE_CHECKPOINT_PASSIVE, &nlog, &nckpt);
			bind_txn_unlock();
			uint64_t us = (uint64_t)((now_mono() - t1) * 1e6);
			stat_inc(ST_db_wal_restarts);
			stat_max(ST_db_checkpoint_lock_max_us, us);
		}
		if (rc == SQLITE_OK) {
			atomic_store(&dk_stat[ST_db_wal_frames], (uint64_t)(nlog > 0 ? nlog : 0));
			stat_max(ST_db_wal_frames_max, (uint64_t)(nlog > 0 ? nlog : 0));
		}
		if (rc == SQLITE_OK && (nlog != last_log || nckpt != last_ckpt) && nlog > 0) {
			stat_inc(ST_db_checkpoints);
			stat_add(ST_db_checkpoint_us, (uint64_t)((now_mono() - t0) * 1e6));
		}
		last_log = nlog;
		last_ckpt = nckpt;
		pthread_mutex_lock(&CK.mu);
	}
	pthread_mutex_unlock(&CK.mu);
	return NULL;
}

int db_checkpointer_start(const dk_config *cfg)
{
	if (CK.running || cfg->db_checkpoint_ms <= 0) return 0;
	char err[512];
	CK.db = db_open(cfg->db_path, err, sizeof err);
	if (!CK.db) {
		log_error("checkpointer: %s", err);
		return -1;
	}
	CK.ms = cfg->db_checkpoint_ms;
	CK.stop = 0;
	if (pthread_create(&CK.th, NULL, checkpointer_main, NULL) != 0) {
		db_close(CK.db);
		CK.db = NULL;
		return -1;
	}
	CK.running = 1;
	return 0;
}

void db_checkpointer_stop(void)
{
	if (!CK.running) return;
	pthread_mutex_lock(&CK.mu);
	CK.stop = 1;
	pthread_cond_signal(&CK.cv);
	pthread_mutex_unlock(&CK.mu);
	pthread_join(CK.th, NULL);
	db_close(CK.db);
	CK.db = NULL;
	CK.running = 0;
}
