/* main.c :: command line entry point. */
#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "app.h"
#include "backup.h"
#include "config.h"
#include "lua.h"
#include "sqlite3.h"

#define DK_VERSION "2.1.0-dev"

static void usage(FILE *f)
{
	fprintf(f,
			"usage: dk <command> [--config PATH] [args...]\n"
			"\n"
			"commands:\n"
			"  serve [--port N] [--bind ADDR]\n"
			"                     run the HTTP server (--port/--bind override the config;\n"
			"                     port 0 picks a free port)\n"
			"  install [args...]  create schema + seed data (runs app/install.lua)\n"
			"  migrate [--status] upgrade the database schema (runs app/cli/migrate.lua)\n"
			"  backup [OUTPUT]    copy the database safely, even while serving (default:\n"
			"                     <db dir>/backups/<name>-YYYYMMDD-HHMMSS.db); prints the path\n"
			"  content sync|status\n"
			"                     sync the content files (app/content/) into the database now,\n"
			"                     or show whether it is in sync (runs app/cli/content.lua)\n"
			"  user [args...]     user administration (runs app/cli/user.lua)\n"
			"  check              compile all modules/templates, build a VM and validate the\n"
			"                     content files; nonzero on error\n"
			"  version            print version information\n"
			"\n"
			"The config file defaults to ./config.lua. migrate, content, user and backup exit with\n"
			"status %d when the database does not exist (they never create it).\n", DK_EXIT_NO_DB);
}

/* `--name VALUE` or `--name=VALUE` at argv[*i]; advances *i past VALUE. */
static int take_opt(int argc, char **argv, int *i, const char *name, const char **val)
{
	size_t n = strlen(name);
	if (strncmp(argv[*i], name, n)) return 0;
	if (argv[*i][n] == '=') {
		*val = argv[*i] + n + 1;
		return 1;
	}
	if (argv[*i][n]) return 0;
	*val = *i + 1 < argc ? argv[++*i] : NULL;
	return 1;
}

/* dk serve [--port N] [--bind ADDR]: override the config's listen address. 0 ok, 2 usage. */
static int serve_options(dk_config *cfg, int argc, char **argv)
{
	for (int i = 0; i < argc; i++) {
		const char *v = NULL;
		if (take_opt(argc, argv, &i, "--port", &v)) {
			char *end;
			errno = 0;
			long port = v ? strtol(v, &end, 10) : -1;
			if (!v || !*v || *end || errno || port < 0 || port > 65535) {
				fprintf(stderr, "dk serve: --port needs a number from 1 to 65535 (0: any free port)\n");
				return 2;
			}
			cfg->port = (int)port;
		} else if (take_opt(argc, argv, &i, "--bind", &v)) {
			unsigned char addr[sizeof(struct in6_addr)];
			if (!v || (inet_pton(AF_INET, v, addr) != 1 && inet_pton(AF_INET6, v, addr) != 1)) {
				fprintf(stderr, "dk serve: --bind needs an IPv4 or IPv6 address (e.g. 127.0.0.1, 0.0.0.0, ::1)\n");
				return 2;
			}
			char *bind = strdup(v);
			if (!bind) return 1;
			free(cfg->bind);
			cfg->bind = bind;
		} else {
			fprintf(stderr, "dk serve: unexpected argument: %s\n\n", argv[i]);
			usage(stderr);
			return 2;
		}
	}
	return 0;
}

/* Commands that work on an existing database must not create an empty one. */
static int need_db(const dk_config *cfg, const char *cmd)
{
	struct stat st;
	if (stat(cfg->db_path, &st) == 0 || errno != ENOENT) return 0;
	fprintf(stderr, "dk %s: no database at %s; run dk install first\n", cmd, cfg->db_path);
	return DK_EXIT_NO_DB;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		usage(stderr);
		return 2;
	}
	const char *cmd = argv[1];
	if (!strcmp(cmd, "version") || !strcmp(cmd, "--version")) {
		printf("dk %s (%s, SQLite %s)\n", DK_VERSION, LUA_RELEASE, sqlite3_libversion());
		return 0;
	}
	if (!strcmp(cmd, "help") || !strcmp(cmd, "--help") || !strcmp(cmd, "-h")) {
		usage(stdout);
		return 0;
	}

	/* pull out --config PATH / --config=PATH; everything else goes to the command */
	const char *config_path = "config.lua";
	char **rest = calloc((size_t)argc, sizeof *rest);
	if (!rest) return 1;
	int nrest = 0;
	for (int i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "--config")) {
			if (i + 1 >= argc) {
				fprintf(stderr, "dk: --config needs a path\n");
				free(rest);
				return 2;
			}
			config_path = argv[++i];
		} else if (!strncmp(argv[i], "--config=", 9)) {
			config_path = argv[i] + 9;
		} else {
			rest[nrest++] = argv[i];
		}
	}

	signal(SIGPIPE, SIG_IGN);
	dk_config cfg;
	char err[1024];
	if (config_load(&cfg, config_path, err, sizeof err) < 0) {
		fprintf(stderr, "dk: %s\n", err);
		free(rest);
		return 1;
	}

	int rc;
	if (!strcmp(cmd, "serve")) {
		rc = serve_options(&cfg, nrest, rest);
		if (!rc) rc = app_serve(&cfg);
	} else if (!strcmp(cmd, "install")) {
		rc = app_cli(&cfg, "install", nrest, rest);
	} else if (!strcmp(cmd, "migrate")) {
		rc = need_db(&cfg, cmd);
		if (!rc) rc = app_cli(&cfg, "cli.migrate", nrest, rest);
	} else if (!strcmp(cmd, "backup")) {
		rc = backup_cli(&cfg, nrest, rest);
	} else if (!strcmp(cmd, "content")) {
		rc = need_db(&cfg, cmd);
		if (!rc) rc = app_cli(&cfg, "cli.content", nrest, rest);
	} else if (!strcmp(cmd, "user")) {
		rc = need_db(&cfg, cmd);
		if (!rc) rc = app_cli(&cfg, "cli.user", nrest, rest);
	} else if (!strcmp(cmd, "check")) {
		rc = app_check(&cfg);
	} else {
		fprintf(stderr, "dk: unknown command '%s'\n\n", cmd);
		usage(stderr);
		rc = 2;
	}
	config_free(&cfg);
	free(rest);
	return rc;
}
