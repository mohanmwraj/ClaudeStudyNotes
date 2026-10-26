# 03 · Secure Boot, TrustZone, MPU, MMU Page Tables, and TCM SRAM

> **Folder:** `02-Linker-Scripts-ELF-and-Bare-Metal-Boot-Sequence/` · **File 3 of 3**
> **Anchors:**
> - Arm *ARMv8-M ARM* (DDI 0553): Security Extension, SAU/IDAU, `SG`/`BXNS`/`BLXNS`/`TT`, PMSAv8, SecureFault.
> - Arm *CMSE: Cortex-M Security Extensions requirements on development tools* (ECM0359818).
> - ARMv7-M ARM (DDI 0403) §B3.5 *PMSAv7*.
> - Arm ARM for A-profile (DDI 0487) chapter D8 *VMSAv8-64 translation*, MAIR/TCR/SCTLR, TLB maintenance and break-before-make.
> - Arm *Trusted Base System Architecture* (TBSA-M) and PSA Certified; Trusted Firmware-A/-M and MCUboot design documents.
> - FIPS 180-4 (SHA-256).
> - Cortex-M7 TRM (TCM interfaces, AHBS).
>
> **Verification:** CMSE codegen and **SG veneer generation** (LLD `--cmse-implib`), MPU encoders (PMSAv7/v8), the AArch64 page-table builder and walker, the MMU-enable and break-before-make sequences, and the secure-boot verifier (with FIPS 180-4 test vectors) were all compiled, linked or run on 2026-10-26 with Clang/LLD 21.1. Every output block in this file was inserted verbatim from the tool output by script, not retyped.

---

## 0. The thesis

Security and isolation on silicon are **address-space properties enforced by hardware on every bus transaction**. They depend on:

- the NS bit on AXI `AxPROT[1]`;
- SAU/IDAU attribution;
- MPU region hits;
- page-table permission bits;
- and a boot ROM that refuses unsigned code.

Firmware doesn't *implement* these protections. It *configures* them, and a configuration mistake is a silently open door. The Principal-level skill is to read the encoded register values and descriptors and know exactly which accesses they allow.

---

## 1. First-Principles Hardware Mechanics

### 1.1 Chain of trust

```text
 Immutable BootROM (mask ROM, cannot be patched)
   │  holds/locates: hash of the root public key (OTP/eFuses), anti-rollback counters (OTP)
   │  verifies ──► BL1/BL2 (first mutable stage: TF-A BL2, MCUboot, vendor SBL)
   │                 verifies ──► BL31 (EL3 runtime / secure monitor, PSCI)
   │                              BL32 (Secure-EL1 TEE: OP-TEE / TF-M on M-profile)
   │                              BL33 (Non-secure: U-Boot / UEFI / application)
   └── every stage: authenticate BEFORE execute; measure (hash-extend into a PCR/log) for attestation
```

| Concept | Meaning | Failure if missing |
|---|---|---|
| **Verified boot** | Each stage *checks a signature* and refuses to run unauthenticated code | Arbitrary code execution at boot |
| **Measured boot** | Each stage *records a hash* (TPM PCR extend, DICE CDI) for later attestation | Remote parties can't prove what ran |
| **Root of trust** | Public-key hash in OTP, plus immutable ROM | Attacker swaps the key |
| **Anti-rollback** | Image carries a *signed* security counter, compared with a monotonic counter (OTP fuses, RPMB) | Attacker re-flashes an old, vulnerable, *validly signed* image |
| **Key revocation** | Multiple key slots; fuse to revoke | A single leaked key is permanent |
| **Debug authentication** | JTAG/SWD locked in production, or unlocked by a signed challenge | Debugger bypasses everything |
| **Glitch resistance** | Redundant checks, constant-time compares, flow counters, random delays | One voltage or clock glitch skips the `bne` |

Two rules a reviewer must enforce on every boot stage:

1. **Authenticate what you will execute.** Verify the bytes *after* copying them to the RAM you execute from, or verify in place and execute in place with the region locked. Verifying flash and then copying from flash again is a TOCTOU (time-of-check/time-of-use) window. An attacker with a flash interposer serves good bytes the first time and bad bytes the second.
2. **Fail closed.** Every path that isn't a fully successful verification must end in "don't jump".

### 1.2 Secure boot verifier blueprint (verified)

Header contract: a little-endian 128-byte header. The signature (bytes 64–127) covers bytes 0–63, which **include the payload digest and the security counter**. A self-contained FIPS 180-4 SHA-256 measures the payload. Signature verification is delegated to a certified library through a hook.

`sha256.h`:

```c
/* sha256.h - minimal FIPS 180-4 SHA-256 for boot-time image measurement. */
#ifndef SHA256_H
#define SHA256_H

#include <stddef.h>
#include <stdint.h>

#define SHA256_LEN 32u

typedef struct {
    uint32_t h[8];
    uint64_t total;
    uint8_t  buf[64];
    size_t   fill;
} sha256_ctx_t;

void sha256_init(sha256_ctx_t *c);
void sha256_update(sha256_ctx_t *c, const uint8_t *p, size_t n);
void sha256_final(sha256_ctx_t *c, uint8_t out[SHA256_LEN]);

#endif /* SHA256_H */
```

`sha256.c`:

```c
/* sha256.c - FIPS 180-4 SHA-256, constant-memory, no dynamic allocation.
 * Byte-oriented loads/stores: endian- and alignment-agnostic (Folder 01 file 02). */
#include "sha256.h"

#include <string.h>

static const uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

static uint32_t rotr(uint32_t x, unsigned n) { return (x >> n) | (x << (32u - n)); }

static void compress(uint32_t h[8], const uint8_t blk[64])
{
    uint32_t w[64];
    for (unsigned i = 0u; i < 16u; i++) {
        w[i] = ((uint32_t)blk[4u * i] << 24) | ((uint32_t)blk[4u * i + 1u] << 16) |
               ((uint32_t)blk[4u * i + 2u] << 8) | (uint32_t)blk[4u * i + 3u];
    }
    for (unsigned i = 16u; i < 64u; i++) {
        uint32_t s0 = rotr(w[i - 15u], 7u) ^ rotr(w[i - 15u], 18u) ^ (w[i - 15u] >> 3);
        uint32_t s1 = rotr(w[i - 2u], 17u) ^ rotr(w[i - 2u], 19u) ^ (w[i - 2u] >> 10);
        w[i] = w[i - 16u] + s0 + w[i - 7u] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (unsigned i = 0u; i < 64u; i++) {
        uint32_t t1 = hh + (rotr(e, 6u) ^ rotr(e, 11u) ^ rotr(e, 25u)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint32_t t2 = (rotr(a, 2u) ^ rotr(a, 13u) ^ rotr(a, 22u)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

void sha256_init(sha256_ctx_t *c)
{
    static const uint32_t iv[8] = { 0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u };
    memcpy(c->h, iv, sizeof iv);
    c->total = 0u;
    c->fill = 0u;
}

void sha256_update(sha256_ctx_t *c, const uint8_t *p, size_t n)
{
    c->total += n;
    while (n > 0u) {
        size_t take = 64u - c->fill;
        if (take > n) {
            take = n;
        }
        memcpy(&c->buf[c->fill], p, take);
        c->fill += take;
        p += take;
        n -= take;
        if (c->fill == 64u) {
            compress(c->h, c->buf);
            c->fill = 0u;
        }
    }
}

void sha256_final(sha256_ctx_t *c, uint8_t out[SHA256_LEN])
{
    uint64_t bits = c->total * 8u;
    uint8_t pad = 0x80u;
    sha256_update(c, &pad, 1u);
    pad = 0u;
    while (c->fill != 56u) {
        sha256_update(c, &pad, 1u);
    }
    uint8_t len[8];
    for (unsigned i = 0u; i < 8u; i++) {
        len[i] = (uint8_t)(bits >> (56u - 8u * i));
    }
    sha256_update(c, len, 8u);
    for (unsigned i = 0u; i < 8u; i++) {
        out[4u * i]      = (uint8_t)(c->h[i] >> 24);
        out[4u * i + 1u] = (uint8_t)(c->h[i] >> 16);
        out[4u * i + 2u] = (uint8_t)(c->h[i] >> 8);
        out[4u * i + 3u] = (uint8_t)c->h[i];
    }
}
```

`boot_verify.h`:

```c
/* boot_verify.h - verified-boot stage: parse header, enforce bounds and
 * anti-rollback, hash the image, verify the signature over the header+digest. */
#ifndef BOOT_VERIFY_H
#define BOOT_VERIFY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "sha256.h"

#define IMG_MAGIC        0x4C37424Fu   /* "L7BO" */
#define IMG_HDR_SIZE     128u          /* fixed: signature covers bytes [0, 64) */
#define IMG_SIG_OFFSET   64u
#define IMG_SIG_LEN      64u           /* e.g. ECDSA P-256 (r||s) or Ed25519 */

/* Little-endian on-flash header (parsed byte-wise, never overlaid). */
typedef struct {
    uint32_t magic;
    uint32_t hdr_size;
    uint32_t img_size;           /* payload bytes after the header           */
    uint32_t load_addr;
    uint32_t entry_offset;       /* entry point offset inside the payload    */
    uint32_t security_counter;   /* anti-rollback: must be >= fused minimum  */
    uint32_t key_id;
    uint32_t flags;
    uint8_t  digest[SHA256_LEN]; /* SHA-256 of the payload                   */
    uint8_t  signature[IMG_SIG_LEN];
} img_hdr_t;

typedef enum {
    BOOT_OK = 0,
    BOOT_ERR_SHORT,
    BOOT_ERR_MAGIC,
    BOOT_ERR_HDR,
    BOOT_ERR_BOUNDS,
    BOOT_ERR_ROLLBACK,
    BOOT_ERR_DIGEST,
    BOOT_ERR_SIGNATURE
} boot_status_t;

/* Platform hooks: signature verification belongs to a certified crypto library
 * (ROM API, PSA Crypto, mbedTLS/TF-PSA-Crypto) - never hand-rolled. */
typedef struct {
    bool (*verify_sig)(uint32_t key_id, const uint8_t *msg, size_t msg_len,
                       const uint8_t sig[IMG_SIG_LEN]);
    uint32_t min_security_counter;   /* read from OTP / monotonic counter */
    size_t   slot_size;              /* flash slot capacity               */
} boot_policy_t;

boot_status_t boot_verify_image(const uint8_t *slot, size_t slot_len,
                                const boot_policy_t *pol, img_hdr_t *out);

#endif /* BOOT_VERIFY_H */
```

`boot_verify.c`:

