/* app.h :: process lifecycle glue between config, codecache, vmpool, http and bind. */
#ifndef DK_APP_H
#define DK_APP_H

#include "config.h"

/* Exit status of `dk migrate`, `dk user` and `dk backup` when the database file does not
 * exist (they never create it; `dk install` does). */
#define DK_EXIT_NO_DB 3

/* codecache + watcher + vmpool + HTTP server; returns when the server stops. 0 ok. */
int app_serve(const dk_config *cfg);

/* Run require(module).run(argv...) in one VM + DB transaction. Returns exit code. */
int app_cli(const dk_config *cfg, const char *module, int argc, char **argv);

/* Build a VM (require "main") and compile every module/template; print failures.
 * Returns 0 if everything compiled. */
int app_check(const dk_config *cfg);

#endif
