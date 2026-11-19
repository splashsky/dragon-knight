/* minitest.h :: tiny assertion helpers for C unit tests.
 *   CHECK(cond); CHECK_STR_EQ(a, b); CHECK_MEM_EQ(a, b, n); return TEST_SUMMARY(); */
#ifndef DK_MINITEST_H
#define DK_MINITEST_H

#include <stdio.h>
#include <string.h>

static int mt_checks, mt_fails;

#define CHECK(cond) do { \
	mt_checks++; \
	if (!(cond)) { mt_fails++; fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } \
} while (0)

#define CHECK_STR_EQ(a, b) do { \
	const char *mt_a = (a), *mt_b = (b); \
	mt_checks++; \
	if (!mt_a || !mt_b || strcmp(mt_a, mt_b) != 0) { \
		mt_fails++; \
		fprintf(stderr, "FAIL %s:%d: %s == %s\n  got:      \"%s\"\n  expected: \"%s\"\n", \
				__FILE__, __LINE__, #a, #b, mt_a ? mt_a : "(null)", mt_b ? mt_b : "(null)"); \
	} \
} while (0)

#define CHECK_MEM_EQ(a, b, n) do { \
	mt_checks++; \
	if (memcmp((a), (b), (n)) != 0) { \
		mt_fails++; fprintf(stderr, "FAIL %s:%d: memcmp(%s, %s, %s)\n", __FILE__, __LINE__, #a, #b, #n); \
	} \
} while (0)

#define TEST_SUMMARY() \
	(printf("%s: %d checks, %d failed\n", __FILE__, mt_checks, mt_fails), mt_fails ? 1 : 0)

#endif