```c
/* boot_verify.c - see boot_verify.h. Fail-closed: every path that is not a
 * complete success returns an error and the caller must not jump. */
#include "boot_verify.h"

#include <string.h>

static uint32_t ld_le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* Constant-time compare: no early exit, so timing does not leak how many
 * leading digest bytes matched (glitch/timing oracles on boot ROMs). */
static bool ct_equal(const uint8_t *a, const uint8_t *b, size_t n)
{
    volatile uint8_t diff = 0u;
    for (size_t i = 0u; i < n; i++) {
        diff = (uint8_t)(diff | (uint8_t)(a[i] ^ b[i]));
    }
    return diff == 0u;
}

boot_status_t boot_verify_image(const uint8_t *slot, size_t slot_len,
                                const boot_policy_t *pol, img_hdr_t *out)
{
    img_hdr_t h;

    if ((slot == NULL) || (pol == NULL) || (out == NULL) || (slot_len < IMG_HDR_SIZE)) {
        return BOOT_ERR_SHORT;
    }
    h.magic            = ld_le32(&slot[0]);
    h.hdr_size         = ld_le32(&slot[4]);
    h.img_size         = ld_le32(&slot[8]);
    h.load_addr        = ld_le32(&slot[12]);
    h.entry_offset     = ld_le32(&slot[16]);
    h.security_counter = ld_le32(&slot[20]);
    h.key_id           = ld_le32(&slot[24]);
    h.flags            = ld_le32(&slot[28]);
    memcpy(h.digest, &slot[32], SHA256_LEN);
    memcpy(h.signature, &slot[IMG_SIG_OFFSET], IMG_SIG_LEN);

    if (h.magic != IMG_MAGIC) {
        return BOOT_ERR_MAGIC;
    }
    if (h.hdr_size != IMG_HDR_SIZE) {
        return BOOT_ERR_HDR;
    }
    /* Bounds BEFORE hashing: 64-bit sum cannot wrap; image must fit the slot. */
    if (((uint64_t)h.hdr_size + h.img_size > slot_len) ||
        ((uint64_t)h.hdr_size + h.img_size > pol->slot_size) ||
        (h.entry_offset >= h.img_size) || ((h.entry_offset & 1u) == 0u)) {  /* Thumb bit */
        return BOOT_ERR_BOUNDS;
    }
    /* 1. Authenticate the header (which contains the digest) - signature first,
     *    so no unauthenticated field drives anything beyond the bounds above. */
    if ((pol->verify_sig == NULL) ||
        !pol->verify_sig(h.key_id, slot, IMG_SIG_OFFSET, h.signature)) {
        return BOOT_ERR_SIGNATURE;
    }
    /* 2. Anti-rollback against the fused/monotonic minimum. */
    if (h.security_counter < pol->min_security_counter) {
        return BOOT_ERR_ROLLBACK;
    }
    /* 3. Measure the payload and compare in constant time. */
    sha256_ctx_t c;
    uint8_t d[SHA256_LEN];
    sha256_init(&c);
    sha256_update(&c, &slot[IMG_HDR_SIZE], h.img_size);
    sha256_final(&c, d);
    if (!ct_equal(d, h.digest, SHA256_LEN)) {
        return BOOT_ERR_DIGEST;
    }
    *out = h;
    return BOOT_OK;
}

#ifdef BOOT_SELFTEST
#include <stdio.h>

static void hex(const char *tag, const uint8_t *p, size_t n)
{
    printf("%s", tag);
    for (size_t i = 0u; i < n; i++) { printf("%02x", p[i]); }
    printf("\n");
}

static void put_le32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

/* TEST ONLY: accepts a "signature" equal to SHA-256(header[0..64)) in its first
 * 32 bytes. Production plugs in ECDSA/Ed25519 from a certified library. */
static bool test_verify_sig(uint32_t key_id, const uint8_t *msg, size_t len, const uint8_t sig[IMG_SIG_LEN])
{
    sha256_ctx_t c;
    uint8_t d[SHA256_LEN];
    if (key_id != 1u) { return false; }
    sha256_init(&c); sha256_update(&c, msg, len); sha256_final(&c, d);
    return memcmp(d, sig, SHA256_LEN) == 0;
}

static uint8_t slot[4096];

static void build_image(uint32_t counter, uint32_t img_size)
{
    sha256_ctx_t c;
    memset(slot, 0xFF, sizeof slot);                 /* erased flash */
    for (uint32_t i = 0u; i < img_size; i++) { slot[IMG_HDR_SIZE + i] = (uint8_t)(i * 7u + 3u); }
    put_le32(&slot[0], IMG_MAGIC);   put_le32(&slot[4], IMG_HDR_SIZE);
    put_le32(&slot[8], img_size);    put_le32(&slot[12], 0x08020000u);
    put_le32(&slot[16], 0x101u);     put_le32(&slot[20], counter);
    put_le32(&slot[24], 1u);         put_le32(&slot[28], 0u);
    sha256_init(&c); sha256_update(&c, &slot[IMG_HDR_SIZE], img_size); sha256_final(&c, &slot[32]);
    sha256_init(&c); sha256_update(&c, slot, IMG_SIG_OFFSET); sha256_final(&c, &slot[IMG_SIG_OFFSET]);
}

int main(void)
{
    static const char *const abc = "abc";
    static const char *const two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    sha256_ctx_t c;
    uint8_t d[SHA256_LEN];
    img_hdr_t h;
    const boot_policy_t pol = { test_verify_sig, 5u, sizeof slot };

    sha256_init(&c); sha256_final(&c, d);                                   hex("sha256(\"\")    = ", d, 32u);
    sha256_init(&c); sha256_update(&c, (const uint8_t *)abc, 3u); sha256_final(&c, d);  hex("sha256(\"abc\") = ", d, 32u);
    sha256_init(&c); sha256_update(&c, (const uint8_t *)two, 56u); sha256_final(&c, d); hex("sha256(448bit) = ", d, 32u);

    build_image(7u, 1000u);  printf("good image          -> %d\n", (int)boot_verify_image(slot, sizeof slot, &pol, &h));
    slot[IMG_HDR_SIZE + 500u] ^= 0x01u;
                             printf("1 payload bit flip  -> %d\n", (int)boot_verify_image(slot, sizeof slot, &pol, &h));
    build_image(7u, 1000u);  slot[20] = 9u;   /* bump counter without re-signing */
                             printf("forged counter      -> %d\n", (int)boot_verify_image(slot, sizeof slot, &pol, &h));
    build_image(4u, 1000u);  printf("old (counter 4 < 5) -> %d\n", (int)boot_verify_image(slot, sizeof slot, &pol, &h));
    build_image(7u, 1000u);  put_le32(&slot[8], 0xFFFFFF80u);
                             printf("huge img_size       -> %d\n", (int)boot_verify_image(slot, sizeof slot, &pol, &h));
    return 0;
}
#endif
```

**Build evidence (verified):** both files compile with zero diagnostics under the full warning set (`-std=c11`) on Cortex-M7, M33, M0+, AArch64 and x86-64.

**Self-test output (verified, native).** The first three lines are the FIPS 180-4 test vectors (empty, `"abc"`, and the 448-bit two-block message). The status codes are `BOOT_OK`=0, `BOUNDS`=4, `ROLLBACK`=5, `DIGEST`=6, `SIGNATURE`=7.

```text
sha256("")    = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
sha256(448bit) = 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
good image          -> 0
1 payload bit flip  -> 6
forged counter      -> 7
old (counter 4 < 5) -> 5
huge img_size       -> 4
```

What each rejection proves about the design:

- **1 payload bit flip → `DIGEST` (6).** The measured hash differs, and the constant-time compare catches it.
- **Forged counter → `SIGNATURE` (7).** The counter is *inside the signed region*, so bumping it invalidates the signature. If the counter were outside the signed bytes, an attacker could set any counter on an old image.
- **Counter 4 < fused minimum 5 → `ROLLBACK` (5),** even though that image is validly signed.
- **`img_size = 0xFFFFFF80` → `BOUNDS` (4).** The size check uses 64-bit arithmetic *before* any hashing, so no read ever goes past the slot.
- **Order of checks:**
  1. structural bounds;
  2. **signature over the header;**
  3. rollback (now trusting a signed field);
  4. digest.

  Unauthenticated fields influence nothing except the bounds check.

The production checklist on top of this:
- the signature is ECDSA-P256/Ed25519/LMS via a certified library (PSA Crypto, a ROM API);
- the public-key hash comes from OTP and is compared in constant time;
- the digest compare and the final "jump" decision are duplicated against glitches, with a flow-integrity counter checked before the jump;
- the payload is hashed *from the RAM it will execute from* (rule 1).

### 1.3 TrustZone: A-profile vs M-profile

| | TrustZone-A (Cortex-A, AArch64) | TrustZone-M (ARMv8-M: Cortex-M23/M33/M55/M85) |
|---|---|---|
| Security state switch | Exception to **EL3** (Secure Monitor, TF-A BL31) via `SMC`; `SCR_EL3.NS` | **Function call** into a Secure Gateway (`SG`) in Non-secure-Callable (NSC) memory; return with `BXNS`; S→NS calls with `BLXNS` |
| Who decides "secure" for an address | Page tables (NS bit), **TZASC** (DRAM), **TZPC**/firewalls (peripherals); the AXI `AxPROT[1]` NS signal travels on every transaction | **SAU** (programmable, up to 8 regions) combined with the **IDAU** (fixed by the SoC). The `TT`/`TTA` instructions query it |
| Banked state | Per-EL system registers; Secure/Non-secure EL1 | MSP/PSP, `MSPLIM`/`PSPLIM`, `VTOR`, MPU, SysTick, `CONTROL`, `PRIMASK`/`BASEPRI`/`FAULTMASK` are **banked per security state** |
| Typical software | TF-A (EL3), OP-TEE (S-EL1), Hafnium (S-EL2) | TF-M (Secure Processing Environment), vendor secure firmware |
| Faults | Synchronous external aborts / permission faults on NS→S accesses | **SecureFault** (`SFSR` at `0xE000EDE4`, `SFAR` at `0xE000EDE8`) |

#### 1.3.1 Compiler-side CMSE (verified)

```c
#include <arm_cmse.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef void (*ns_callback_t)(uint32_t) __attribute__((cmse_nonsecure_call));

static uint32_t s_counter;
static const uint8_t s_device_key[16] = { 0x2Bu, 0x7Eu, 0x15u, 0x16u };

int32_t secure_bump(uint32_t token) __attribute__((cmse_nonsecure_entry));
int32_t secure_bump(uint32_t token)
{
    if (token != 0x1234u) {
        return -1;
    }
    s_counter++;
    return (int32_t)s_counter;
}

int32_t secure_read_id(uint8_t *ns_dst, size_t n) __attribute__((cmse_nonsecure_entry));
int32_t secure_read_id(uint8_t *ns_dst, size_t n)
{
    if (n > 4u) {
        return -1;
    }
    /* Never trust a Non-secure pointer: it may point INTO Secure memory. */
    uint8_t *dst = cmse_check_address_range(ns_dst, n, CMSE_NONSECURE | CMSE_MPU_READWRITE);
    if (dst == NULL) {
        return -2;
    }
    memcpy(dst, s_device_key, n);          /* first bytes only: a public ID, not the key */
    return (int32_t)n;
}

void secure_notify(ns_callback_t cb);
void secure_notify(ns_callback_t cb)
{
    cb(s_counter);
}
```

