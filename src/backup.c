/* backup.c :: `dk backup` (see backup.h). Needs no Lua VM: config + SQLite only. */
#include "backup.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "app.h"
#include "sqlite3.h"
#include "util.h"

#define BACKUP_PAGES     1024  /* pages copied per sqlite3_backup_step */
#define BACKUP_SLEEP_MS  25    /* pause after SQLITE_BUSY / SQLITE_LOCKED */
#define BACKUP_MAX_WAITS 1200  /* consecutive busy steps before giving up (~30 s) */

static int path_exists(const char *path)
{
	struct stat st;
	return lstat(path, &st) == 0;
}

static void remove_db_files(const char *path)
{
	static const char *const suffix[] = { "", "-journal", "-wal", "-shm" };
	char buf[PATH_MAX];
	for (size_t i = 0; i < sizeof suffix / sizeof *suffix; i++)
		if (snprintf(buf, sizeof buf, "%s%s", path, suffix[i]) < (int)sizeof buf) unlink(buf);
}

/* fsync the directory holding path, so a completed rename survives a crash */
static void sync_parent_dir(const char *path)
{
	char dir[PATH_MAX];
	if (snprintf(dir, sizeof dir, "%s", path) >= (int)sizeof dir) return;
	char *slash = strrchr(dir, '/');
	if (!slash) snprintf(dir, sizeof dir, ".");
	else if (slash == dir) dir[1] = '\0';
	else *slash = '\0';
	int fd = open(dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (fd < 0) return;
	fsync(fd);
	close(fd);
}

static int copy_pages(sqlite3 *src, sqlite3 *dst, char *err, size_t errlen)
{
	/* An open read transaction pins one snapshot of src for every step, so the copy is
	 * consistent and never restarts because another connection wrote in between. */
	char *msg = NULL;
	if (sqlite3_exec(src, "BEGIN; SELECT count(*) FROM sqlite_schema;", NULL, NULL, &msg) != SQLITE_OK) {
		snprintf(err, errlen, "cannot read the database: %s", msg ? msg : sqlite3_errmsg(src));
		sqlite3_free(msg);
		return -1;
	}
	int ret = -1;
	sqlite3_backup *b = sqlite3_backup_init(dst, "main", src, "main");
	if (!b) {
		snprintf(err, errlen, "backup: %s", sqlite3_errmsg(dst));
	} else {
		int rc, waits = 0;
		for (;;) {
			rc = sqlite3_backup_step(b, BACKUP_PAGES);
			if (rc == SQLITE_OK) {
				waits = 0;
			} else if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
				if (++waits > BACKUP_MAX_WAITS) break;
				sqlite3_sleep(BACKUP_SLEEP_MS);
			} else {
				break;
			}
		}
		int frc = sqlite3_backup_finish(b);
		if (rc == SQLITE_DONE && frc == SQLITE_OK) ret = 0;
		else snprintf(err, errlen, "backup: %s", rc == SQLITE_DONE ? sqlite3_errmsg(dst) : sqlite3_errstr(rc));
	}
	sqlite3_exec(src, "COMMIT", NULL, NULL, NULL);
	return ret;
}

/* Make the copy a self-contained rollback-journal file and check it. */
static int finish_copy(sqlite3 *dst, char *err, size_t errlen)
{
	char *msg = NULL;
	if (sqlite3_exec(dst, "PRAGMA journal_mode=DELETE", NULL, NULL, &msg) != SQLITE_OK) {
		snprintf(err, errlen, "backup: %s", msg ? msg : sqlite3_errmsg(dst));
		sqlite3_free(msg);
		return -1;
	}
	sqlite3_stmt *st = NULL;
	if (sqlite3_prepare_v2(dst, "PRAGMA integrity_check", -1, &st, NULL) != SQLITE_OK) {
		snprintf(err, errlen, "integrity check: %s", sqlite3_errmsg(dst));
		return -1;
	}
	int ret = -1;
	if (sqlite3_step(st) != SQLITE_ROW) {
		snprintf(err, errlen, "integrity check: %s", sqlite3_errmsg(dst));
	} else {
		const char *res = (const char *)sqlite3_column_text(st, 0);
		if (res && !strcmp(res, "ok")) ret = 0;
		else snprintf(err, errlen, "the copy failed the integrity check: %s", res ? res : "(null)");
	}
	sqlite3_finalize(st);
	return ret;
}

