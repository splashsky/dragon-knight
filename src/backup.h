/* backup.h :: `dk backup`: an online, consistent copy of the database (SQLite backup API). */
#ifndef DK_BACKUP_H
#define DK_BACKUP_H

#include <stddef.h>
#include <time.h>

#include "config.h"

/* Copy the database at src to dst, safe while a server is writing to it: the copy is
 * made from one read transaction (a consistent snapshot; in WAL mode writers carry on),
 * written to "<dst>.tmp", checked with PRAGMA integrity_check and renamed to dst.
 * Never creates src and never overwrites dst. 0 ok; -1 with a message in err. */
int db_backup(const char *src, const char *dst, char *err, size_t errlen);

/* Default backup file for db_path: <dir>/backups/<name without .db>-YYYYMMDD-HHMMSS.db
 * (UTC), with -2, -3, ... appended if that file exists. 0 ok; -1 if it doesn't fit. */
int backup_default_path(const char *db_path, time_t when, char *out, size_t outlen);

/* `dk backup [OUTPUT]`: prints the path written. Returns the exit status. */
int backup_cli(const dk_config *cfg, int argc, char **argv);

#endif