**Codegen (verified — Clang 21.1.0, `-O2 -mcmse`, Cortex-M33):**

```asm
__acle_se_secure_bump:
secure_bump:
	movw	r1, #4660
	cmp	r0, r1
	bne	.LBB0_2
	movw	r1, :lower16:s_counter
	movt	r1, :upper16:s_counter
	ldr	r0, [r1]
	adds	r0, #1
	str	r0, [r1]
	b	.LBB0_3
.LBB0_2:
	mov.w	r0, #-1
.LBB0_3:
	mrs	r12, control
	tst.w	r12, #8
	beq	.LBB0_5
	vmrs	r12, fpscr
	bic	r12, r12, #159
	bic	r12, r12, #4026531840
	vmov	d0, lr, lr
	vmov	d1, lr, lr
	vmov	d2, lr, lr
	vmov	d3, lr, lr
	vmov	d4, lr, lr
	vmov	d5, lr, lr
	vmov	d6, lr, lr
	vmov	d7, lr, lr
	vmsr	fpscr, r12
.LBB0_5:
	mov	r1, lr
	mov	r2, lr
	mov	r3, lr
	mov	r12, lr
	msr	apsr_nzcvqg, lr
	bxns	lr
__acle_se_secure_read_id:
secure_read_id:
	push	{r4, lr}
	cmp	r1, #4
	bls	.LBB1_2
	mov.w	r4, #-1
	b	.LBB1_4
.LBB1_2:
	mov	r4, r1
	add	r1, r0
	subs	r1, #1
	cmp	r1, r0
	bhs	.LBB1_7
.LBB1_3:
	mvn	r4, #1
.LBB1_4:
	mov	r0, r4
	pop.w	{r4, lr}
	mrs	r12, control
	tst.w	r12, #8
	beq	.LBB1_6
	vmrs	r12, fpscr
	bic	r12, r12, #159
	bic	r12, r12, #4026531840
	vmov	d0, lr, lr
	vmov	d1, lr, lr
	vmov	d2, lr, lr
	vmov	d3, lr, lr
	vmov	d4, lr, lr
	vmov	d5, lr, lr
	vmov	d6, lr, lr
	vmov	d7, lr, lr
	vmsr	fpscr, r12
.LBB1_6:
	mov	r1, lr
	mov	r2, lr
	mov	r3, lr
	mov	r12, lr
	msr	apsr_nzcvqg, lr
	bxns	lr
.LBB1_7:
	eor.w	r2, r1, r0
	cmp	r2, #31
	tta	r2, r0
	bhi	.LBB1_10
	lsls	r1, r2, #10
	bpl	.LBB1_3
	cbnz	r0, .LBB1_12
	b	.LBB1_3
.LBB1_10:
	tta	r1, r1
	cmp	r2, r1
	bne	.LBB1_3
	lsls	r1, r2, #10
	and.w	r0, r0, r1, asr #31
	cmp	r0, #0
	beq	.LBB1_3
.LBB1_12:
	movw	r1, :lower16:s_device_key
	movt	r1, :upper16:s_device_key
	mov	r2, r4
	bl	__aeabi_memcpy
	b	.LBB1_4
secure_notify:
	push	{r7, lr}
	movw	r1, :lower16:s_counter
	movt	r1, :upper16:s_counter
	ldr	r1, [r1]
	mov	r2, r0
	mov	r0, r1
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11}
	bic	r2, r2, #1
	sub	sp, #136
	vlstm	sp, {d0 - d15}
	mov	r1, r2
	mov	r3, r2
	mov	r4, r2
	mov	r5, r2
	mov	r6, r2
	mov	r7, r2
	mov	r8, r2
	mov	r9, r2
	mov	r10, r2
	mov	r11, r2
	mov	r12, r2
	msr	apsr_nzcvqg, r2
	blxns	r2
	mrs	r12, control
	tst.w	r12, #8
	it	ne
	vmovne.f32	s0, s0
	vlldm	sp, {d0 - d15}
	add	sp, #136
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11}
	pop	{r7, pc}
s_device_key:
	.byte	43
	.byte	126
	.byte	21
	.byte	22
	.zero	12
```

Everything the CMSE contract requires is visible in the listing:

- **`__acle_se_secure_bump:` / `secure_bump:`** are two symbols at one address. The linker builds the `SG` veneer for the *public* name and points it at the `__acle_se_` *implementation* name.
- **Register scrubbing before `bxns lr`.** Secure state must not leak through registers:
  - `r1`–`r3` and `r12` are overwritten with `lr` (a value the caller already knows);
  - flags are cleared via `msr apsr_nzcvqg, lr`;
  - if Secure FP was active (`CONTROL.SFPA`, the `tst #8`), `d0`–`d7` are overwritten and FPSCR's cumulative flags are cleared.
  
  `r0` carries the return value. The callee-saved `r4`–`r11` were preserved by normal AAPCS rules, so they hold the caller's own values.
- **`bxns lr`** returns to Non-secure state.
- **`cmse_check_address_range`** became **`tta`** (Test Target Alternate domain) instructions. The core reports the SAU/IDAU/MPU attributes the *Non-secure* side would see for both ends of the buffer, and the code requires the whole range to be NS-accessible and in one region. **Without this check, a Non-secure caller passes a pointer into Secure memory, and the Secure function writes its own secrets wherever the attacker asks.** This is the classic TrustZone-M "confused deputy" bug.
- **`secure_notify` → `blxns r2`:** calling *out* to Non-secure code saves all callee-saved registers (`push.w {r4–r11}`), lazily saves Secure FP state (`vlstm`), scrubs every register, clears bit 0 of the target address (`bic r2, r2, #1`, which tells `BLXNS` to switch to NS), and restores (`vlldm`, `pop`) afterwards.

#### 1.3.2 Linker-side: SG veneers and the import library (verified)

`secure.ld`:

```ld
ENTRY(Reset_Handler)
MEMORY
{
  S_FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 0x3F000   /* Secure code (alias of flash with addr bit 28 set) */
  NSC     (rx)  : ORIGIN = 0x1003F000, LENGTH = 0x1000    /* Non-secure-callable: SG veneers only           */
  S_SRAM  (rwx) : ORIGIN = 0x30000000, LENGTH = 0x10000
}
SECTIONS
{
  .text : { *(.text .text.*) *(.rodata .rodata.*) } > S_FLASH
  .gnu.sgstubs ORIGIN(NSC) : { *(.gnu.sgstubs*) } > NSC
  .data : { *(.data .data.*) } > S_SRAM AT > S_FLASH
  .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) } > S_SRAM
}
```

```text
ld.lld -T secure.ld --cmse-implib --out-implib=secure_veneers.o -o secure.elf secure.o s_rt.o
```

**Output (verified: sections, veneer disassembly, import-library symbols):**

```text
  [ 1] .text             PROGBITS        10000000 010000 0001ec 00 AXM  0   0  4
  [ 2] .gnu.sgstubs      PROGBITS        1003f000 01f000 000010 08  AX  0   0 32
.gnu.sgstubs:
  1003f000:  sg       
  1003f004:  b.w      #0x10000000
  1003f008:  sg       
  1003f00c:  b.w      #0x10000064
-- import library (secure_veneers.o) symbols:
     1: 1003f001     8 FUNC    GLOBAL DEFAULT  ABS secure_bump
     2: 1003f009     8 FUNC    GLOBAL DEFAULT  ABS secure_read_id
```

- `.gnu.sgstubs` is placed at `0x1003F000`, the region the SAU/IDAU marks **NSC**. Each veneer is `sg` (Secure Gateway, the *only* legal first instruction of an NS→S call target) followed by `b.w` to the `__acle_se_` implementation.
- Only the two `cmse_nonsecure_entry` functions got veneers. `secure_notify` is not callable from Non-secure state.
- The **import library** (`secure_veneers.o`) contains *only* absolute symbols at the veneer addresses (`0x1003F001`: Thumb bit set). The Non-secure image links against it and never sees Secure code addresses.
- LLD needs an explicit address for `.gnu.sgstubs`. The first attempt (`ALIGN(32)` only) failed with `no address assigned to the veneers output section .gnu.sgstubs` (verified). Veneer addresses must be **stable across Secure-image releases**, or every Non-secure image breaks: `--in-implib=old_veneers.o` keeps them fixed (⚠ verify the LLD flag set for your release; GNU ld has equivalent options).
- **Why NSC must contain nothing but veneers.** Any word in NSC memory that happens to encode `SG` is a valid entry point. Hence a dedicated NSC region containing only linker-generated stubs.

### 1.4 The MPU: PMSAv7 vs PMSAv8

| | PMSAv7 (Cortex-M3/M4/M7) | PMSAv8 (Cortex-M23/M33/M55/M85) |
|---|---|---|
| Region shape | **Power-of-two size ≥ 32 B, base aligned to size**, 8 sub-region disable bits | Any **multiple of 32 B**, base and limit 32-B aligned |
| Overlap | Allowed; the **highest-numbered** region wins | **Forbidden**: an address hitting two regions faults |
| Attributes | TEX/C/B/S bits inline in `RASR` | Index into `MAIR0`/`MAIR1` (8 attribute bytes), as on A-profile |
| Registers | `RBAR` (ADDR, VALID, REGION) + `RASR` (XN, AP[2:0], TEX, S, C, B, SRD, SIZE, EN) | `RBAR` (BASE, SH, AP[1:0], XN) + `RLAR` (LIMIT, [PXN on v8.1-M], AttrIndx, EN) |
| No-access region | `AP = 000` | No "no access" AP: leave a hole (with `PRIVDEFENA = 0`) or use the background map |
| Security | n/a | One MPU per security state (`MPU_NS` alias at `0xE002ED90`) |

`mpu.h`:

