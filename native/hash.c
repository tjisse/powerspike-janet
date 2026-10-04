#include <janet.h>
#include <openssl/sha.h>

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
    {"sha256", sha256, "(hash/sha256 bytes)\nReturn the lowercase SHA-256 digest."},
    {NULL, NULL, NULL}
};
JANET_MODULE_ENTRY(JanetTable *env) { janet_cfuns(env, "pshash", functions); }
