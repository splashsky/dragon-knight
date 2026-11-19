/* stats.c :: metric names and formatting (see stats.h). */
#include "stats.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "codecache.h"
#include "hub.h"
#include "vmpool.h"

_Atomic uint64_t dk_stat[ST_COUNT];

enum { COUNTER, GAUGE, MAX };

#define DK_STAT_ROW(name, kind, help) { #name, kind, help },
static const struct {
	const char *name;
	int kind;
	const char *help;
} info[ST_COUNT] = { DK_STATS(DK_STAT_ROW) };
#undef DK_STAT_ROW

static double started;
static const char *_Atomic server_backend;
static atomic_int server_workers;

void stats_set_server(const char *backend, int workers)
{
	atomic_store(&server_backend, backend);
	atomic_store(&server_workers, workers);
}

const char *stat_name(int k) { return info[k].name; }
const char *stat_help(int k) { return info[k].help; }

const char *stat_kind(int k)
{
	return info[k].kind == COUNTER ? "counter" : info[k].kind == GAUGE ? "gauge" : "max";
}

void stats_start(void)
{
	started = now_mono();
}

long stats_rss_kb(void)
{
	FILE *f = fopen("/proc/self/statm", "r");
	if (!f)
		return -1;
	long size, rss;
	int n = fscanf(f, "%ld %ld", &size, &rss);
	fclose(f);
	if (n != 2)
		return -1;
	return rss * (sysconf(_SC_PAGESIZE) / 1024);
}

int stats_format(sbuf *out)
{
	int err = 0;
	err |= sb_printf(out, "uptime_s %.0f\n", started > 0 ? now_mono() - started : 0.0);
	err |= sb_printf(out, "rss_kb %ld\n", stats_rss_kb());
	const char *be = atomic_load(&server_backend);
	if (be)
		err |= sb_printf(out, "event_backend %s\nworkers %d\n", be, atomic_load(&server_workers));
	vmpool_stats vs;
	vmpool_get_stats(&vs);
	err |= sb_printf(out, "vm_ready %d\n", vs.ready);
	err |= sb_printf(out, "code_generation %llu\n", (unsigned long long)codecache_generation());
	for (int k = 0; k < ST_COUNT; k++)
		err |= sb_printf(out, "%s %llu\n", info[k].name, (unsigned long long)stat_get(k));
	err |= hub_format_stats(out);
	return err ? -1 : 0;
}

#ifdef DK_COUNT_MALLOC
/* Debug builds link with -Wl,--wrap=malloc,... so every malloc/calloc/realloc made by
 * dk, Lua and SQLite objects is counted (not those inside libc itself). */
void *__real_malloc(size_t n);
void *__real_calloc(size_t n, size_t m);
void *__real_realloc(void *p, size_t n);
void *__wrap_malloc(size_t n);
void *__wrap_calloc(size_t n, size_t m);
void *__wrap_realloc(void *p, size_t n);

void *__wrap_malloc(size_t n)
{
	stat_inc(ST_mallocs);
	return __real_malloc(n);
}

void *__wrap_calloc(size_t n, size_t m)
{
	stat_inc(ST_mallocs);
	return __real_calloc(n, m);
}

void *__wrap_realloc(void *p, size_t n)
{
	stat_inc(ST_mallocs);
	return __real_realloc(p, n);
}
#endif