```c
/* mpu.h - ARMv7-M (PMSAv7) and ARMv8-M (PMSAv8) MPU region encoders.
 * Encoding is pure (host-testable); programming takes a register-block pointer. */
#ifndef MPU_H
#define MPU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    MPU_OK = 0,
    MPU_ERR_SIZE,        /* v7: not a power of two >= 32; v8: not a multiple of 32 */
    MPU_ERR_ALIGN,       /* v7: base not aligned to size; v8: base not 32-aligned */
    MPU_ERR_REGION,      /* region number out of range                           */
    MPU_ERR_OVERLAP      /* v8: regions must not overlap                         */
} mpu_status_t;

/* Memory types common to both encoders. */
typedef enum {
    MEM_NORMAL_WB_WA = 0,   /* cached code and data                       */
    MEM_NORMAL_NC,          /* DMA buffers / descriptors (no maintenance) */
    MEM_DEVICE,             /* peripherals: Device-nGnRE / shareable dev  */
    MEM_STRONGLY_ORDERED    /* Device-nGnRnE                              */
} mem_type_t;

typedef enum {
    AP_NONE = 0,            /* no access (guard regions)                  */
    AP_PRIV_RW,             /* privileged RW, unprivileged no access      */
    AP_FULL_RW,             /* RW for everyone                            */
    AP_PRIV_RO,             /* privileged RO                              */
    AP_FULL_RO              /* RO for everyone                            */
} access_t;

typedef struct {
    uint32_t   base;
    uint32_t   size;        /* bytes */
    mem_type_t type;
    access_t   access;
    bool       exec;        /* false -> XN */
    bool       shareable;   /* Normal memory shared with another master   */
} mpu_region_t;

/* ---------------- PMSAv7 (Cortex-M3/M4/M7) ---------------- */
#define MPU_V7_RBAR_VALID    (1u << 4)
#define MPU_V7_RASR_ENABLE   (1u << 0)
#define MPU_V7_RASR_XN       (1u << 28)
mpu_status_t mpu_v7_encode(unsigned region, const mpu_region_t *r,
                           uint32_t *rbar, uint32_t *rasr);

/* ---------------- PMSAv8 (Cortex-M23/M33/M55/M85) ---------------- */
#define MPU_V8_RLAR_ENABLE   (1u << 0)
/* MAIR attribute indices used by mpu_v8_encode (program MAIR0 with MPU_V8_MAIR0). */
#define MPU_V8_ATTR_WB       0u   /* 0xFF Normal, inner/outer WB non-transient R/W-allocate */
#define MPU_V8_ATTR_NC       1u   /* 0x44 Normal, inner/outer non-cacheable                 */
#define MPU_V8_ATTR_DEV      2u   /* 0x04 Device-nGnRE                                      */
#define MPU_V8_ATTR_SO       3u   /* 0x00 Device-nGnRnE                                     */
#define MPU_V8_MAIR0         0x000444FFu
mpu_status_t mpu_v8_encode(const mpu_region_t *r, uint32_t *rbar, uint32_t *rlar);
mpu_status_t mpu_v8_check_overlap(const mpu_region_t *r, size_t n);

/* ---------------- Programming (shared register block layout) ---------------- */
typedef struct {
    const volatile uint32_t TYPE;   /* 0xE000ED90 */
    volatile uint32_t CTRL;         /* 0xE000ED94 */
    volatile uint32_t RNR;          /* 0xE000ED98 */
    volatile uint32_t RBAR;         /* 0xE000ED9C */
    volatile uint32_t RASR_RLAR;    /* 0xE000EDA0: RASR on v7-M, RLAR on v8-M */
    volatile uint32_t ALIAS[6];     /* 0xE000EDA4..B8 alias registers */
    uint32_t          RESERVED[1];  /* 0xE000EDBC */
    volatile uint32_t MAIR0;        /* 0xE000EDC0 (v8-M only) */
    volatile uint32_t MAIR1;        /* 0xE000EDC4 (v8-M only) */
} mpu_regs_t;

#define MPU_CTRL_ENABLE      (1u << 0)
#define MPU_CTRL_HFNMIENA    (1u << 1)
#define MPU_CTRL_PRIVDEFENA  (1u << 2)

typedef void (*barrier_fn_t)(void);

/* Disable, program all regions, enable with PRIVDEFENA, then DSB+ISB via the
 * supplied barrier (cpu_dsb_isb on target, a no-op in host tests). */
mpu_status_t mpu_v7_program(mpu_regs_t *mpu, const mpu_region_t *r, size_t n,
                            barrier_fn_t dsb_isb);

#endif /* MPU_H */
```

`mpu.c`:

```c
/* mpu.c - see mpu.h. Field positions: ARMv7-M ARM B3.5, ARMv8-M ARM B3.5/D1. */
#include "mpu.h"

/* ---- PMSAv7 ---- */
static uint32_t v7_ap(access_t a)
{
    switch (a) {
    case AP_PRIV_RW: return 1u;   /* 001 */
    case AP_FULL_RW: return 3u;   /* 011 */
    case AP_PRIV_RO: return 5u;   /* 101 */
    case AP_FULL_RO: return 6u;   /* 110 */
    case AP_NONE:
    default:         return 0u;   /* 000 */
    }
}

/* TEX[21:19] S[18] C[17] B[16] */
static uint32_t v7_attr(mem_type_t t, bool shareable)
{
    uint32_t tex, c, b, s = shareable ? 1u : 0u;
    switch (t) {
    case MEM_NORMAL_WB_WA:     tex = 1u; c = 1u; b = 1u; break;
    case MEM_NORMAL_NC:        tex = 1u; c = 0u; b = 0u; break;
    case MEM_DEVICE:           tex = 0u; c = 0u; b = 1u; s = 1u; break; /* shareable device */
    case MEM_STRONGLY_ORDERED:
    default:                   tex = 0u; c = 0u; b = 0u; s = 1u; break;
    }
    return (tex << 19) | (s << 18) | (c << 17) | (b << 16);
}

mpu_status_t mpu_v7_encode(unsigned region, const mpu_region_t *r,
                           uint32_t *rbar, uint32_t *rasr)
{
    if (region > 15u) {
        return MPU_ERR_REGION;
    }
    /* Size must be a power of two, 32 B .. 4 GB (size 0 means 4 GB here). */
    uint32_t log2 = 32u;
    if (r->size != 0u) {
        if ((r->size < 32u) || ((r->size & (r->size - 1u)) != 0u)) {
            return MPU_ERR_SIZE;
        }
        log2 = (uint32_t)__builtin_ctz(r->size);
        /* PMSAv7: the base must be aligned to the region size. */
        if ((r->base & (r->size - 1u)) != 0u) {
            return MPU_ERR_ALIGN;
        }
    }
    *rbar = (r->base & ~0x1Fu) | MPU_V7_RBAR_VALID | (uint32_t)region;
    *rasr = (r->exec ? 0u : MPU_V7_RASR_XN) |
            (v7_ap(r->access) << 24) |
            v7_attr(r->type, r->shareable) |
            ((log2 - 1u) << 1) |              /* SIZE field: 2^(SIZE+1) bytes */
            MPU_V7_RASR_ENABLE;
    return MPU_OK;
}

/* ---- PMSAv8 ---- */
static uint32_t v8_ap(access_t a)
{
    switch (a) {
    case AP_FULL_RW: return 1u;   /* 01: RW any privilege   */
    case AP_PRIV_RO: return 2u;   /* 10: RO privileged      */
    case AP_FULL_RO: return 3u;   /* 11: RO any privilege   */
    case AP_PRIV_RW:              /* 00: RW privileged only */
    case AP_NONE:                 /* PMSAv8 has no "no access": leave the region disabled */
    default:         return 0u;
    }
}

mpu_status_t mpu_v8_encode(const mpu_region_t *r, uint32_t *rbar, uint32_t *rlar)
{
    if ((r->size == 0u) || ((r->size & 0x1Fu) != 0u)) {
        return MPU_ERR_SIZE;
    }
    if ((r->base & 0x1Fu) != 0u) {
        return MPU_ERR_ALIGN;
    }
    uint32_t attr;
    switch (r->type) {
    case MEM_NORMAL_WB_WA: attr = MPU_V8_ATTR_WB;  break;
    case MEM_NORMAL_NC:    attr = MPU_V8_ATTR_NC;  break;
    case MEM_DEVICE:       attr = MPU_V8_ATTR_DEV; break;
    case MEM_STRONGLY_ORDERED:
    default:               attr = MPU_V8_ATTR_SO;  break;
    }
    uint32_t sh = (r->shareable && (r->type <= MEM_NORMAL_NC)) ? 3u : 0u; /* inner shareable */
    uint32_t limit = r->base + r->size - 1u;                             /* inclusive        */
    *rbar = r->base | (sh << 3) | (v8_ap(r->access) << 1) | (r->exec ? 0u : 1u);
    *rlar = (limit & ~0x1Fu) | (attr << 1) | ((r->access == AP_NONE) ? 0u : MPU_V8_RLAR_ENABLE);
    return MPU_OK;
}

mpu_status_t mpu_v8_check_overlap(const mpu_region_t *r, size_t n)
{
    for (size_t i = 0u; i < n; i++) {
        for (size_t j = i + 1u; j < n; j++) {
            uint64_t a0 = r[i].base, a1 = (uint64_t)r[i].base + r[i].size;
            uint64_t b0 = r[j].base, b1 = (uint64_t)r[j].base + r[j].size;
            if ((a0 < b1) && (b0 < a1)) {
                return MPU_ERR_OVERLAP;   /* PMSAv8: an address hitting 2 regions faults */
            }
        }
    }
    return MPU_OK;
}

mpu_status_t mpu_v7_program(mpu_regs_t *mpu, const mpu_region_t *r, size_t n,
                            barrier_fn_t dsb_isb)
{
    uint32_t rbar[16], rasr[16];

    if (n > 16u) {
        return MPU_ERR_REGION;
    }
    for (size_t i = 0u; i < n; i++) {           /* validate everything first */
        mpu_status_t st = mpu_v7_encode((unsigned)i, &r[i], &rbar[i], &rasr[i]);
        if (st != MPU_OK) {
            return st;
        }
    }
    dsb_isb();                                  /* complete accesses under the old map */
    mpu->CTRL = 0u;
    for (size_t i = 0u; i < n; i++) {
        mpu->RBAR = rbar[i];                    /* VALID=1: RBAR also selects the region */
        mpu->RASR_RLAR = rasr[i];
    }
    for (size_t i = n; i < 16u; i++) {          /* disable leftovers from a previous map */
        mpu->RNR = (uint32_t)i;
        mpu->RASR_RLAR = 0u;
    }
    mpu->CTRL = MPU_CTRL_ENABLE | MPU_CTRL_PRIVDEFENA;
    dsb_isb();                                  /* new map in force for the next fetch */
    return MPU_OK;
}

#ifdef MPU_SELFTEST
#include <stdio.h>

static void no_barrier(void) { }

static const char *st_name(mpu_status_t s)
{
    static const char *const names[] = { "OK", "ERR_SIZE", "ERR_ALIGN", "ERR_REGION", "ERR_OVERLAP" };
    return names[s];
}

int main(void)
{
    /* STM32H7-style map: ITCM, flash, DTCM, AXI SRAM, D2 SRAM for DMA, peripherals. */
    const mpu_region_t map[] = {
        { 0x00000000u, 64u * 1024u,   MEM_NORMAL_WB_WA, AP_PRIV_RO, true,  false }, /* ITCM code    */
        { 0x08000000u, 2u << 20,      MEM_NORMAL_WB_WA, AP_PRIV_RO, true,  false }, /* flash        */
        { 0x20000000u, 128u * 1024u,  MEM_NORMAL_WB_WA, AP_PRIV_RW, false, false }, /* DTCM data    */
        { 0x24000000u, 512u * 1024u,  MEM_NORMAL_WB_WA, AP_PRIV_RW, false, false }, /* AXI SRAM     */
        { 0x30000000u, 128u * 1024u,  MEM_NORMAL_NC,    AP_PRIV_RW, false, true  }, /* DMA buffers  */
        { 0x40000000u, 512u << 20,    MEM_DEVICE,       AP_PRIV_RW, false, true  }, /* peripherals  */
        { 0x2001F000u, 32u,           MEM_NORMAL_WB_WA, AP_NONE,    false, false }, /* stack guard  */
    };
    mpu_regs_t fake = { 0 };
    uint32_t rbar, rasr, rlar;

    printf("PMSAv7 encodings:\n");
    for (unsigned i = 0u; i < sizeof map / sizeof map[0]; i++) {
        mpu_status_t st = mpu_v7_encode(i, &map[i], &rbar, &rasr);
        printf("  r%u base=0x%08X size=0x%08X -> %s RBAR=0x%08X RASR=0x%08X\n", i,
               (unsigned)map[i].base, (unsigned)map[i].size, st_name(st),
               (unsigned)rbar, (unsigned)rasr);
    }
    const mpu_region_t bad_align = { 0x24010000u, 128u * 1024u, MEM_NORMAL_NC, AP_PRIV_RW, false, true };
    const mpu_region_t bad_size  = { 0x30000000u, 96u * 1024u,  MEM_NORMAL_NC, AP_PRIV_RW, false, true };
    printf("  128K region at 0x24010000 -> %s\n", st_name(mpu_v7_encode(7u, &bad_align, &rbar, &rasr)));
    printf("  96K region (not 2^n)      -> %s\n", st_name(mpu_v7_encode(7u, &bad_size, &rbar, &rasr)));

    printf("PMSAv8 encodings (MAIR0=0x%08X):\n", (unsigned)MPU_V8_MAIR0);
    for (unsigned i = 0u; i < 6u; i++) {
        mpu_status_t st = mpu_v8_encode(&map[i], &rbar, &rlar);
        printf("  r%u -> %s RBAR=0x%08X RLAR=0x%08X\n", i, st_name(st), (unsigned)rbar, (unsigned)rlar);
    }
    const mpu_region_t v8_96k = { 0x30000000u, 96u * 1024u, MEM_NORMAL_NC, AP_PRIV_RW, false, true };
    printf("  96K region on PMSAv8      -> %s (any multiple of 32 B is legal)\n",
           st_name(mpu_v8_encode(&v8_96k, &rbar, &rlar)));
    printf("  overlap check (map incl. guard inside DTCM) -> %s\n",
           st_name(mpu_v8_check_overlap(map, sizeof map / sizeof map[0])));

    mpu_status_t st = mpu_v7_program(&fake, map, sizeof map / sizeof map[0], no_barrier);
    printf("program: %s CTRL=0x%08X last RBAR=0x%08X\n", st_name(st), (unsigned)fake.CTRL, (unsigned)fake.RBAR);
    return 0;
}
#endif
```

