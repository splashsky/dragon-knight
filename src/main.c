/* main.c :: command line entry point. */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app.h"
#include "config.h"
#include "lua.h"
#include "sqlite3.h"

#define DK_VERSION "2.0.0-dev"

static void usage(FILE *f)
{
	fprintf(f,
			"usage: dk <command> [--config PATH] [args...]\n"
			"\n"
			"commands:\n"
			"  serve              run the HTTP server\n"
			"  install [args...]  create schema + seed data (runs app/install.lua)\n"
			"  migrate [--status] upgrade the database schema (runs app/cli/migrate.lua)\n"
			"  user [args...]     user administration (runs app/cli/user.lua)\n"
			"  check              compile all modules/templates and build a VM; nonzero on error\n"
			"  version            print version information\n"
			"\n"
			"The config file defaults to ./config.lua.\n");
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
		rc = nrest ? (usage(stderr), 2) : app_serve(&cfg);
	} else if (!strcmp(cmd, "install")) {
		rc = app_cli(&cfg, "install", nrest, rest);
	} else if (!strcmp(cmd, "migrate")) {
		rc = app_cli(&cfg, "cli.migrate", nrest, rest);
	} else if (!strcmp(cmd, "user")) {
		rc = app_cli(&cfg, "cli.user", nrest, rest);
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
