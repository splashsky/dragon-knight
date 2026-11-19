/* app.c :: dk_hooks implementation and process lifecycle (see app.h). */
#include "app.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bind.h"
#include "codecache.h"
#include "http.h"
#include "stats.h"
#include "util.h"
#include "vmpool.h"

typedef struct {
	int      id;
	sqlite3 *db;
	dk_vm   *vm;       /* used by the current request; released in app_after */
} worker_ctx;

static void *app_worker_init(int worker_id, void *ud)
{
	const dk_config *cfg = ud;
	worker_ctx *w = calloc(1, sizeof *w);
	if (!w) return NULL;
	w->id = worker_id;
	char err[512];
	w->db = db_open(cfg->db_path, err, sizeof err);
	if (!w->db) log_error("worker %d: %s", worker_id, err);
	else db_tune(w->db, cfg, cfg->db_checkpoint_ms > 0);
	return w;
}

static void app_worker_fini(void *wctx, void *ud)
{
	(void)ud;
	worker_ctx *w = wctx;
	if (!w) return;
	db_close(w->db);
	free(w);
}

static void app_handle(void *wctx, const dk_request *req, dk_response *resp, void *ud)
{
	const dk_config *cfg = ud;
	worker_ctx *w = wctx;
	if (!w || !w->db) {
		bind_error_page(resp, cfg, 503, "database unavailable (see server log)");
		return;
	}
	char err[4096];
	dk_vm *vm = vmpool_acquire(err, sizeof err);
	if (!vm) {
		log_error("%s %s -> 500: cannot build VM\n%s", req->method, req->target, err);
		bind_error_page(resp, cfg, 500, err);
		return;
	}
	bind_handle(vm_state(vm), cfg, w->db, req, resp);
	w->vm = vm;
}

static void app_after(void *wctx, void *ud)
{
	(void)ud;
	worker_ctx *w = wctx;
	if (w && w->vm) {
		vmpool_release(w->vm);
		w->vm = NULL;
	}
}

int app_serve(const dk_config *cfg)
{
	if (codecache_init(cfg) < 0) {
		log_error("codecache_init failed");
		return 1;
	}
	if (codecache_watch_start(vmpool_on_change, NULL) < 0)
		log_warn("file watcher not running: code changes need a restart");
	if (vmpool_init(cfg) < 0) {
		codecache_shutdown();
		return 1;
	}
	dk_hooks hooks = {
		.worker_init = app_worker_init,
		.worker_fini = app_worker_fini,
		.handle = app_handle,
		.after = app_after,
		.ud = (void *)cfg,
	};
	log_info("dk listening on http://%s:%d (workers=%d, app=%s, templates=%s)",
			 cfg->bind, cfg->port, config_workers(cfg), cfg->app_dir, cfg->template_dir);
	stats_start();
	if (log_async_start(1u << 20) < 0)
		log_warn("log writer not running: logging synchronously");
	if (db_checkpointer_start(cfg) < 0)
		log_warn("no background checkpoints: SQLite checkpoints on commit");
	int rc = http_serve(cfg, &hooks);
	db_checkpointer_stop();
	sbuf st;
	sb_init(&st);
	if (stats_format(&st) == 0)
		log_info("final stats:\n%s", st.p);
	sb_free(&st);
	vmpool_shutdown();
	codecache_shutdown();
	log_async_stop();
	return rc == 0 ? 0 : 1;
}

int app_cli(const dk_config *cfg, const char *module, int argc, char **argv)
{
	if (codecache_init(cfg) < 0) {
		fprintf(stderr, "dk: codecache_init failed\n");
		return 1;
	}
	char err[4096];
	int rc = 1;
	sqlite3 *db = db_open(cfg->db_path, err, sizeof err);
	dk_vm *vm = NULL;
	if (!db) {
		fprintf(stderr, "dk: %s\n", err);
	} else if (!(vm = vm_build_ex(cfg, 0, err, sizeof err))) {
		fprintf(stderr, "dk: %s\n", err);
	} else {
		rc = bind_run_cli(vm_state(vm), cfg, db, module, argc, argv);
	}
	vm_destroy(vm);
	db_close(db);
	codecache_shutdown();
	return rc;
}

static void check_report(const char *what, const char *msg, void *ud)
{
	(void)ud;
	fprintf(stderr, "FAIL %s\n  %s\n", what, msg);
}

int app_check(const dk_config *cfg)
{
	if (codecache_init(cfg) < 0) {
		fprintf(stderr, "dk: codecache_init failed\n");
		return 1;
	}
	char err[4096];
	int fails = codecache_prewarm_ex(check_report, NULL);
	dk_vm *vm = vm_build(cfg, err, sizeof err);
	if (!vm) {
		fprintf(stderr, "FAIL building VM (config + require \"main\")\n  %s\n", err);
		fails++;
	} else if (bind_run_cli(vm_state(vm), cfg, NULL, "cli.check", 0, NULL) != 0) {
		fails++;     /* app/cli/check.lua: content files (reported by the module) */
	}
	vm_destroy(vm);
	codecache_shutdown();
	if (fails) {
		fprintf(stderr, "dk check: %d failure(s)\n", fails);
		return 1;
	}
	printf("dk check: ok\n");
	return 0;
}