**Self-test output (verified, native, STM32H7-style map; zero diagnostics on Cortex-M7/M33/M0+, AArch64 and x86-64):**

```text
PMSAv7 encodings:
  r0 base=0x00000000 size=0x00010000 -> OK RBAR=0x00000010 RASR=0x050B001F
  r1 base=0x08000000 size=0x00200000 -> OK RBAR=0x08000011 RASR=0x050B0029
  r2 base=0x20000000 size=0x00020000 -> OK RBAR=0x20000012 RASR=0x110B0021
  r3 base=0x24000000 size=0x00080000 -> OK RBAR=0x24000013 RASR=0x110B0025
  r4 base=0x30000000 size=0x00020000 -> OK RBAR=0x30000014 RASR=0x110C0021
  r5 base=0x40000000 size=0x20000000 -> OK RBAR=0x40000015 RASR=0x11050039
  r6 base=0x2001F000 size=0x00000020 -> OK RBAR=0x2001F016 RASR=0x100B0009
  128K region at 0x24010000 -> ERR_ALIGN
  96K region (not 2^n)      -> ERR_SIZE
PMSAv8 encodings (MAIR0=0x000444FF):
  r0 -> OK RBAR=0x00000004 RLAR=0x0000FFE1
  r1 -> OK RBAR=0x08000004 RLAR=0x081FFFE1
  r2 -> OK RBAR=0x20000001 RLAR=0x2001FFE1
  r3 -> OK RBAR=0x24000001 RLAR=0x2407FFE1
  r4 -> OK RBAR=0x30000019 RLAR=0x3001FFE3
  r5 -> OK RBAR=0x40000001 RLAR=0x5FFFFFE5
  96K region on PMSAv8      -> OK (any multiple of 32 B is legal)
  overlap check (map incl. guard inside DTCM) -> ERR_OVERLAP
program: OK CTRL=0x00000005 last RBAR=0x2001F016
```

Decoding three of them by hand, which is what you do when reviewing a vendor BSP:

- **r0 ITCM, `RASR = 0x050B001F`:** XN = 0 (executable); `AP = 101` (privileged RO); `TEX = 001, C = 1, B = 1` (Normal, write-back write-allocate); `SIZE = 15` → 2^(15+1) = 64 KB; `EN = 1`.
- **r4 DMA, `RASR = 0x110C0021`:** XN = 1; `AP = 001` (privileged RW); `TEX = 001, S = 1, C = 0, B = 0` (**Normal non-cacheable, shareable**: DMA buffers need no cache maintenance, Folder 03); `SIZE = 16` → 128 KB.
- **r5 peripherals, `RASR = 0x11050039`:** XN = 1; `AP = 001`; `TEX = 000, S = 1, C = 0, B = 1` (**shareable Device**); `SIZE = 28` → 512 MB.

The two architectural differences are proven by the output:

- The **stack guard (r6), 32 bytes inside the DTCM region**, is legal on PMSAv7 (higher region number wins: no access inside a RW region) but **rejected as an overlap on PMSAv8**. There the guard is a *hole* between two regions, or `PSPLIM`/`MSPLIM` is used instead.
- A **96 KB region** is illegal on PMSAv7 (not a power of two: `ERR_SIZE`) and fine on PMSAv8 (any multiple of 32 B).
- **Alignment:** a 128 KB region at `0x24010000` isn't size-aligned, so PMSAv7 returns `ERR_ALIGN`. That's why PMSAv7 linker scripts align DMA regions to their own size.

**Programming sequence** (implemented in `mpu_v7_program`):
1. validate everything first;
2. `DSB`/`ISB` so accesses under the old map complete;
3. `CTRL = 0`;
4. program regions (with `RBAR.VALID = 1`, the region number comes from `RBAR`);
5. disable leftover regions;
6. `CTRL = ENABLE | PRIVDEFENA`;
7. **`DSB` + `ISB`** so the next instruction fetch is checked against the new map.

`PRIVDEFENA = 1` gives privileged code the default memory map as a background region. That's convenient, but it makes every unmapped address privileged-RW. High-assurance builds set it to 0 and map everything explicitly.

**Cortex-M7 speculation.** The M7 can perform **speculative instruction fetches and data reads** to Normal-memory regions it isn't actually executing from. For addresses where nothing responds (an unpopulated external-memory window, a QSPI region with the controller off), a speculative read can stall the bus. Vendor guidance is to cover such windows with an MPU region that is Device/Strongly-ordered or no-access + XN (⚠ verify the vendor application note for your part).

### 1.5 The AArch64 MMU (VMSAv8-64)

Translation with a **4 KB granule and 48-bit VA** (`TCR_EL1.T0SZ = 16`) walks four levels, each indexing 9 VA bits:

```text
 VA[47:39] → L0 (512 GB/entry) → VA[38:30] → L1 (1 GB block) → VA[29:21] → L2 (2 MB block) → VA[20:12] → L3 (4 KB page)
```

Descriptor bits (stage 1, lower attributes in [11:2], upper in [63:52]):

| Bits | Field | Notes |
|---|---|---|
| `[1:0]` | `0b11` table (L0–L2) / page (L3); `0b01` block (L1/L2) | `0b00`/`0b10` invalid → translation fault |
| `[4:2]` | AttrIndx | Index into `MAIR_EL1` |
| `[7:6]` | AP | `00` EL1 RW, `01` RW all, `10` EL1 RO, `11` RO all |
| `[9:8]` | SH | `11` inner shareable (SMP normal memory), `10` outer |
| `[10]` | **AF** (access flag) | **Must be 1**, unless hardware AF management (FEAT_HAFDBS) is on; otherwise the first access raises an *access flag fault* |
| `[11]` | nG | Non-global (ASID-tagged) |
| `[47:12]` | Output address | |
| `[53]` | PXN | Privileged execute never |
| `[54]` | UXN/XN | Unprivileged execute never |

`MAIR_EL1` slots used here: `0xFF` Normal WB RA/WA, `0x44` Normal non-cacheable, `0x04` Device-nGnRE, `0x00` Device-nGnRnE. **Device-nGnRE** means:
- **nG**: non-Gathering, so accesses are not merged;
- **nR**: non-Reordering;
- **E**: Early write acknowledgement allowed.

MMIO should normally use nGnRE. nGnRnE (no early ack) is for registers where you need the write to have actually arrived, e.g. some PCIe configuration space.

`pgtable.h`:

```c
/* pgtable.h - AArch64 stage-1 translation tables, 4 KB granule, 48-bit VA
 * (TCR_EL1.T0SZ = 16: walk starts at level 0). Identity-maps physical ranges
 * with the largest legal blocks (1 GB at L1, 2 MB at L2, 4 KB pages at L3). */
#ifndef PGTABLE_H
#define PGTABLE_H

#include <stdbool.h>
#include <stdint.h>

typedef uint64_t pte_t;

#define PTE_VALID        (1ull << 0)
#define PTE_TABLE        (1ull << 1)     /* L0-L2: next-level table; L3: page       */
#define PTE_ATTRIDX(i)   ((uint64_t)(i) << 2)
#define PTE_ATTRIDX_MASK (7ull << 2)
#define PTE_AP_RW_EL1    (0ull << 6)
#define PTE_AP_RW_ALL    (1ull << 6)
#define PTE_AP_RO_EL1    (2ull << 6)
#define PTE_AP_RO_ALL    (3ull << 6)
#define PTE_SH_INNER     (3ull << 8)
#define PTE_SH_OUTER     (2ull << 8)
#define PTE_AF           (1ull << 10)    /* access flag: must be set or first touch faults */
#define PTE_NG           (1ull << 11)
#define PTE_PXN          (1ull << 53)
#define PTE_UXN          (1ull << 54)
#define PTE_ADDR_MASK    0x0000FFFFFFFFF000ull

/* MAIR_EL1 attribute slots */
#define MT_NORMAL_WB     0u    /* 0xFF */
#define MT_NORMAL_NC     1u    /* 0x44 */
#define MT_DEVICE_nGnRE  2u    /* 0x04 */
#define MT_DEVICE_nGnRnE 3u    /* 0x00 */
#define MAIR_EL1_VALUE   0x00000000000444FFull

/* TCR_EL1: T0SZ=16, IRGN0=ORGN0=WBWA, SH0=inner, TG0=4K, EPD1=1, IPS=40-bit */
#define TCR_EL1_VALUE    ((16ull << 0) | (1ull << 8) | (1ull << 10) | (3ull << 12) | \
                          (0ull << 14) | (1ull << 23) | (2ull << 32))

typedef enum { PT_OK = 0, PT_ERR_ALIGN, PT_ERR_NOMEM, PT_ERR_RANGE } pt_status_t;

typedef struct {
    pte_t   *root;           /* level-0 table (512 entries, 4 KB aligned) */
    pte_t  (*pool)[512];     /* backing store for further tables          */
    unsigned pool_used;
    unsigned pool_len;
} pt_ctx_t;

/* Map [pa, pa+size) at VA == PA with the given leaf attributes (AttrIndx,
 * AP, SH, XN bits; VALID/AF/type bits are added here). */
pt_status_t pt_map_identity(pt_ctx_t *ctx, uint64_t pa, uint64_t size, pte_t attrs);

typedef struct {
    bool     ok;
    unsigned level;          /* level of the leaf or of the faulting lookup */
    uint64_t pa;
    pte_t    leaf;
} pt_walk_t;

/* Software walk, exactly as the MMU does it (for tests and fault decoding). */
pt_walk_t pt_walk(const pte_t *root, uint64_t va);

#endif /* PGTABLE_H */
```

