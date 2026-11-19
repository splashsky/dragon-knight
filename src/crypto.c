/* crypto.c :: SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256, CSPRNG, helpers. */
#include "crypto.h"

#include <errno.h>
#include <string.h>
#include <sys/random.h>

static const uint32_t K[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_block(uint32_t st[8], const uint8_t *p)
{
	uint32_t w[64];
	for (int i = 0; i < 16; i++)
		w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 |
			   (uint32_t)p[4 * i + 2] << 8 | (uint32_t)p[4 * i + 3];
	for (int i = 16; i < 64; i++) {
		uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
		uint32_t s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
		w[i] = w[i - 16] + s0 + w[i - 7] + s1;
	}
	uint32_t a = st[0], b = st[1], c = st[2], d = st[3];
	uint32_t e = st[4], f = st[5], g = st[6], h = st[7];
	for (int i = 0; i < 64; i++) {
		uint32_t t1 = h + (ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
		uint32_t t2 = (ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
		h = g; g = f; f = e; e = d + t1;
		d = c; c = b; b = a; a = t1 + t2;
	}
	st[0] += a; st[1] += b; st[2] += c; st[3] += d;
	st[4] += e; st[5] += f; st[6] += g; st[7] += h;
}

void sha256_init(sha256_ctx *c)
{
	static const uint32_t iv[8] = {
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
	};
	memcpy(c->state, iv, sizeof iv);
	c->bitlen = 0;
	c->buflen = 0;
}

void sha256_update(sha256_ctx *c, const void *data, size_t n)
{
	const uint8_t *p = data;
	c->bitlen += (uint64_t)n * 8;
	if (c->buflen) {
		size_t take = 64 - c->buflen;
		if (take > n) take = n;
		memcpy(c->buf + c->buflen, p, take);
		c->buflen += take;
		p += take;
		n -= take;
		if (c->buflen < 64) return;
		sha256_block(c->state, c->buf);
		c->buflen = 0;
	}
	while (n >= 64) {
		sha256_block(c->state, p);
		p += 64;
		n -= 64;
	}
	if (n) {
		memcpy(c->buf, p, n);
		c->buflen = n;
	}
}

void sha256_final(sha256_ctx *c, uint8_t out[32])
{
	uint64_t bits = c->bitlen;
	c->buf[c->buflen++] = 0x80;
	if (c->buflen > 56) {
		memset(c->buf + c->buflen, 0, 64 - c->buflen);
		sha256_block(c->state, c->buf);
		c->buflen = 0;
	}
	memset(c->buf + c->buflen, 0, 56 - c->buflen);
	for (int i = 0; i < 8; i++) c->buf[56 + i] = (uint8_t)(bits >> (56 - 8 * i));
	sha256_block(c->state, c->buf);
	for (int i = 0; i < 8; i++) {
		out[4 * i]     = (uint8_t)(c->state[i] >> 24);
		out[4 * i + 1] = (uint8_t)(c->state[i] >> 16);
		out[4 * i + 2] = (uint8_t)(c->state[i] >> 8);
		out[4 * i + 3] = (uint8_t)c->state[i];
	}
	memset(c, 0, sizeof *c);
}

void sha256(const void *data, size_t n, uint8_t out[32])
{
	sha256_ctx c;
	sha256_init(&c);
	sha256_update(&c, data, n);
	sha256_final(&c, out);
}

/* Precomputed inner/outer states, so PBKDF2 doesn't rehash the key each iteration. */
typedef struct {
	sha256_ctx inner, outer;
} hmac_key;

static void hmac_setkey(hmac_key *hk, const void *key, size_t keylen)
{
	uint8_t k[64], pad[64];
	memset(k, 0, sizeof k);
	if (keylen > 64) sha256(key, keylen, k);
	else if (keylen) memcpy(k, key, keylen);
	for (int i = 0; i < 64; i++) pad[i] = k[i] ^ 0x36;
	sha256_init(&hk->inner);
	sha256_update(&hk->inner, pad, 64);
	for (int i = 0; i < 64; i++) pad[i] = k[i] ^ 0x5c;
	sha256_init(&hk->outer);
	sha256_update(&hk->outer, pad, 64);
	memset(k, 0, sizeof k);
	memset(pad, 0, sizeof pad);
}

static void hmac_run(const hmac_key *hk, const void *m1, size_t n1,
					 const void *m2, size_t n2, uint8_t out[32])
{
	sha256_ctx c = hk->inner;
	uint8_t ih[32];
	sha256_update(&c, m1, n1);
	if (n2) sha256_update(&c, m2, n2);
	sha256_final(&c, ih);
	c = hk->outer;
	sha256_update(&c, ih, 32);
	sha256_final(&c, out);
}

void hmac_sha256(const void *key, size_t keylen, const void *msg, size_t msglen, uint8_t out[32])
{
	hmac_key hk;
	hmac_setkey(&hk, key, keylen);
	hmac_run(&hk, msg, msglen, NULL, 0, out);
	memset(&hk, 0, sizeof hk);
}

void pbkdf2_hmac_sha256(const void *pw, size_t pwlen, const void *salt, size_t saltlen,
						uint32_t iterations, uint8_t *out, size_t outlen)
{
	hmac_key hk;
	hmac_setkey(&hk, pw, pwlen);
	if (iterations == 0) iterations = 1;
	for (uint32_t blk = 1; outlen > 0; blk++) {
		uint8_t ctr[4] = { (uint8_t)(blk >> 24), (uint8_t)(blk >> 16), (uint8_t)(blk >> 8), (uint8_t)blk };
		uint8_t u[32], t[32];
		hmac_run(&hk, salt, saltlen, ctr, 4, u);
		memcpy(t, u, 32);
		for (uint32_t i = 1; i < iterations; i++) {
			hmac_run(&hk, u, 32, NULL, 0, u);
			for (int j = 0; j < 32; j++) t[j] ^= u[j];
		}
		size_t take = outlen < 32 ? outlen : 32;
		memcpy(out, t, take);
		out += take;
		outlen -= take;
		memset(u, 0, sizeof u);
		memset(t, 0, sizeof t);
	}
	memset(&hk, 0, sizeof hk);
}

int random_bytes(void *buf, size_t n)
{
	uint8_t *p = buf;
	while (n > 0) {
		ssize_t r = getrandom(p, n, 0);
		if (r < 0) {
			if (errno == EINTR) continue;
			return -1;
		}
		p += r;
		n -= (size_t)r;
	}
	return 0;
}

int ct_equal(const void *a, const void *b, size_t n)
{
	const volatile uint8_t *x = a, *y = b;
	uint8_t d = 0;
	for (size_t i = 0; i < n; i++) d |= x[i] ^ y[i];
	return d == 0;
}

void hex_encode(const uint8_t *in, size_t n, char *out)
{
	static const char hx[] = "0123456789abcdef";
	for (size_t i = 0; i < n; i++) {
		out[2 * i]     = hx[in[i] >> 4];
		out[2 * i + 1] = hx[in[i] & 15];
	}
	out[2 * n] = '\0';
}
