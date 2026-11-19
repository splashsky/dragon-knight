/* config.h :: server configuration, loaded from a Lua file (default ./config.lua).
 * The file must `return { ... }`. It is executed in a throwaway sandboxed Lua state
 * (base library only). Missing keys get defaults; a missing file means all defaults.
 * The Lua app additionally sees the full table as dk.config (re-read per VM, so
 * app-level keys hot-reload; server keys below require restart). */
#ifndef DK_CONFIG_H
#define DK_CONFIG_H

#include <stddef.h>

typedef struct {
	char  *path;              /* path of the config file itself (may not exist) */
	char  *bind;              /* "127.0.0.1" */
	int    port;              /* 8080 */
	int    workers;           /* 0   : request worker threads; 0 = one per CPU (at least 2) */
	int    spares;            /* 0   : Lua VMs in the pool (ready + in use); 0 => workers + 1 */
	char  *db_path;           /* "data/dk.db" */
	char  *app_dir;           /* "app" */
	char  *template_dir;      /* "templates" */
	char  *public_dir;        /* "public"  (served at /static/) */
	char  *outbox_dir;        /* "data/outbox" */
	char  *secret;            /* HMAC key for signed values; `dk install` prints a random one if empty */
	int    dev;               /* 1 : show Lua tracebacks in 500 pages */
	size_t max_header_bytes;  /* 16384 */
	size_t max_body_bytes;    /* 1048576 */
	int    keepalive_timeout; /* 15 seconds */
	int    request_timeout;   /* 30 seconds (time to receive a full request) */
	int    max_connections;   /* 1024 */
	int    queue_timeout_ms;  /* 2000: a request waiting longer for a worker gets a fast 503 (0 = never) */
	int    access_log;        /* 1   : one log line per request (written by a background thread) */
	size_t static_cache_bytes;    /* 8 MiB: memory for cached /static/ files (0 = no cache) */
	size_t static_cache_file_max; /* 256 KiB: larger files are sent with sendfile() */
	char  *stats_socket;      /* NULL: <db dir>/dk.sock; "" = none (`dk stats`) */
	size_t vm_memory_limit;   /* 256 MiB: address space per Lua VM (its memory limit) */
	int    vm_gc_pause;       /* 1000: Lua GC pause (%) of request VMs */
	int    db_cache_kb;       /* 8192: SQLite page cache per connection (KiB) */
	size_t db_mmap_bytes;     /* 0: SQLite memory-mapped I/O per connection (bytes; 0 = off) */
	int    db_checkpoint_ms;  /* 1000: background WAL checkpoint interval (0 = SQLite's auto) */
	int    max_streams;           /* 512: open event streams (SSE) in all; more get 503 */
	int    max_streams_per_ip;    /* 8: open event streams per client address */
	size_t stream_queue_bytes;    /* 256 KiB: unsent bytes a stream may queue before it is closed */
	int    stream_heartbeat_ms;   /* 15000: ": ping" on quiet streams (0 = none) */
	int    stream_replay_events;  /* 200: events kept per channel for Last-Event-ID replay */
	int    stream_replay_seconds; /* 300: ... and for how long (0 = no replay) */
} dk_config;

void config_defaults(dk_config *c);
/* 0 ok; -1 error with message in err. Fills defaults first. */
int  config_load(dk_config *c, const char *path, char *err, size_t errlen);
void config_free(dk_config *c);

/* Effective worker count: cfg->workers, or the CPUs this process may run on (min 2). */
int  config_workers(const dk_config *c);
/* Effective stats socket path (NULL: none). */
const char *config_stats_socket(const dk_config *c, char *buf, size_t n);

#endif
