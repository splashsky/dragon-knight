/* test_util.c :: sbuf, url/html encoding, read_file, time. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "util.h"
#include "minitest.h"

static void test_sbuf(void)
{
	sbuf b;
	sb_init(&b);
	CHECK(b.p == NULL && b.len == 0);
	CHECK(sb_puts(&b, "hello") == 0);
	CHECK_STR_EQ(b.p, "hello");
	CHECK(sb_putc(&b, ' ') == 0);
	CHECK(sb_printf(&b, "%d-%s", 42, "x") == 0);
	CHECK_STR_EQ(b.p, "hello 42-x");
	CHECK(b.len == 10);

	/* Growth across many appends, and a printf larger than the internal scratch buffer. */
	sb_reset(&b);
	CHECK(b.len == 0 && b.p[0] == '\0');
	int fails = 0;
	for (int i = 0; i < 10000; i++) fails += sb_append(&b, "0123456789", 10) != 0;
	CHECK(fails == 0);
	CHECK(b.len == 100000);
	CHECK(b.cap > b.len && b.p[b.len] == '\0');
	CHECK(memcmp(b.p + 99990, "0123456789", 10) == 0);

	sb_reset(&b);
	char big[1000];
	memset(big, 'z', sizeof big - 1);
	big[sizeof big - 1] = '\0';
	CHECK(sb_printf(&b, "<%s>%d", big, 7) == 0);
	CHECK(b.len == 1002);
	CHECK(b.p[0] == '<' && b.p[1000] == '>' && b.p[1001] == '7' && b.p[1002] == '\0');
	CHECK(strlen(b.p) == b.len);

	/* Append with embedded NUL keeps length. */
	sb_reset(&b);
	CHECK(sb_append(&b, "a\0b", 3) == 0);
	CHECK(b.len == 3 && b.p[1] == '\0' && b.p[2] == 'b');
	CHECK(sb_append(&b, NULL, 0) == 0);
	CHECK(b.len == 3);

	char *s = sb_steal(&b);
	CHECK(s != NULL && s[2] == 'b');
	CHECK(b.p == NULL && b.len == 0 && b.cap == 0);
	free(s);

	s = sb_steal(&b);          /* stealing an empty buffer yields "" */
	CHECK(s != NULL && s[0] == '\0');
	free(s);

	CHECK(sb_reserve(&b, (size_t)-1) == -1);
	sb_free(&b);
	sb_free(&b);
	CHECK(b.p == NULL);
}

static const char *dec(const char *in, int plus)
{
	static char buf[256];
	snprintf(buf, sizeof buf, "%s", in);
	size_t n = url_decode(buf, strlen(buf), plus);
	if (n != strlen(buf)) return "(length mismatch)";
	return buf;
}

static void test_url_decode(void)
{
	CHECK_STR_EQ(dec("a+b%20c", 1), "a b c");
	CHECK_STR_EQ(dec("a+b%20c", 0), "a+b c");
	CHECK_STR_EQ(dec("%41%4a%4A%7e", 1), "AJJ~");
	CHECK_STR_EQ(dec("100%", 1), "100%");
	CHECK_STR_EQ(dec("%4", 1), "%4");
	CHECK_STR_EQ(dec("%zz%2", 1), "%zz%2");
	CHECK_STR_EQ(dec("%%41", 1), "%A");
	CHECK_STR_EQ(dec("", 1), "");
	CHECK_STR_EQ(dec("%C3%A9", 1), "\xc3\xa9");

	char b[] = "x%00y";
	size_t n = url_decode(b, 5, 1);
	CHECK(n == 3 && b[0] == 'x' && b[1] == '\0' && b[2] == 'y' && b[3] == '\0');

	/* Only the first n bytes are considered. */
	char c[] = "ab%41";
	n = url_decode(c, 4, 1);
	CHECK(n == 4);
	CHECK_STR_EQ(c, "ab%4");
}

static void test_url_encode(void)
{
	sbuf b;
	sb_init(&b);
	const char *in = "a b&c=d/é~._-";
	CHECK(url_encode(&b, in, strlen(in)) == 0);
	CHECK_STR_EQ(b.p, "a%20b%26c%3Dd%2F%C3%A9~._-");
	sb_reset(&b);
	CHECK(url_encode(&b, "\0+", 2) == 0);
	CHECK_STR_EQ(b.p, "%00%2B");
	sb_reset(&b);
	CHECK(url_encode(&b, "", 0) == 0);
	CHECK(b.len == 0);
	sb_free(&b);
}

static void test_html_escape(void)
{
	sbuf b;
	sb_init(&b);
	const char *in = "<a href=\"x\">Tom & Jerry's</a>";
	CHECK(html_escape(&b, in, strlen(in)) == 0);
	CHECK_STR_EQ(b.p, "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;");
	sb_reset(&b);
	CHECK(html_escape(&b, "plain", 5) == 0);
	CHECK_STR_EQ(b.p, "plain");
	sb_reset(&b);
	CHECK(html_escape(&b, "&&", 2) == 0);
	CHECK_STR_EQ(b.p, "&amp;&amp;");
	sb_reset(&b);
	CHECK(html_escape(&b, "", 0) == 0);
	CHECK(b.len == 0);
	sb_free(&b);
}

static void test_read_file(void)
{
	char path[] = "/tmp/dk_test_util_XXXXXX";
	int fd = mkstemp(path);
	CHECK(fd >= 0);
	if (fd < 0) return;

	/* Larger than any initial guess and containing a NUL byte. */
	size_t n = 100000;
	char *data = malloc(n);
	CHECK(data != NULL);
	if (!data) { close(fd); unlink(path); return; }
	for (size_t i = 0; i < n; i++) data[i] = (char)('a' + i % 26);
	data[500] = '\0';
	CHECK(write(fd, data, n) == (ssize_t)n);
	close(fd);

	size_t len = 0;
	char *got = read_file(path, &len);
	CHECK(got != NULL);
	if (got) {
		CHECK(len == n);
		CHECK(memcmp(got, data, n) == 0);
		CHECK(got[n] == '\0');
		free(got);
	}
	free(data);

	/* Empty file. */
	FILE *f = fopen(path, "w");
	CHECK(f != NULL);
	if (f) fclose(f);
	got = read_file(path, &len);
	CHECK(got != NULL && len == 0 && got[0] == '\0');
	free(got);
	unlink(path);

	errno = 0;
	CHECK(read_file("/nonexistent/dk/file", &len) == NULL);
	CHECK(errno == ENOENT);
	CHECK(read_file("/tmp", &len) == NULL);
	CHECK(errno == EISDIR);

	/* /proc files report st_size 0 but have content. */
	got = read_file("/proc/self/status", &len);
	CHECK(got != NULL && len > 0 && strlen(got) == len);
	free(got);
}

static void test_time_log(void)
{
	CHECK(now_unix() > 1700000000);
	double a = now_mono(), b = now_mono();
	CHECK(b >= a && a > 0);
	log_info("test_util: info %d", 1);
	log_warn("test_util: warn %s", "two");
	char big[8000];
	memset(big, 'L', sizeof big - 1);
	big[sizeof big - 1] = '\0';
	log_error("test_util: truncated long line %s", big);
	CHECK(1);
}

int main(void)
{
	test_sbuf();
	test_url_decode();
	test_url_encode();
	test_html_escape();
	test_read_file();
	test_time_log();
	return TEST_SUMMARY();
}
