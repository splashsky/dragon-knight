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
    int    workers;           /* 4   : request worker threads */
    int    spares;            /* 0   : warm spare VMs to keep ready; 0 => workers + 1 */
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
} dk_config;

void config_defaults(dk_config *c);
/* 0 ok; -1 error with message in err. Fills defaults first. */
int  config_load(dk_config *c, const char *path, char *err, size_t errlen);
void config_free(dk_config *c);

#endif
