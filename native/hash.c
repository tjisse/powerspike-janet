#include <janet.h>
#include <openssl/sha.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>

/* XXH64, seed zero: https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md */
static const uint64_t p1 = UINT64_C(11400714785074694791);
static const uint64_t p2 = UINT64_C(14029467366897019727);
static const uint64_t p3 = UINT64_C(1609587929392839161);
static const uint64_t p4 = UINT64_C(9650029242287828579);
static const uint64_t p5 = UINT64_C(2870177450012600261);
static uint64_t rotate(uint64_t x, unsigned n) { return (x << n) | (x >> (64 - n)); }
static uint64_t little(const uint8_t *p, unsigned n) {
    uint64_t x = 0;
    for (unsigned i = 0; i < n; ++i) x |= (uint64_t)p[i] << (8 * i);
    return x;
}
static uint64_t round64(uint64_t a, uint64_t b) { return rotate(a + b * p2, 31) * p1; }
static uint64_t merge64(uint64_t a, uint64_t b) { return (a ^ round64(0, b)) * p1 + p4; }
static Janet tooltip_hash(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    JanetByteView bytes = janet_getbytes(argv, 0);
    const uint8_t *p = bytes.bytes;
    size_t remaining = (size_t)bytes.len;
    uint64_t h;
    if (remaining >= 32) {
        uint64_t a = p1 + p2, b = p2, c = 0, d = 0 - p1;
        do {
            a = round64(a, little(p, 8)); b = round64(b, little(p + 8, 8));
            c = round64(c, little(p + 16, 8)); d = round64(d, little(p + 24, 8));
            p += 32; remaining -= 32;
        } while (remaining >= 32);
        h = rotate(a, 1) + rotate(b, 7) + rotate(c, 12) + rotate(d, 18);
        h = merge64(merge64(merge64(merge64(h, a), b), c), d);
    } else h = p5;
    h += (uint64_t)bytes.len;
    while (remaining >= 8) {
        h = rotate(h ^ round64(0, little(p, 8)), 27) * p1 + p4;
        p += 8; remaining -= 8;
    }
    if (remaining >= 4) {
        h = rotate(h ^ (little(p, 4) * p1), 23) * p2 + p3;
        p += 4; remaining -= 4;
    }
    while (remaining--) h = rotate(h ^ ((uint64_t)*p++ * p5), 11) * p1;
    h ^= h >> 33; h *= p2; h ^= h >> 29; h *= p3; h ^= h >> 32;
    char output[13];
    snprintf(output, sizeof(output), "{%010" PRIx64 "}", h & UINT64_C(0xffffffffff));
    return janet_cstringv(output);
}

static Janet sha256(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    JanetByteView bytes = janet_getbytes(argv, 0);
    unsigned char digest[SHA256_DIGEST_LENGTH];
    char hex[SHA256_DIGEST_LENGTH * 2];
    static const char digits[] = "0123456789abcdef";
    if (!SHA256(bytes.bytes, bytes.len, digest)) janet_panic("SHA-256 failed");
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        hex[i * 2] = digits[digest[i] >> 4];
        hex[i * 2 + 1] = digits[digest[i] & 15];
    }
    return janet_wrap_string(janet_string((const uint8_t *)hex, sizeof(hex)));
}

static const JanetReg functions[] = {
    {"tooltip-key", tooltip_hash, "(hash/tooltip-key bytes)\nReturn the 40-bit XXH64 key used by tooltip localization."},
    {"sha256", sha256, "(hash/sha256 bytes)\nReturn the lowercase SHA-256 digest."},
    {NULL, NULL, NULL}
};
JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "pshash", functions); }
