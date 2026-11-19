/* crypto.h :: hand-rolled primitives. No external deps.
 * SHA-256 (FIPS 180-4), HMAC-SHA256 (RFC 2104), PBKDF2-HMAC-SHA256 (RFC 8018). */
#ifndef DK_CRYPTO_H
#define DK_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t state[8];
    uint64_t bitlen;
    uint8_t  buf[64];
    size_t   buflen;
} sha256_ctx;

void sha256_init(sha256_ctx *c);
void sha256_update(sha256_ctx *c, const void *data, size_t n);
void sha256_final(sha256_ctx *c, uint8_t out[32]);
void sha256(const void *data, size_t n, uint8_t out[32]);

void hmac_sha256(const void *key, size_t keylen, const void *msg, size_t msglen, uint8_t out[32]);

void pbkdf2_hmac_sha256(const void *pw, size_t pwlen, const void *salt, size_t saltlen,
                        uint32_t iterations, uint8_t *out, size_t outlen);

/* Cryptographically secure random bytes via getrandom(2). 0 ok, -1 error. */
int  random_bytes(void *buf, size_t n);

/* Constant-time comparison of equal-length buffers: 1 if equal, 0 otherwise. */
int  ct_equal(const void *a, const void *b, size_t n);

/* Lowercase hex; out must hold 2*n+1 bytes (NUL-terminated). */
void hex_encode(const uint8_t *in, size_t n, char *out);

#endif
