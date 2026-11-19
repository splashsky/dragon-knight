/* test_crypto.c :: SHA-256 (FIPS 180), HMAC-SHA256 (RFC 4231), PBKDF2-HMAC-SHA256 vectors. */
#include <stdlib.h>
#include <string.h>

#include "crypto.h"
#include "minitest.h"

#define SHA_X55 "d5e285683cd4efc02d021a5c62014694958901005d6f71e89e0989fac77e4072"
#define SHA_X56 "04c26261370ee7541549d16dee320c723e3fd14671e66a099afe0a377c16888e"
#define SHA_X63 "75220b47218278e656f2013bb8f0c455a25eaf01e86c64924e9d48d89776d6f2"
#define SHA_X64 "7ce100971f64e7001e8fe5a51973ecdfe1ced42befe7ee8d5fd6219506b5393c"

static const char *hex(const uint8_t *p, size_t n)
{
    static char buf[2 * 256 + 1];
    hex_encode(p, n, buf);
    return buf;
}

static const char *sha_hex(const void *d, size_t n)
{
    uint8_t out[32];
    sha256(d, n, out);
    return hex(out, 32);
}

static const char *hmac_hex(const void *k, size_t kn, const void *m, size_t mn, size_t outn)
{
    uint8_t out[32];
    hmac_sha256(k, kn, m, mn, out);
    return hex(out, outn);
}

static const char *pbkdf2_hex(const char *pw, const char *salt, uint32_t c, size_t dk)
{
    uint8_t out[128];
    pbkdf2_hmac_sha256(pw, strlen(pw), salt, strlen(salt), c, out, dk);
    return hex(out, dk);
}

static void test_sha256(void)
{
    CHECK_STR_EQ(sha_hex("", 0), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    CHECK_STR_EQ(sha_hex("abc", 3), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const char *m448 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    CHECK_STR_EQ(sha_hex(m448, strlen(m448)),
                 "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    const char *m896 = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
                       "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
    CHECK_STR_EQ(sha_hex(m896, strlen(m896)),
                 "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");

    /* 1M 'a': once in one shot, once in odd-sized chunks through the streaming API. */
    size_t n = 1000000;
    char *a = malloc(n);
    CHECK(a != NULL);
    if (!a) return;
    memset(a, 'a', n);
    CHECK_STR_EQ(sha_hex(a, n), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    sha256_ctx c;
    uint8_t out[32];
    sha256_init(&c);
    for (size_t off = 0, step = 1; off < n; off += step, step = step % 97 + 1)
        sha256_update(&c, a + off, off + step > n ? n - off : step);
    sha256_final(&c, out);
    CHECK_STR_EQ(hex(out, 32), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    free(a);

    /* Padding edges (55/56/63/64 bytes), checked against Python's hashlib. */
    char buf[64];
    memset(buf, 'x', sizeof buf);
    CHECK_STR_EQ(sha_hex(buf, 55), SHA_X55);
    CHECK_STR_EQ(sha_hex(buf, 56), SHA_X56);
    CHECK_STR_EQ(sha_hex(buf, 63), SHA_X63);
    CHECK_STR_EQ(sha_hex(buf, 64), SHA_X64);
}

static void test_sha256_boundaries(void)
{
    /* Compare one-shot with byte-at-a-time streaming across block/padding edges. */
    uint8_t buf[200];
    for (size_t i = 0; i < sizeof buf; i++) buf[i] = (uint8_t)(i * 7 + 3);
    for (size_t len = 0; len <= sizeof buf; len++) {
        uint8_t a[32], b[32];
        sha256(buf, len, a);
        sha256_ctx c;
        sha256_init(&c);
        for (size_t i = 0; i < len; i++) sha256_update(&c, buf + i, 1);
        sha256_final(&c, b);
        CHECK_MEM_EQ(a, b, 32);
    }
}

static void test_hmac(void)
{
    uint8_t k[131];

    memset(k, 0x0b, 20);
    CHECK_STR_EQ(hmac_hex(k, 20, "Hi There", 8, 32),
                 "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");

    CHECK_STR_EQ(hmac_hex("Jefe", 4, "what do ya want for nothing?", 28, 32),
                 "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");

    uint8_t d[50];
    memset(k, 0xaa, 20);
    memset(d, 0xdd, 50);
    CHECK_STR_EQ(hmac_hex(k, 20, d, 50, 32),
                 "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe");

    for (int i = 0; i < 25; i++) k[i] = (uint8_t)(i + 1);
    memset(d, 0xcd, 50);
    CHECK_STR_EQ(hmac_hex(k, 25, d, 50, 32),
                 "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b");

    memset(k, 0x0c, 20);
    CHECK_STR_EQ(hmac_hex(k, 20, "Test With Truncation", 20, 16), "a3b6167473100ee06e0c796c2955552b");

    memset(k, 0xaa, 131);
    const char *m6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    CHECK_STR_EQ(hmac_hex(k, 131, m6, strlen(m6), 32),
                 "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");

    const char *m7 = "This is a test using a larger than block-size key and a larger than "
                     "block-size data. The key needs to be hashed before being used by the "
                     "HMAC algorithm.";
    CHECK_STR_EQ(hmac_hex(k, 131, m7, strlen(m7), 32),
                 "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2");
}

static void test_pbkdf2(void)
{
    CHECK_STR_EQ(pbkdf2_hex("password", "salt", 1, 32),
                 "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
    CHECK_STR_EQ(pbkdf2_hex("password", "salt", 2, 32),
                 "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43");
    CHECK_STR_EQ(pbkdf2_hex("password", "salt", 4096, 32),
                 "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a");
    CHECK_STR_EQ(pbkdf2_hex("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 40),
                 "348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9");
    /* Short output is a prefix of the full block. */
    CHECK_STR_EQ(pbkdf2_hex("password", "salt", 1, 5), "120fb6cffc");
}

static void test_random(void)
{
    uint8_t a[32], b[32], zero[32] = {0};
    CHECK(random_bytes(a, sizeof a) == 0);
    CHECK(random_bytes(b, sizeof b) == 0);
    CHECK(memcmp(a, b, 32) != 0);
    CHECK(memcmp(a, zero, 32) != 0);
    CHECK(random_bytes(a, 0) == 0);
    /* Large request (getrandom may return short reads above 256 bytes for some flags). */
    size_t n = 1 << 20;
    uint8_t *big = malloc(n);
    CHECK(big != NULL);
    if (big) {
        memset(big, 0, n);
        CHECK(random_bytes(big, n) == 0);
        size_t zeros = 0;
        for (size_t i = n - 4096; i < n; i++) zeros += big[i] == 0;
        CHECK(zeros < 100);   /* tail was actually filled */
        free(big);
    }
}

static void test_ct_hex(void)
{
    CHECK(ct_equal("abc", "abc", 3) == 1);
    CHECK(ct_equal("abc", "abd", 3) == 0);
    CHECK(ct_equal("xbc", "abc", 3) == 0);
    CHECK(ct_equal("", "", 0) == 1);

    char out[16];
    const uint8_t in[] = { 0x00, 0x0f, 0xa5, 0xff };
    hex_encode(in, 4, out);
    CHECK_STR_EQ(out, "000fa5ff");
    hex_encode(in, 0, out);
    CHECK_STR_EQ(out, "");
}

int main(void)
{
    test_sha256();
    test_sha256_boundaries();
    test_hmac();
    test_pbkdf2();
    test_random();
    test_ct_hex();
    return TEST_SUMMARY();
}