`pgtable.c`:

```c
/* pgtable.c - see pgtable.h. Descriptor formats: Arm ARM D8.3 (VMSAv8-64). */
#include "pgtable.h"

#include <stddef.h>
#include <string.h>

static unsigned shift_of(unsigned level) { return 39u - 9u * level; }   /* L0=39 L1=30 L2=21 L3=12 */
static unsigned index_of(uint64_t va, unsigned level) { return (unsigned)((va >> shift_of(level)) & 0x1FFu); }

static pte_t *alloc_table(pt_ctx_t *ctx)
{
    if (ctx->pool_used >= ctx->pool_len) {
        return NULL;
    }
    pte_t *t = ctx->pool[ctx->pool_used++];
    memset(t, 0, 512u * sizeof(pte_t));           /* invalid entries fault */
    return t;
}

/* Replace a block entry by a table of next-level blocks/pages with identical
 * attributes. On a LIVE table this needs break-before-make (see the KB). */
static pte_t *split_block(pt_ctx_t *ctx, pte_t *entry, unsigned level)
{
    pte_t *t = alloc_table(ctx);
    if (t == NULL) {
        return NULL;
    }
    uint64_t base = *entry & PTE_ADDR_MASK;
    pte_t attrs = *entry & ~(PTE_ADDR_MASK | PTE_TABLE);
    uint64_t step = 1ull << shift_of(level + 1u);
    pte_t type = (level + 1u == 3u) ? PTE_TABLE : 0u;  /* L3 leaf = page (0b11) */
    for (unsigned i = 0u; i < 512u; i++) {
        t[i] = ((base + i * step) & PTE_ADDR_MASK) | attrs | type;
    }
    *entry = ((uint64_t)(uintptr_t)t & PTE_ADDR_MASK) | PTE_TABLE | PTE_VALID;
    return t;
}

static pt_status_t map_level(pt_ctx_t *ctx, pte_t *table, unsigned level,
                             uint64_t va, uint64_t end, pte_t attrs)
{
    while (va < end) {
        uint64_t blk = 1ull << shift_of(level);
        uint64_t next = (va & ~(blk - 1u)) + blk;
        if (next > end) {
            next = end;
        }
        pte_t *e = &table[index_of(va, level)];
        bool aligned = ((va & (blk - 1u)) == 0u) && ((next - va) == blk);

        if ((level >= 1u) && aligned) {             /* block (L1/L2) or page (L3) */
            *e = (va & PTE_ADDR_MASK) | attrs | PTE_AF | PTE_VALID |
                 ((level == 3u) ? PTE_TABLE : 0u);
        } else {
            if (level == 3u) {
                return PT_ERR_ALIGN;                /* not 4 KB aligned */
            }
            pte_t *sub;
            if ((*e & PTE_VALID) == 0u) {
                sub = alloc_table(ctx);
                if (sub == NULL) {
                    return PT_ERR_NOMEM;
                }
                *e = ((uint64_t)(uintptr_t)sub & PTE_ADDR_MASK) | PTE_TABLE | PTE_VALID;
            } else if ((*e & PTE_TABLE) == 0u) {    /* existing block: split it */
                sub = split_block(ctx, e, level);
                if (sub == NULL) {
                    return PT_ERR_NOMEM;
                }
            } else {
                sub = (pte_t *)(uintptr_t)(*e & PTE_ADDR_MASK);
            }
            pt_status_t st = map_level(ctx, sub, level + 1u, va, next, attrs);
            if (st != PT_OK) {
                return st;
            }
        }
        va = next;
    }
    return PT_OK;
}

pt_status_t pt_map_identity(pt_ctx_t *ctx, uint64_t pa, uint64_t size, pte_t attrs)
{
    if (((pa | size) & 0xFFFu) != 0u) {
        return PT_ERR_ALIGN;
    }
    if ((size == 0u) || (pa + size > (1ull << 40)) || (pa + size < pa)) {
        return PT_ERR_RANGE;                        /* beyond IPS = 40 bits */
    }
    return map_level(ctx, ctx->root, 0u, pa, pa + size, attrs);
}

pt_walk_t pt_walk(const pte_t *root, uint64_t va)
{
    pt_walk_t w = { false, 0u, 0u, 0u };
    const pte_t *t = root;
    for (unsigned level = 0u; level <= 3u; level++) {
        pte_t e = t[index_of(va, level)];
        w.level = level;
        if ((e & PTE_VALID) == 0u) {
            return w;                                /* translation fault, level N */
        }
        bool table_or_page = (e & PTE_TABLE) != 0u;
        if ((level == 3u) || !table_or_page) {
            if ((level == 0u) && !table_or_page) {
                return w;                            /* no L0 blocks with 4 KB granule */
            }
            uint64_t off_mask = (1ull << shift_of(level)) - 1u;
            w.ok = true;
            w.leaf = e;
            w.pa = (e & PTE_ADDR_MASK & ~off_mask) | (va & off_mask);
            return w;
        }
        t = (const pte_t *)(uintptr_t)(e & PTE_ADDR_MASK);
    }
    return w;
}

#ifdef PT_SELFTEST
#include <stdalign.h>
#include <stdio.h>

static alignas(4096) pte_t g_root[512];
static alignas(4096) pte_t g_pool[8][512];

static const char *attr_name(pte_t leaf)
{
    static const char *const n[] = { "Normal-WB", "Normal-NC", "Device-nGnRE", "Device-nGnRnE" };
    unsigned i = (unsigned)((leaf & PTE_ATTRIDX_MASK) >> 2);
    return (i < 4u) ? n[i] : "?";
}

int main(void)
{
    pt_ctx_t ctx = { g_root, g_pool, 0u, 8u };
    const pte_t normal = PTE_ATTRIDX(MT_NORMAL_WB) | PTE_SH_INNER | PTE_AP_RW_EL1 | PTE_UXN;
    const pte_t code   = PTE_ATTRIDX(MT_NORMAL_WB) | PTE_SH_INNER | PTE_AP_RO_EL1 | PTE_UXN;
    const pte_t dmanc  = PTE_ATTRIDX(MT_NORMAL_NC) | PTE_SH_OUTER | PTE_AP_RW_EL1 | PTE_UXN | PTE_PXN;
    const pte_t dev    = PTE_ATTRIDX(MT_DEVICE_nGnRE) | PTE_AP_RW_EL1 | PTE_UXN | PTE_PXN;

    pt_status_t st[4];
    st[0] = pt_map_identity(&ctx, 0x40000000ull, 0x40000000ull, normal);  /* 1 GB DRAM       */
    st[1] = pt_map_identity(&ctx, 0x40080000ull, 0x00200000ull, code);    /* 2 MB kernel text, not 2MB-aligned */
    st[2] = pt_map_identity(&ctx, 0x7FE00000ull, 0x00200000ull, dmanc);   /* 2 MB DMA window  */
    st[3] = pt_map_identity(&ctx, 0x09000000ull, 0x00001000ull, dev);     /* 4 KB UART MMIO   */
    printf("map status: %d %d %d %d, tables used: %u of %u\n", st[0], st[1], st[2], st[3],
           ctx.pool_used, ctx.pool_len);
    printf("MAIR_EL1=0x%016llX TCR_EL1=0x%016llX\n",
           (unsigned long long)MAIR_EL1_VALUE, (unsigned long long)TCR_EL1_VALUE);

    const uint64_t probes[] = { 0x40001234ull, 0x40081000ull, 0x40280008ull, 0x7FE00040ull,
                                0x09000018ull, 0x09001000ull, 0x00000000ull, 0x80000000ull };
    for (unsigned i = 0u; i < sizeof probes / sizeof probes[0]; i++) {
        pt_walk_t w = pt_walk(g_root, probes[i]);
        if (w.ok) {
            printf("VA 0x%010llX -> PA 0x%010llX  L%u %-13s AP=%u XN(U/P)=%u/%u AF=%u desc=0x%016llX\n",
                   (unsigned long long)probes[i], (unsigned long long)w.pa, w.level, attr_name(w.leaf),
                   (unsigned)((w.leaf >> 6) & 3u), (unsigned)((w.leaf >> 54) & 1u),
                   (unsigned)((w.leaf >> 53) & 1u), (unsigned)((w.leaf >> 10) & 1u),
                   (unsigned long long)w.leaf);
        } else {
            printf("VA 0x%010llX -> translation fault at level %u\n",
                   (unsigned long long)probes[i], w.level);
        }
    }
    return 0;
}
#endif
```

**Self-test output (verified, native; zero diagnostics on AArch64 and x86-64):**

```text
map status: 0 0 0 0, tables used: 6 of 8
MAIR_EL1=0x00000000000444FF TCR_EL1=0x0000000200803510
VA 0x0040001234 -> PA 0x0040001234  L3 Normal-WB     AP=0 XN(U/P)=1/0 AF=1 desc=0x0040000040001703
VA 0x0040081000 -> PA 0x0040081000  L3 Normal-WB     AP=2 XN(U/P)=1/0 AF=1 desc=0x0040000040081783
VA 0x0040280008 -> PA 0x0040280008  L3 Normal-WB     AP=0 XN(U/P)=1/0 AF=1 desc=0x0040000040280703
VA 0x007FE00040 -> PA 0x007FE00040  L2 Normal-NC     AP=0 XN(U/P)=1/1 AF=1 desc=0x006000007FE00605
VA 0x0009000018 -> PA 0x0009000018  L3 Device-nGnRE  AP=0 XN(U/P)=1/1 AF=1 desc=0x006000000900040B
VA 0x0009001000 -> translation fault at level 3
VA 0x0000000000 -> translation fault at level 2
VA 0x0080000000 -> translation fault at level 1
```

