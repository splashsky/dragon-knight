/* test_static.c :: static_rel_ok and static_file_exists (dk.static_exists). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "static.h"
#include "minitest.h"

static char root[256];

static void put(const char *rel)
{
	char path[512];
	snprintf(path, sizeof path, "%s/%s", root, rel);
	FILE *f = fopen(path, "w");
	CHECK(f != NULL);
	if (f) {
		fputs("x", f);
		fclose(f);
	}
}

static void sub(const char *rel)
{
	char path[512];
	snprintf(path, sizeof path, "%s/%s", root, rel);
	CHECK(mkdir(path, 0700) == 0);
}

static void test_rel_ok(void)
{
	CHECK(static_rel_ok("images/skills/heal.png", 22));
	CHECK(static_rel_ok("css/dk.css", 10));
	CHECK(static_rel_ok("a-b_C.9/x", 9));
	CHECK(!static_rel_ok("", 0));
	CHECK(!static_rel_ok("/etc/passwd", 11));
	CHECK(!static_rel_ok("../config.lua", 13));
	CHECK(!static_rel_ok("images/../../x", 14));
	CHECK(!static_rel_ok("a..b", 4));
	CHECK(!static_rel_ok("images/skills/he al.png", 23));
	CHECK(!static_rel_ok("images\\x.png", 12));
	CHECK(!static_rel_ok("images/%2e%2e/x", 15));
	CHECK(!static_rel_ok("a\0b", 3));            /* embedded NUL */
	CHECK(!static_rel_ok("caf\xc3\xa9.png", 9));  /* non-ASCII */
	char big[STATIC_REL_MAX + 2];
	memset(big, 'a', sizeof big - 1);
	big[sizeof big - 1] = '\0';
	CHECK(!static_rel_ok(big, strlen(big)));
	big[STATIC_REL_MAX] = '\0';
	CHECK(static_rel_ok(big, strlen(big)));
}

static void test_exists(void)
{
	char pub[300], outside[300], link[600];
	snprintf(pub, sizeof pub, "%s/public", root);
	sub("public");
	sub("public/images");
	sub("public/images/skills");
	put("public/images/skills/heal.png");
	put("secret.txt");
	snprintf(outside, sizeof outside, "%s/secret.txt", root);
	snprintf(link, sizeof link, "%s/images/out.png", pub);
	CHECK(symlink(outside, link) == 0);
	snprintf(link, sizeof link, "%s/images/in.png", pub);
	CHECK(symlink("skills/heal.png", link) == 0);

	CHECK(static_file_exists(pub, "images/skills/heal.png") == 1);
	CHECK(static_file_exists(pub, "images/skills/./heal.png") == 1);
	CHECK(static_file_exists(pub, "images/in.png") == 1);          /* a symlink inside */
	CHECK(static_file_exists(pub, "images/skills/nope.png") == 0);
	CHECK(static_file_exists(pub, "images/skills") == 0);          /* a directory */
	CHECK(static_file_exists(pub, "images/out.png") == 0);         /* a symlink leading out */
	CHECK(static_file_exists(pub, "../secret.txt") == -1);
	CHECK(static_file_exists(pub, outside) == -1);                 /* absolute */
	CHECK(static_file_exists(pub, "images/skills/heal.png?x") == -1);
	CHECK(static_file_exists(NULL, "images/skills/heal.png") == 0);
	CHECK(static_file_exists("", "images/skills/heal.png") == 0);
	snprintf(link, sizeof link, "%s/missing", root);
	CHECK(static_file_exists(link, "images/skills/heal.png") == 0);
}

static void cleanup(void)
{
	static const char *const files[] = {
		"public/images/in.png", "public/images/out.png", "public/images/skills/heal.png", "secret.txt", NULL
	};
	static const char *const dirs[] = { "public/images/skills", "public/images", "public", NULL };
	char path[512];
	for (int i = 0; files[i]; i++) {
		snprintf(path, sizeof path, "%s/%s", root, files[i]);
		unlink(path);
	}
	for (int i = 0; dirs[i]; i++) {
		snprintf(path, sizeof path, "%s/%s", root, dirs[i]);
		rmdir(path);
	}
	rmdir(root);
}

int main(void)
{
	const char *tmp = getenv("TMPDIR");
	snprintf(root, sizeof root, "%s/dk-static-XXXXXX", tmp && *tmp ? tmp : "/tmp");
	if (!mkdtemp(root)) {
		perror("mkdtemp");
		return 1;
	}
	test_rel_ok();
	test_exists();
	cleanup();
	return TEST_SUMMARY();
}