int db_backup(const char *src_path, const char *dst_path, char *err, size_t errlen)
{
	char tmp[PATH_MAX];
	if (snprintf(tmp, sizeof tmp, "%s.tmp", dst_path) >= (int)sizeof tmp) {
		snprintf(err, errlen, "%s: path too long", dst_path);
		return -1;
	}
	if (path_exists(dst_path)) {
		snprintf(err, errlen, "%s already exists; not overwriting it", dst_path);
		return -1;
	}
	if (mkdir_parents(dst_path) < 0) {
		snprintf(err, errlen, "cannot create directory for %s: %s", dst_path, strerror(errno));
		return -1;
	}

	sqlite3 *src = NULL, *dst = NULL;
	int ret = -1;
	/* read-write without CREATE: a missing database is an error, never created */
	int rc = sqlite3_open_v2(src_path, &src, SQLITE_OPEN_READWRITE, NULL);
	if (rc != SQLITE_OK) {
		snprintf(err, errlen, "cannot open %s: %s", src_path, src ? sqlite3_errmsg(src) : sqlite3_errstr(rc));
		goto done;
	}
	sqlite3_busy_timeout(src, 5000);

	remove_db_files(tmp);  /* left over from an interrupted backup */
	rc = sqlite3_open_v2(tmp, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
	if (rc != SQLITE_OK) {
		snprintf(err, errlen, "cannot create %s: %s", tmp, dst ? sqlite3_errmsg(dst) : sqlite3_errstr(rc));
		goto done;
	}
	if (copy_pages(src, dst, err, errlen) < 0 || finish_copy(dst, err, errlen) < 0) goto done;
	if (sqlite3_close(dst) != SQLITE_OK) {
		snprintf(err, errlen, "closing %s: %s", tmp, sqlite3_errmsg(dst));
		goto done;
	}
	dst = NULL;
	if (path_exists(dst_path)) {
		snprintf(err, errlen, "%s appeared during the backup; not overwriting it", dst_path);
		goto done;
	}
	if (rename(tmp, dst_path) < 0) {
		snprintf(err, errlen, "cannot rename %s to %s: %s", tmp, dst_path, strerror(errno));
		goto done;
	}
	sync_parent_dir(dst_path);
	ret = 0;
done:
	if (dst) sqlite3_close(dst);
	if (src) sqlite3_close(src);
	if (ret < 0) remove_db_files(tmp);
	return ret;
}

int backup_default_path(const char *db_path, time_t when, char *out, size_t outlen)
{
	char dir[PATH_MAX], name[PATH_MAX], stamp[32];
	const char *slash = strrchr(db_path, '/');
	if (!slash) dir[0] = '\0';
	else if (snprintf(dir, sizeof dir, "%.*s/", (int)(slash - db_path), db_path) >= (int)sizeof dir) return -1;
	if (snprintf(name, sizeof name, "%s", slash ? slash + 1 : db_path) >= (int)sizeof name) return -1;
	size_t len = strlen(name);
	if (len > 3 && !strcmp(name + len - 3, ".db")) name[len - 3] = '\0';
	if (!name[0]) snprintf(name, sizeof name, "dk");

	struct tm tm;
	gmtime_r(&when, &tm);
	strftime(stamp, sizeof stamp, "%Y%m%d-%H%M%S", &tm);
	for (int i = 1; i < 1000; i++) {
		int n = i == 1 ? snprintf(out, outlen, "%sbackups/%s-%s.db", dir, name, stamp)
					   : snprintf(out, outlen, "%sbackups/%s-%s-%d.db", dir, name, stamp, i);
		if (n < 0 || (size_t)n >= outlen) return -1;
		if (!path_exists(out)) return 0;
	}
	return -1;
}

static void backup_usage(FILE *f)
{
	fprintf(f,
			"usage: dk backup [--config PATH] [OUTPUT]\n"
			"\n"
			"\tCopies the database (db_path in the config) to OUTPUT, safely while dk serve is\n"
			"\trunning, checks the copy and prints its path. OUTPUT defaults to\n"
			"\t<db dir>/backups/<db name>-YYYYMMDD-HHMMSS.db (UTC); an existing file is never\n"
			"\toverwritten. Exit status %d if the database does not exist.\n", DK_EXIT_NO_DB);
}

int backup_cli(const dk_config *cfg, int argc, char **argv)
{
	const char *out = NULL;
	for (int i = 0; i < argc; i++) {
		if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			backup_usage(stdout);
			return 0;
		}
		if ((argv[i][0] == '-' && argv[i][1]) || out) {
			fprintf(stderr, "dk backup: unexpected argument: %s\n\n", argv[i]);
			backup_usage(stderr);
			return 2;
		}
		out = argv[i];
	}

	struct stat st;
	if (stat(cfg->db_path, &st) < 0) {
		if (errno == ENOENT) {
			fprintf(stderr, "dk backup: no database at %s (nothing to back up; run dk install first)\n",
					cfg->db_path);
			return DK_EXIT_NO_DB;
		}
		fprintf(stderr, "dk backup: %s: %s\n", cfg->db_path, strerror(errno));
		return 1;
	}
	if (!S_ISREG(st.st_mode)) {
		fprintf(stderr, "dk backup: %s is not a regular file\n", cfg->db_path);
		return 1;
	}

	char path[PATH_MAX], err[1024];
	if (!out) {
		if (backup_default_path(cfg->db_path, time(NULL), path, sizeof path) < 0) {
			fprintf(stderr, "dk backup: cannot choose a backup file name for %s\n", cfg->db_path);
			return 1;
		}
		out = path;
	}
	if (db_backup(cfg->db_path, out, err, sizeof err) < 0) {
		fprintf(stderr, "dk backup: %s\n", err);
		return 1;
	}
	printf("%s\n", out);
	return 0;
}