What the walk proves:

- **Block splitting is real and costly.** DRAM was first mapped as one 1 GB L1 block. Mapping a 2 MB "kernel text" range at `0x40080000`, which is **not 2 MB-aligned**, forced the 1 GB block to split into 2 MB L2 blocks. The two 2 MB blocks the text straddles then split again into **4 KB L3 pages**. That's why `0x40001234` and `0x40280008` (both plain DRAM) translate at L3: 512 TLB entries' worth of mappings where one 2 MB entry would do. Linux aligns its kernel image to 2 MB for exactly this reason (TLB reach).
- **The descriptors decode correctly.** `0x0040000040001703` = UXN (bit 54) | address `0x40001000` | AF (`0x400`) | SH inner (`0x300`) | page (`0x3`). The 2 MB NC block `0x006000007FE00605` = PXN|UXN | AttrIndx 1 (`0x4`) | AF | block (`0x1`) with SH outer (`0x200`).
- **Faults report the level.** `0x09001000` (just past the 4 KB UART page) faults at L3; `0x0` at L2; `0x80000000` at L1. The hardware reports the same level in ESR's `DFSC` (`0x04`–`0x07` = translation fault, level 0–3), which is the first thing to read in an MMU fault post-mortem.
- **`TCR_EL1 = 0x200803510`:**
  - T0SZ = 16;
  - IRGN0 = ORGN0 = WBWA (`0x500`);
  - SH0 inner (`0x3000`);
  - TG0 4 KB;
  - **EPD1 = 1** (no TTBR1 walks, since there's no upper-half table);
  - IPS = 40-bit.

#### 1.5.1 Enabling the MMU, and changing live mappings (verified codegen)

```c
/* mmu_hw.c - EL1 MMU enable and live-table update (break-before-make). */
#include <stdint.h>

#include "pgtable.h"

#define SCTLR_M  (1ull << 0)    /* MMU enable          */
#define SCTLR_C  (1ull << 2)    /* data cache enable   */
#define SCTLR_I  (1ull << 12)   /* instruction cache   */

void mmu_enable_el1(const pte_t *root);
void mmu_enable_el1(const pte_t *root)
{
    uint64_t sctlr;
    __asm__ volatile(
        "msr  mair_el1, %[mair]   \n\t"
        "msr  tcr_el1, %[tcr]     \n\t"
        "msr  ttbr0_el1, %[ttbr]  \n\t"
        "isb                      \n\t"   /* system-register writes visible       */
        "tlbi vmalle1             \n\t"   /* no stale entries from a previous map */
        "dsb  nsh                 \n\t"
        "isb                      \n\t"
        : : [mair] "r"(MAIR_EL1_VALUE), [tcr] "r"(TCR_EL1_VALUE),
            [ttbr] "r"((uint64_t)(uintptr_t)root)
        : "memory");
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    sctlr |= SCTLR_M | SCTLR_C | SCTLR_I;
    __asm__ volatile(
        "msr  sctlr_el1, %0       \n\t"
        "isb                      \n\t"   /* next fetch is translated             */
        : : "r"(sctlr) : "memory");
}

/* Change a LIVE leaf (e.g. Normal-WB -> Normal-NC for a DMA buffer) without
 * ever letting two different translations coexist in TLBs:
 *   break (invalidate) -> TLBI -> make (write new). */
void pte_update_bbm(volatile pte_t *pte, pte_t new_val, uint64_t va);
void pte_update_bbm(volatile pte_t *pte, pte_t new_val, uint64_t va)
{
    *pte = 0u;                                          /* 1. break             */
    __asm__ volatile("dsb ishst" : : : "memory");       /*    store visible to walkers */
    __asm__ volatile("tlbi vaae1is, %0" : : "r"(va >> 12) : "memory"); /* 2. all cores */
    __asm__ volatile("dsb ish" : : : "memory");         /*    invalidation complete    */
    *pte = new_val;                                     /* 3. make              */
    __asm__ volatile("dsb ishst\n\tisb" : : : "memory");
}
```

**Codegen (verified — Clang 21.1.0, `-O2`, `aarch64-linux-gnu`):**

```asm
mmu_enable_el1:
	mov	x9, #13584
	mov	w8, #17663
	movk	x9, #128, lsl #16
	movk	w8, #4, lsl #16
	movk	x9, #2, lsl #32
	msr	MAIR_EL1, x8
	msr	TCR_EL1, x9
	msr	TTBR0_EL1, x0
	isb
	tlbi	vmalle1
	dsb	nsh
	isb
	mrs	x8, SCTLR_EL1
	mov	w9, #4101
	orr	x8, x8, x9
	msr	SCTLR_EL1, x8
	isb
	ret
pte_update_bbm:
	str	xzr, [x0]
	lsr	x8, x2, #12
	dsb	ishst
	tlbi	vaae1is, x8
	dsb	ish
	str	x1, [x0]
	dsb	ishst
	isb
	ret
```

- **Enable sequence:**
  1. Write `MAIR`, `TCR` and `TTBR0` (the constants are materialized as `0x444FF` and `0x200803510`), then `isb`.
  2. `tlbi vmalle1` to discard any stale TLB entries, then `dsb nsh`, then `isb`.
  3. Set `SCTLR_EL1.M`, `.C` and `.I` in one write (`orr` with `0x1005`), then **`isb`** so the next instruction fetch is translated.
  
  The code doing this must be **identity-mapped** (VA = PA), or the instruction after the `isb` is fetched from a different address than the one before it.
- **Break-before-make (BBM).** The Arm ARM forbids changing a live descriptor's output address, memory type, or block size in a way that could let two different valid translations exist at once. The penalty is TLB conflict aborts or loss of coherency. The sequence is:
  1. write 0 (invalid);
  2. `dsb ishst` (the walker sees it);
  3. `tlbi vaae1is` (all cores in the inner-shareable domain);
  4. `dsb ish` (invalidation complete);
  5. write the new descriptor;
  6. `dsb ishst` + `isb`.
  
  Converting a DMA buffer from Normal-WB to Normal-NC at run time (Folder 03), or splitting a block as the builder above does on a *live* table, requires exactly this. FEAT_BBM levels relax some cases on newer cores (⚠ verify).
- **Stage 2 and the SMMU.** A hypervisor adds a second translation (IPA→PA, `VTTBR_EL2`). Device DMA goes through the **SMMU**, which uses the same descriptor formats. Folder 06 covers both.

### 1.6 TCM: Tightly Coupled Memory

| Property | ITCM / DTCM (Cortex-M7), ATCM/BTCM (Cortex-R) |
|---|---|
| Latency | **Zero wait states** at core clock; *deterministic* (no cache misses, no bus contention with the AXI master) |
| Caching | **Not cacheable**: it doesn't need to be, and it never needs cache maintenance |
| Size and address | SoC-configured. On STM32H7: ITCM 64 KB at `0x0000_0000`, DTCM 128 KB at `0x2000_0000` (⚠ verify per part) |
| DMA access | Through the core's **AHBS slave port** on Cortex-M7, if the SoC routes a DMA master to it. Some SoCs allow only specific DMA engines (e.g. MDMA on STM32H7) to reach DTCM (⚠ verify the bus matrix) |
| Typical contents | ITCM: ISRs with hard deadlines, flash-programming routines (`.ramfunc`), the hot DSP kernel. DTCM: stacks, ISR state, lock-free queue indices, the RTOS kernel's ready lists |
| ECC | Many parts have ECC on TCM, and the first read of never-written words may raise an ECC error, so initialize before use (File 02 §1.6) |
| Address 0 | ITCM at address 0 means **a null function pointer executes the first ITCM instruction**, and a null data read returns ITCM contents instead of faulting. Reserve the first 32 bytes: an MPU no-access region, or a `UDF` trap stub |

The linker side of TCM placement (`> ITCM AT > FLASH`, thunks for flash→ITCM calls) is in File 01. The five-region production script is in Folder 07, File 01.

---

## 2. Production Blueprints

### 2.1 The Subtle Buggy Way: a secure boot that passes its happy-path test

```c
/* boot_verify_bad.c - a "secure boot" that passes its happy-path test and is
 * broken five ways. Compiles cleanly. */
#include <stdint.h>
#include <string.h>

#include "sha256.h"

struct bad_hdr {                     /* (1) overlaid on flash: layout = ABI-dependent */
    uint32_t magic, hdr_size, img_size, load_addr, entry, counter, key_id, flags;
    uint8_t  digest[32];
    uint8_t  signature[64];
};

extern int platform_verify_sig(const uint8_t digest[32], const uint8_t sig[64]);
int boot_bad(const uint8_t *slot, uint8_t *ram_dst, uint32_t min_counter);

int boot_bad(const uint8_t *slot, uint8_t *ram_dst, uint32_t min_counter)
{
    const struct bad_hdr *h = (const struct bad_hdr *)(const void *)slot;
    uint8_t d[32];
    sha256_ctx_t c;

    if (h->counter < min_counter) {               /* (2) counter checked, but it is NOT */
        return -1;                                /*     covered by the signature below  */
    }
    sha256_init(&c);
    sha256_update(&c, slot + 128, h->img_size);   /* (3) img_size unbounded: reads past the slot */
    sha256_final(&c, d);
    if (memcmp(d, h->digest, 32) != 0) {          /* (4) early-exit compare: timing oracle,  */
        return -2;                                /*     single glitch skips the branch       */
    }
    if (!platform_verify_sig(h->digest, h->signature)) {   /* signs the digest only */
        return -3;
    }
    memcpy(ram_dst, slot + 128, h->img_size);     /* (5) TOCTOU: verified flash, then re-read it */
    return 0;
}
```

**Diagnostics (verified):** zero warnings under the full warning set, **including `-Wcast-align`**. The `(const struct bad_hdr *)(const void *)slot` double cast launders the alignment warning that a direct cast would trigger (Folder 01, File 01 §4.1). The five defects:

1. **Header overlaid on flash:** an ABI-dependent layout, plus alignment and aliasing UB (Folder 01).
2. **The rollback counter isn't covered by the signature.** The signature covers only the *digest*. An attacker edits `counter` on an old, validly signed image, and the check passes. (The hardened version signs the whole header; verified: forged counter → `SIGNATURE`.)
3. **`img_size` unbounded:** the hash reads past the slot, into adjacent flash, a fault, or attacker-controlled external memory.
4. **`memcmp` early exit.** It leaks how many digest bytes matched through timing, and **one glitch on the `bne`** skips the whole check. The digest compare isn't duplicated, and there's no flow counter.
5. **TOCTOU:** it verifies flash, then copies from flash *again* into RAM and executes the copy.

### 2.2 The Silicon-Hardened Production Way

- **Boot:** the verified `boot_verify_image` (§1.2), plus hashing the RAM copy you will execute, plus duplicated decisions and a flow counter.
- **Isolation (M-profile):**
  - SAU configured so that Secure flash, Secure SRAM, the NSC veneer region (only `.gnu.sgstubs`) and Non-secure memory are explicit;
  - every entry function validates NS pointers with `cmse_check_address_range` (verified `tta`);
  - veneer addresses frozen with an input import library.
- **MPU:** generated from the memory map by the verified encoders, with:
  - XN on every data region;
  - privileged-only peripherals;
  - DMA buffers Normal-NC;
  - a stack guard (PMSAv7) or `PSPLIM` (PMSAv8);
  - the first 32 bytes of address 0 no-access;
  - speculative-access cover regions on M7;
  - `PRIVDEFENA = 0` in high-assurance builds.
- **MMU:** identity map built offline or at boot by the verified builder. Kernel and image regions are 2 MB-aligned to keep L2 blocks. Device memory uses nGnRE + XN/PXN. Every live change follows BBM.

---

## 3. Hardware Debugging and Post-Mortem Diagnostics

### 3.1 Cortex-M MemManage and SecureFault

| Register | Address | Key bits |
|---|---|---|
| `CFSR.MMFSR` | `0xE000ED28` [7:0] | `IACCVIOL` 0 (fetch from XN/no-access), `DACCVIOL` 1, `MUNSTKERR` 3, `MSTKERR` 4 (stack overflow into a guard during exception entry), `MLSPERR` 5, `MMARVALID` 7 |
| `MMFAR` | `0xE000ED34` | Faulting data address when `MMARVALID` |
| `SFSR` (v8-M) | `0xE000EDE4` | `INVEP` 0 (NS branched to a non-`SG` address in S memory), `INVIS` 1 (integrity signature mismatch on exception return), `INVER` 2 (invalid exception return), `AUVIOL` 3 (NS access to S memory), `INVTRAN` 4 (invalid transition, e.g. branch to NS without `BXNS`), `LSPERR` 5, `SFARVALID` 6, `LSERR` 7 |
| `SFAR` | `0xE000EDE8` | Faulting address when `SFARVALID` |

Two common signatures:
- `SFSR.INVEP` means a Non-secure image calling a stale veneer address after a Secure-image update (§1.3.2).
- `SFSR.AUVIOL` with `SFAR` in Secure RAM means an NS DMA or code path touching Secure memory. That's the fault you *want*, versus the confused-deputy bug where the Secure side does it on the attacker's behalf.

### 3.2 AArch64 MMU faults

For a data abort (ESR EC `0x24`/`0x25`), the DFSC tells you which stage of the walk failed:

| DFSC | Meaning | Usual cause |
|---|---|---|
| `0x04`–`0x07` | Translation fault, level 0–3 | Unmapped VA; the verified walker reports the same level |
| `0x09`–`0x0B` | Access flag fault, L1–L3 | Descriptor written without AF and no hardware AF update |
| `0x0D`–`0x0F` | Permission fault, L1–L3 | Write to an RO mapping, or execute from XN/PXN |
| `0x21` | Alignment fault | Unaligned access to Device memory |
| `0x30` | TLB conflict abort | Two TLB entries hit one VA, i.e. **break-before-make skipped** |

TRACE32's `MMU.List.PageTable` decodes live tables, and `MMU.FORMAT` must match the TCR configuration. GDB with a QEMU or OpenOCD target can dump the tables as memory. Run the verified `pt_walk` logic in a GDB Python script for the same decode.

---

## 4. Tier-1 L7 Bar-Raiser Q&A Chains

### Q1 🔥 "Design secure boot for a Cortex-M33 product with field updates."

- **L5:** "ROM checks a signature on the image using a public key."
- **Why L5 fails on hardware:** It skips the attacks that actually happen:
  - rollback to an old signed image;
  - fields outside the signed region (verified: unsigned counter → bypass);
  - unbounded lengths;
  - glitching a single compare;
  - TOCTOU between verify and execute;
  - debug ports left open;
  - key revocation.
- **L7 defense:** Immutable ROM with a root-key hash in OTP. A signed header covering digest, counter, load address and entry point (verified: the forged counter is rejected). Then:
  - a monotonic counter in OTP/RPMB;
  - bounds before hashing;
  - constant-time, duplicated compares and a flow counter;
  - hashing the executed RAM copy;
  - fail-closed;
  - MCUboot-style A/B slots with revert-on-failed-confirm;
  - authenticated debug;
  - TF-M for the Secure side.

### Q2 🔥 "What does the compiler do for a `cmse_nonsecure_entry` function?"

- **L5:** "It makes the function callable from Non-secure code."
- **Why L5 fails:** The compiler alone can't. It emits the `__acle_se_` alias, register and FP scrubbing, and `bxns lr`. The **linker** creates the `sg` veneer in NSC memory and the import library (both verified). And neither of them validates pointer arguments for you.
- **L7 defense:** Walk the verified listing (scrub of `r1`–`r3`/`r12`/APSR/FP, `bxns`) and the veneer (`sg; b.w`). Validate every NS pointer with `cmse_check_address_range`, which became `tta` (verified). Keep NSC containing only veneers, freeze veneer addresses across releases, and call out to NS through `cmse_nonsecure_call` pointers (`blxns`, with full save and scrub, verified).

### Q3 "Configure the MPU so a DMA buffer needs no cache maintenance, and a stack overflow is caught."

- **L5:** "Mark the buffer non-cacheable and put a guard region below the stack."
- **Why L5 fails:** On PMSAv7 the region must be a power-of-two size, aligned to its size (verified `ERR_ALIGN`/`ERR_SIZE`). On PMSAv8 overlapping guards are *illegal* (verified `ERR_OVERLAP`). "Non-cacheable" must be **Normal** NC, not Device, or unaligned and `memcpy`-style accesses to the buffer fault or slow down. And without `DSB`/`ISB` after enabling, the next accesses may run under the old map.
- **L7 defense:**
  - Encode with the verified functions: DMA = `TEX=001 C=0 B=0 S=1` (`RASR 0x110C0021`).
  - Align the linker section to the region size (v7).
  - Guard = a 32-byte `AP=000` region above it in region number (v7), or `PSPLIM`/`MSPLIM` (v8).
  - Program with disable → regions → enable → `DSB`/`ISB`.
  - On M7, add speculative-access cover regions.

### Q4 🔥 "Walk the AArch64 translation of a VA through 4 KB-granule tables, and tell me why the kernel is 2 MB-aligned."

- **L5:** "Four levels, nine bits each, 4 KB pages."
- **Why L5 fails:** It misses **block descriptors** (1 GB at L1, 2 MB at L2) and the TLB-reach consequence. A misaligned image forces splits down to 4 KB pages (verified: L3 translations for plain DRAM after mapping a misaligned 2 MB range). It also misses AF, MAIR indirection, shareability, and the fault-level decoding.
- **L7 defense:** The verified builder and walker output. Decode one descriptor bit by bit. Explain `TCR_EL1` fields, EPD1, and the enable sequence (verified asm). Explain BBM for live changes, and TLB conflict aborts (DFSC `0x30`) when it's skipped. Mention contiguous-bit hints and huge pages for TLB reach.

### Q5 🧊 "Why is it dangerous to have ITCM at address 0?"

- **L5:** "It isn't; it's fast memory."
- **Why L5 fails:** Address 0 is the null pointer. With code or data there, null dereferences and null function calls **don't fault**: they read ITCM or execute whatever is at `0x0` (in File 01's image, `ram_mix`). That turns crashes into silent misbehavior.
- **L7 defense:** Reserve the first 32 bytes, with an MPU no-access region (verified encoder: a 32-byte region is legal) or a `UDF` stub at `0x0`. Place real ITCM code after it, and compile with `-fno-delete-null-pointer-checks` if the code genuinely reads address 0 (Folder 01, File 01 §1.8).

### Q6 "Your TF-M product passes all tests. What single coding mistake most often breaks its isolation?"

- **L5:** "Buffer overflows."
- **Why L5 fails:** Close, but the TrustZone-specific answer is the **confused deputy**. A Secure entry function writes to (or reads from) a pointer supplied by the Non-secure caller without checking that the *Non-secure side* is allowed to access it. The hardware checks the *Secure* function's rights, which cover everything.
- **L7 defense:** `cmse_check_address_range(p, n, CMSE_NONSECURE | CMSE_MPU_READWRITE)` (verified `tta` sequence) on every pointer and length. Copy NS data into Secure buffers *once* (TOCTOU: the NS side can change it concurrently from another context or DMA). Validate lengths with overflow-safe arithmetic, and fuzz the veneer interface.

---

## 5. Invariants Checklist

- [ ] Root-key hash in OTP; ROM verifies the first mutable stage; every stage verifies the next *before* executing it.
- [ ] Signed region covers digest, security counter, load address and entry point; bounds checked before hashing; anti-rollback against a monotonic counter.
- [ ] Constant-time, duplicated compares and a flow counter on the final decision; hash the bytes you execute.
- [ ] NSC region contains only linker-generated `SG` veneers; veneer addresses frozen across releases; every NS pointer checked with `cmse_check_address_range`.
- [ ] MPU regions generated by validated encoders; XN on data; Normal-NC for DMA; guards or `PSPLIM`; `DSB`/`ISB` after enable; `PRIVDEFENA` policy decided explicitly.
- [ ] Address 0 is not usable memory (reserved, or a trap).
- [ ] AArch64 tables: AF set, MAIR slots documented, Device nGnRE + XN for MMIO, images 2 MB-aligned, identity-mapped enable code, break-before-make for every live change.
- [ ] TCM initialized before reads (ECC), used for deterministic code and data, and its DMA reachability checked against the SoC bus matrix.

## 6. References

1. Arm, *ARMv8-M Architecture Reference Manual* (DDI 0553): Security Extension, PMSAv8, `TT`/`SG`/`BXNS`, SFSR; *Armv8-M Security Extensions: Requirements on Development Tools* (CMSE).
2. Arm, *ARMv7-M Architecture Reference Manual* (DDI 0403E) §B3.5 *Protected Memory System Architecture, PMSAv7*.
3. Arm, *Arm Architecture Reference Manual for A-profile* (DDI 0487): D8 translation tables, `MAIR_EL1`, `TCR_EL1`, `SCTLR_EL1`, TLB maintenance, break-before-make; *Learn the architecture: AArch64 memory management* guide.
4. Trusted Firmware-A *Firmware Design* and *Trusted Board Boot*; Trusted Firmware-M *Secure Boot* / MCUboot design (image header, TLV, rollback); PSA Certified and Arm *Platform Security Boot Guide*.
5. NIST FIPS 180-4, *Secure Hash Standard* (test vectors in Appendix B / CSRC examples).
6. Arm, *Cortex-M7 Technical Reference Manual* (TCM, AHBS) and vendor reference manuals for TCM sizes and bus-matrix reachability (⚠ verify per part).
7. LLD documentation: `--cmse-implib`, `--in-implib`, `--out-implib`.
