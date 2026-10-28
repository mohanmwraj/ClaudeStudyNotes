# 03.3 · TUF (The Update Framework) and Uptane: Roles, Keys, Threshold Signing and Anti-Rollback

> **Folder 03 · File 3 of 4.** A signed image proves who *built* it. It doesn't prove that it is the *latest* image, that this device *should* install it, or that the server *still* has the keys it had last year. Signatures alone leave a family of attacks open:
>
> | Attack | What the attacker does |
> |---|---|
> | Freeze | Withholds updates |
> | Rollback | Replays an old vulnerable release |
> | Mix-and-match | Combines metadata from different releases |
> | Key compromise | Uses one stolen online key to sign anything |
> | Endless data | Serves an infinite stream |
>
> **TUF** answers with separated roles, thresholds, versions and expirations. **Uptane** extends TUF for fleets of ECUs, where a compromised server must still not be able to install arbitrary software.
>
> This file implements the TUF 1.0.37 client workflow and Uptane 2.1.0 full verification, and runs each attack against them. The Ed25519 underneath is validated against RFC 8032 vectors and OpenSSL 3.5.
>
> **Pinned.**
> - TUF specification **v1.0.37** (`tuf-spec.md`: "Detailed client workflow", "File formats", "Key management and migration").
> - Uptane Standard **2.1.0** (`uptane-standard.md`: "Full verification", "Partial verification", "Metadata about images").
> - RFC 8032 (Ed25519).
>
> **Verification.**
> - `ed25519_ref.py` reproduces RFC 8032 §7.1 TEST 1 and TEST 2.
> - `ed25519_interop.sh` signs with a fresh OpenSSL key and verifies in Python, and the reverse.
> - `tuf_verify.py` runs 18 cases: each attack must fail with the right error class, and each legitimate operation, including root key rotation and fast-forward recovery, must succeed.

---

## 1. First-Principles Architecture & Hardware State Machines

### 1.1 Roles and what each one protects

| Role | Signs | Key location | Expiry | If its key is stolen alone |
|---|---|---|---|---|
| **root** | Keys and thresholds of every role, including itself | Offline, threshold (e.g. 2-of-3 HSM-held keys in a ceremony) | Long (a year or more) | Game over unless threshold; that's why it's threshold and offline |
| **targets** | What images exist: names, lengths, hashes, custom data | Release HSM, used per release | Months | Attacker can list malicious images, but devices also need snapshot + timestamp; Uptane adds the Director check |
| **snapshot** | Which version of every targets file is current | Online | Days | Can freeze or mix only within what targets signed |
| **timestamp** | Which snapshot is current, frequently re-signed | Online, automated | Hours to a day | Can freeze a device only until the timestamp expires |

**The design principle is containment.** The keys that must be online, because they re-sign frequently, are the ones whose compromise is least harmful and shortest-lived. The keys that can do the most damage are offline and threshold.

### 1.2 The client workflow (TUF 1.0.37)

```text
 0  fix the update start time T (all expiry checks use T)
 1  load trusted root (shipped with the device)
 2  UPDATE ROOT: while (N+1).root.json exists:
        verify threshold of N's root keys AND threshold of (N+1)'s root keys   (one signature per keyid)
        version == N+1 exactly; persist
    root expires > T, else FREEZE
    if timestamp or snapshot keys changed: delete trusted timestamp + snapshot   (fast-forward recovery)
 3  TIMESTAMP: threshold (timestamp role); version > trusted (== → no update, stop; < → ROLLBACK);
    snapshot version listed must not decrease; expires > T; persist
 4  SNAPSHOT: hashes/length == timestamp's meta; threshold; version == timestamp's;
    no listed targets version decreases, none removed (ROLLBACK); expires > T; persist
 5  TARGETS: hashes/length == snapshot's meta; threshold; version == snapshot's (MIX-AND-MATCH); expires > T
 6  FETCH TARGET: download at most `length` bytes (ENDLESS DATA), hashes must match (ARBITRARY SOFTWARE)
```

**Three details decide whether an implementation is TUF or merely looks like it:**
- **Signatures count per keyid.** The spec requires that "each SIGNATURE which is counted towards the THRESHOLD MUST have a unique KEYID". Duplicating one valid signature must not reach a threshold of two.
- **Root rotation needs both thresholds.** The new root must be signed by a threshold of the *old* root keys and of its *own* root keys. One proves continuity, the other proves the new keyholders accept the role.
- **Time is fixed at the start.** A device whose clock can be set by an attacker defeats every expiry check. Use a monotonic secure time source: Uptane's attested time, a time server signed by its own TUF role, or at minimum never accept time from the update channel itself.

### 1.3 Metadata format

- **Every metadata file is `{"signed": ROLE, "signatures": [{"keyid", "sig"}]}`.** The signature covers the **canonical JSON** of `signed` (the OLPC dialect: sorted keys, no whitespace, no floats).
- **A key is `{"keytype": "ed25519", "scheme": "ed25519", "keyval": {"public": <64 hex>}}`.** Its **keyid** is the SHA-256 of the key's canonical form.
- **Ambiguity breaks signatures.** A different canonicalization makes every signature fail, or worse, lets two parsers disagree about what was signed.

### 1.4 Uptane: two repositories, and why

```text
  Image repository (offline-signed targets: what images EXIST)     Director repository (online: what THIS vehicle installs)
            │ targets: brake-4.2.bin {length, sha256, hardware_id, release_counter}       │ targets: brake-4.2.bin {..., ecu_serial: BRK-0001}
            └──────────────────────────► Primary ECU: FULL verification ◄────────────────────┘
                                         · both repositories pass the TUF workflow
                                         · every Director-assigned image exists in the Image repo with the SAME length,
                                           hashes and SHALL-match custom fields (hardware id, release counter)
                                         · release counter ≥ installed (rollback even with a compromised Director)
                                         └──► Secondary ECUs: full verification (SHOULD), or PARTIAL: Director targets only
```

- **A compromised Director (online keys)** can only assign images the offline-signed Image repository also lists, and can't roll them back past their release counter.
- **A compromised Image repository alone** can list malware, but no Director assigns it.
- **Partial verification is the floor for constrained Secondaries.** "The smallest set of Uptane checks permissible" is Director Targets only, which trusts the Primary's full verification.

### 1.5 Placing TUF in the stack

| Layer | Verifies |
|---|---|
| TUF/Uptane metadata | *Which* artifact, *which* version, *still current*, *for this device* |
| Artifact signature (FIT 01.4, OSTree commit 03.2, RAUC bundle 03.4) | The artifact's own integrity at install and boot time |
| Secure boot, dm-verity / composefs | What actually executes, every boot |
| Anti-rollback counters (01.1) | That even a valid-looking older artifact can't boot after commit |

They're complementary. TUF without boot-time verification is defeated by anyone who writes storage directly. Boot-time verification without TUF is defeated by freeze and rollback over the network.

---

## 2. Production Code & Configuration Blueprints

### 2.1 Ed25519, verified against the RFC and OpenSSL

```python
# ed25519_ref.py - Ed25519 (RFC 8032) in pure Python: the signature scheme TUF/Uptane metadata and OSTree use
"""Usage: python ed25519_ref.py --selftest
          python ed25519_ref.py sign <seed-hex> <message-file>          -> signature hex
          python ed25519_ref.py verify <public-hex> <message-file> <signature-hex>

Follows RFC 8032 section 5.1 (with the section 6 reference structure): extended coordinates, cofactored
secret, deterministic nonce r = SHA-512(prefix || M), s < q enforced on verify. Not constant-time: fine
for verifying public metadata, never for signing on a device.
"""
import hashlib
import sys

p = 2**255 - 19
q = 2**252 + 27742317777372353535851937790883648493
d = -121665 * pow(121666, p - 2, p) % p
SQRT_M1 = pow(2, (p - 1) // 4, p)


def sha512(b):
    return hashlib.sha512(b).digest()


def add(P, Q):
    A = (P[1] - P[0]) * (Q[1] - Q[0]) % p
    B = (P[1] + P[0]) * (Q[1] + Q[0]) % p
    C = 2 * P[3] * Q[3] * d % p
    D = 2 * P[2] * Q[2] % p
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % p, G * H % p, F * G % p, E * H % p)


def mul(s, P):
    Q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            Q = add(Q, P)
        P = add(P, P)
        s >>= 1
    return Q


def equal(P, Q):
    return (P[0] * Q[2] - Q[0] * P[2]) % p == 0 and (P[1] * Q[2] - Q[1] * P[2]) % p == 0


def recover_x(y, sign):
    if y >= p:
        return None
    x2 = (y * y - 1) * pow(d * y * y + 1, p - 2, p) % p
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (p + 3) // 8, p)
    if (x * x - x2) % p:
        x = x * SQRT_M1 % p
    if (x * x - x2) % p:
        return None
    return p - x if (x & 1) != sign else x


G_Y = 4 * pow(5, p - 2, p) % p
G_X = recover_x(G_Y, 0)
G = (G_X, G_Y, 1, G_X * G_Y % p)


def compress(P):
    zinv = pow(P[2], p - 2, p)
    x, y = P[0] * zinv % p, P[1] * zinv % p
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def decompress(b):
    if len(b) != 32:
        return None
    y = int.from_bytes(b, "little")
    sign, y = y >> 255, y & ((1 << 255) - 1)
    x = recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % p)


def expand(seed):
    h = sha512(seed)
    a = int.from_bytes(h[:32], "little")
    a = (a & ((1 << 254) - 8)) | (1 << 254)
    return a, h[32:]


def public_key(seed):
    return compress(mul(expand(seed)[0], G))


def sign(seed, msg):
    a, prefix = expand(seed)
    A = compress(mul(a, G))
    r = int.from_bytes(sha512(prefix + msg), "little") % q
    R = compress(mul(r, G))
    k = int.from_bytes(sha512(R + A + msg), "little") % q
    return R + ((r + k * a) % q).to_bytes(32, "little")


def verify(public, msg, sig):
    if len(public) != 32 or len(sig) != 64:
        return False
    A, R = decompress(public), decompress(sig[:32])
    s = int.from_bytes(sig[32:], "little")
    if A is None or R is None or s >= q:
        return False
    k = int.from_bytes(sha512(sig[:32] + public + msg), "little") % q
    return equal(mul(s, G), add(R, mul(k, A)))


# RFC 8032 section 7.1, TEST 1 and TEST 2
VECTORS = [
    ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46b"
     "d25bf5f0595bbe24655141438e7a100b"),
    ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c"
     "387b2eaeb4302aeeb00d291612bb0c00"),
]


def main():
    a = sys.argv[1:]
    if a == ["--selftest"]:
        ok = True
        for i, (sk, pk, m, sig) in enumerate(VECTORS, 1):
            seed, msg = bytes.fromhex(sk), bytes.fromhex(m)
            good = public_key(seed).hex() == pk and sign(seed, msg).hex() == sig and \
                verify(bytes.fromhex(pk), msg, bytes.fromhex(sig)) and \
                not verify(bytes.fromhex(pk), msg + b"x", bytes.fromhex(sig))
            ok &= good
            print(f"RFC 8032 TEST {i}: {'ok' if good else 'FAIL'}")
        print("selftest:", "ALL PASSED" if ok else "FAILED")
        sys.exit(0 if ok else 1)
    if a[0] == "sign":
        print(sign(bytes.fromhex(a[1]), open(a[2], "rb").read()).hex())
    elif a[0] == "verify":
        good = verify(bytes.fromhex(a[1]), open(a[2], "rb").read(), bytes.fromhex(a[3]))
        print("Signature Verified Successfully" if good else "Signature Verification Failure")
        sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
```

```sh
#!/bin/sh
# ed25519_interop.sh - fresh OpenSSL key: OpenSSL signs / Python verifies, Python signs / OpenSSL verifies
# Usage: sh ed25519_interop.sh   (in an empty directory holding ed25519_ref.py; needs openssl >= 1.1.1)
set -eu
openssl genpkey -algorithm ed25519 -out k.pem
openssl pkey -in k.pem -pubout -out pub.pem
# Raw keys: the last 32 bytes of the PKCS#8 private key and of the SubjectPublicKeyInfo.
seed=$(openssl pkey -in k.pem -outform DER | tail -c 32 | od -An -v -tx1 | tr -d ' \n')
pub=$(openssl pkey -in k.pem -pubout -outform DER | tail -c 32 | od -An -v -tx1 | tr -d ' \n')
printf '{"_type":"timestamp","version":7}' > msg

openssl pkeyutl -sign -inkey k.pem -rawin -in msg -out sig.bin
python -I ed25519_ref.py verify "$pub" msg "$(od -An -v -tx1 sig.bin | tr -d ' \n')"

python -I ed25519_ref.py sign "$seed" msg | tr -d '\r\n' > sig.hex
python -c "open('sig2.bin','wb').write(bytes.fromhex(open('sig.hex').read()))"
openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in msg -sigfile sig2.bin

printf '{"_type":"timestamp","version":8}' > tampered
if openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in tampered -sigfile sig2.bin >/dev/null 2>&1; then
	echo "tampered message verified by openssl: FAIL"
	exit 1
fi
if python -I ed25519_ref.py verify "$pub" tampered "$(od -An -v -tx1 sig.bin | tr -d ' \n')"; then
	echo "tampered message verified by ed25519_ref: FAIL"
	exit 1
fi
echo "interop: ALL PASSED"
```

```text
RFC 8032 TEST 1: ok
RFC 8032 TEST 2: ok
selftest: ALL PASSED
```

```text
Signature Verified Successfully
Signature Verified Successfully
Signature Verification Failure
interop: ALL PASSED
```

### 2.2 Update metadata

#### The Fragile Way

```json
{ "image": "app-2.0.img", "sha256": "4b1d…", "url": "https://updates.acme.example/app-2.0.img",
  "signature": "<one Ed25519 signature by build-server key>" }
```

One key on the build server signs one manifest:
- **No version and no expiry.** Every manifest ever signed remains valid forever, so the attacker can replay `app-1.3.img` (rollback) or keep serving today's manifest (freeze).
- **No role separation.** The online build key is the only key, and its theft lets the attacker ship anything.
- **No device targeting.** Every device installs whatever the manifest says.

#### The Silicon-Hardened Production Way

TUF roles with thresholds, as `tuf_verify.py` produces them (keys and signatures abbreviated):

```text
{
 "signed": {
  "_type": "root",
  "spec_version": "1.0.37",
  "consistent_snapshot": false,
  "version": 1,
  "expires": "2030-01-01T00:00:00Z",
  "keys": {
   "924b7f3db487...": {
    "keytype": "ed25519",
    "scheme": "ed25519",
    "keyval": {
     "public": "ee3a679a8d1c7e7d..."
    }
   },
   "c6d2c199cfa1...": {
    "keytype": "ed25519",
    "scheme": "ed25519",
    "keyval": {
     "public": "740ef4287c604901..."
    }
   },
   "d2ba2f60d825...": {
    "keytype": "ed25519",
    "scheme": "ed25519",
    "keyval": {
     "public": "bed6fa042e51ab04..."
    }
   },
   "640800ca1d29...": {
    "keytype": "ed25519",
    "scheme": "ed25519",
    "keyval": {
     "public": "49ce08cfa82ae86e..."
    }
   },
   "165fa872bc4d...": {
    "keytype": "ed25519",
    "scheme": "ed25519",
    "keyval": {
     "public": "37842b9cf67bcecc..."
    }
   }
  },
  "roles": {
   "root": {
    "keyids": [
     "924b7f3db487...",
     "c6d2c199cfa1..."
    ],
    "threshold": 2
   },
   "targets": {
    "keyids": [
     "d2ba2f60d825..."
    ],
    "threshold": 1
   },
   "snapshot": {
    "keyids": [
     "640800ca1d29..."
    ],
    "threshold": 1
   },
   "timestamp": {
    "keyids": [
     "165fa872bc4d..."
    ],
    "threshold": 1
   }
  }
 },
 "signatures": [
  {
   "keyid": "924b7f3db487...",
   "sig": "dacb065018a66518be71b424..."
  },
  {
   "keyid": "c6d2c199cfa1...",
   "sig": "ab3d80b5d5bc01bc39833a77..."
  }
 ]
}
canonical form signed (bytes): 1590
```

The client and the attack suite:

```python
# tuf_verify.py - a TUF 1.0.37 client workflow and Uptane 2.1.0 full verification, with the attacks it stops
"""Usage: python tuf_verify.py      (needs ed25519_ref.py alongside)

Client steps follow the TUF specification v1.0.37 "Detailed client workflow" (update root, timestamp,
snapshot, targets, fetch target), including: root N+1 signed by a threshold of BOTH old and new root
keys; one signature per keyid towards a threshold; version rules (exactly N+1 for root, strictly
greater for timestamp, equal to the referencing metadata for snapshot/targets); hashes and length
from the referencing metadata; expiry against a time fixed at the start of the update; deleting
trusted timestamp/snapshot when their keys rotate (fast-forward recovery). Delegations and consistent
snapshots are not modelled. Uptane full verification (standard 2.1.0, "Full verification"): Director
and Image repository Targets must agree on length, hashes and SHALL-match custom metadata, and the
release counter must not go backwards.
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I drops the script directory
import ed25519_ref as ed  # noqa: E402

SPEC = "1.0.37"


class TufError(Exception):
    def __init__(self, kind, msg):
        super().__init__(f"{kind}: {msg}")
        self.kind = kind


def canonical(obj):
    """OLPC canonical JSON as TUF uses it: sorted keys, no whitespace, integers only, minimal escaping."""
    if isinstance(obj, dict):
        return "{" + ",".join(canonical(k) + ":" + canonical(obj[k]) for k in sorted(obj)) + "}"
    if isinstance(obj, list):
        return "[" + ",".join(canonical(v) for v in obj) + "]"
    if isinstance(obj, str):
        return '"' + obj.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, int):
        return str(obj)
    if obj is None:
        return "null"
    raise TypeError("canonical JSON has no floats")


class Key:
    def __init__(self, label):
        self.seed = hashlib.sha256(label.encode()).digest()      # deterministic test keys
        self.public = ed.public_key(self.seed)
        self.obj = {"keytype": "ed25519", "scheme": "ed25519", "keyval": {"public": self.public.hex()}}
        self.keyid = hashlib.sha256(canonical(self.obj).encode()).hexdigest()


def sign(signed, keys):
    msg = canonical(signed).encode()
    return {"signed": signed, "signatures": [{"keyid": k.keyid, "sig": ed.sign(k.seed, msg).hex()} for k in keys]}


def dump(md):
    return json.dumps(md).encode()


def meta_for(blob, version):
    return {"version": version, "length": len(blob), "hashes": {"sha256": hashlib.sha256(blob).hexdigest()}}


def verify_threshold(md, root_signed, role):
    """Count each authorized keyid once; signatures are over the canonical form of 'signed'."""
    spec = root_signed["roles"][role]
    msg, good = canonical(md["signed"]).encode(), set()
    for s in md["signatures"]:
        key = root_signed["keys"].get(s["keyid"])
        if s["keyid"] in spec["keyids"] and key and s["keyid"] not in good and \
                ed.verify(bytes.fromhex(key["keyval"]["public"]), msg, bytes.fromhex(s["sig"])):
            good.add(s["keyid"])
    if len(good) < spec["threshold"]:
        raise TufError("signature", f"{role}: {len(good)} valid of threshold {spec['threshold']}")


def check_blob(blob, meta, what):
    if len(blob) > meta["length"]:
        raise TufError("endless-data", f"{what}: {len(blob)} bytes > {meta['length']}")
    if hashlib.sha256(blob).hexdigest() != meta["hashes"]["sha256"] or len(blob) != meta["length"]:
        kind = "mix-and-match" if what.endswith(".json") else "arbitrary-software"
        raise TufError(kind, f"{what}: hash mismatch")


class Client:
    def __init__(self, root_md):
        self.trusted = {"root": root_md}          # shipped out of band with the device

    def refresh(self, repo, now):
        """repo: filename -> bytes. 'now' is fixed for the whole update (spec: fixed update start time)."""
        root, start_roles = self.trusted["root"], self.trusted["root"]["signed"]["roles"]
        while f"{root['signed']['version'] + 1}.root.json" in repo:              # update the root role
            new = json.loads(repo[f"{root['signed']['version'] + 1}.root.json"])
            verify_threshold(new, root["signed"], "root")                        # old keys...
            verify_threshold(new, new["signed"], "root")                         # ...and new keys
            if new["signed"]["version"] != root["signed"]["version"] + 1:
                raise TufError("rollback", "root version is not N+1")
            root = self.trusted["root"] = new
        if root["signed"]["expires"] <= now:
            raise TufError("freeze", "root expired")
        for role in ("timestamp", "snapshot"):                                   # fast-forward recovery
            if set(root["signed"]["roles"][role]["keyids"]) != set(start_roles[role]["keyids"]):
                self.trusted.pop("timestamp", None)
                self.trusted.pop("snapshot", None)
        rs = root["signed"]

        ts = json.loads(repo["timestamp.json"])                                  # update the timestamp role
        verify_threshold(ts, rs, "timestamp")
        old = self.trusted.get("timestamp")
        if old:
            if ts["signed"]["version"] < old["signed"]["version"]:
                raise TufError("rollback", "timestamp version went backwards")
            if ts["signed"]["version"] == old["signed"]["version"]:
                return "no-change"
            if ts["signed"]["meta"]["snapshot.json"]["version"] < old["signed"]["meta"]["snapshot.json"]["version"]:
                raise TufError("rollback", "snapshot version in timestamp went backwards")
        if ts["signed"]["expires"] <= now:
            raise TufError("freeze", "timestamp expired")
        self.trusted["timestamp"] = ts

        blob = repo["snapshot.json"]                                              # update the snapshot role
        check_blob(blob, ts["signed"]["meta"]["snapshot.json"], "snapshot.json")
        snap = json.loads(blob)
        verify_threshold(snap, rs, "snapshot")
        if snap["signed"]["version"] != ts["signed"]["meta"]["snapshot.json"]["version"]:
            raise TufError("mix-and-match", "snapshot version differs from timestamp's")
        if self.trusted.get("snapshot"):
            for name, m in self.trusted["snapshot"]["signed"]["meta"].items():
                if name not in snap["signed"]["meta"] or snap["signed"]["meta"][name]["version"] < m["version"]:
                    raise TufError("rollback", f"{name} version went backwards in snapshot")
        if snap["signed"]["expires"] <= now:
            raise TufError("freeze", "snapshot expired")
        self.trusted["snapshot"] = snap

        blob = repo["targets.json"]                                               # update the targets role
        check_blob(blob, snap["signed"]["meta"]["targets.json"], "targets.json")
        tg = json.loads(blob)
        verify_threshold(tg, rs, "targets")
        if tg["signed"]["version"] != snap["signed"]["meta"]["targets.json"]["version"]:
            raise TufError("mix-and-match", "targets version differs from snapshot's")
        if tg["signed"]["expires"] <= now:
            raise TufError("freeze", "targets expired")
        self.trusted["targets"] = tg
        return "updated"

    def fetch(self, name, data):
        info = self.trusted["targets"]["signed"]["targets"].get(name)
        if info is None:
            raise TufError("arbitrary-software", f"{name} is not in trusted targets metadata")
        check_blob(data, info, name)
        return info


# ---------------- a repository, as the release pipeline would publish it ----------------
class Repository:
    def __init__(self, name, threshold=2):
        self.k = {r: [Key(f"{name}-{r}-{i}") for i in range(threshold if r == "root" else 1)]
                  for r in ("root", "targets", "snapshot", "timestamp")}
        self.targets, self.custom, self.versions = {}, {}, {"t": 0, "s": 0, "ts": 0}
        self.root_md = self.make_root(self.k["root"])

    def make_root(self, signers, version=1):
        keys = {k.keyid: k.obj for ks in self.k.values() for k in ks}
        roles = {r: {"keyids": [k.keyid for k in ks], "threshold": len(ks) if r == "root" else 1}
                 for r, ks in self.k.items()}
        return sign({"_type": "root", "spec_version": SPEC, "consistent_snapshot": False, "version": version,
                     "expires": "2030-01-01T00:00:00Z", "keys": keys, "roles": roles}, signers)

    def publish(self, expires="2026-11-30T00:00:00Z", ts_version=None, ts_key=None):
        self.versions = {k: v + 1 for k, v in self.versions.items()}
        tg = sign({"_type": "targets", "spec_version": SPEC, "version": self.versions["t"], "expires": expires,
                   "targets": {n: {"length": len(b), "hashes": {"sha256": hashlib.sha256(b).hexdigest()},
                                   "custom": self.custom.get(n, {})} for n, b in self.targets.items()}},
                  self.k["targets"])
        tb = dump(tg)
        sn = sign({"_type": "snapshot", "spec_version": SPEC, "version": self.versions["s"], "expires": expires,
                   "meta": {"targets.json": meta_for(tb, self.versions["t"])}}, self.k["snapshot"])
        sb = dump(sn)
        ts = sign({"_type": "timestamp", "spec_version": SPEC, "version": ts_version or self.versions["ts"],
                   "expires": expires, "meta": {"snapshot.json": meta_for(sb, self.versions["s"])}},
                  [ts_key] if ts_key else self.k["timestamp"])
        return {"targets.json": tb, "snapshot.json": sb, "timestamp.json": dump(ts)}


def uptane_full_verification(director, image, ecu_serial, installed_counter):
    """Director and Image repository Targets must match for every image assigned to this ECU."""
    plan = []
    for name, d in director.trusted["targets"]["signed"]["targets"].items():
        if d["custom"].get("ecu_serial") != ecu_serial:
            continue
        i = image.trusted["targets"]["signed"]["targets"].get(name)
        if i is None:
            raise TufError("arbitrary-software", f"{name} assigned by the Director is not in the Image repository")
        if (d["length"], d["hashes"]) != (i["length"], i["hashes"]):
            raise TufError("mix-and-match", f"{name}: Director and Image repository disagree on length/hashes")
        for field in ("hardware_id", "release_counter"):
            if d["custom"].get(field) != i["custom"].get(field):
                raise TufError("mix-and-match", f"{name}: SHALL-match field {field} differs")
        if i["custom"]["release_counter"] < installed_counter:
            raise TufError("rollback", f"{name}: release counter {i['custom']['release_counter']} < installed")
        plan.append(name)
    return plan


def main():
    now = "2026-10-28T12:00:00Z"
    fails = 0

    def case(name, expect, fn):
        nonlocal fails
        try:
            fn()
            outcome = "accepted"
        except TufError as e:
            outcome = e.kind
        fails += outcome != expect
        print(f"   {'ok  ' if outcome == expect else 'FAIL'} {name:<68} -> {outcome}")

    print("== TUF client workflow")
    repo = Repository("image")
    app = b"\x7fELF app 2.0" * 100
    repo.targets["fw/app-2.0.img"] = app
    files = repo.publish()
    c = Client(repo.root_md)
    case("valid update", "accepted", lambda: (c.refresh(files, now), c.fetch("fw/app-2.0.img", app)))
    case("arbitrary software: target bytes modified", "arbitrary-software",
         lambda: c.fetch("fw/app-2.0.img", b"\x7fELF evil" + b"x" * (len(app) - 9)))
    case("endless data: target longer than its metadata says", "endless-data",
         lambda: c.fetch("fw/app-2.0.img", app + b"\0" * 4096))
    newer = repo.publish()
    c.refresh(newer, now)
    case("rollback: replayed older timestamp", "rollback",
         lambda: c.refresh({**newer, "timestamp.json": files["timestamp.json"]}, now))
    case("freeze: validly signed but expired metadata", "freeze",
         lambda: Client(repo.root_md).refresh(repo.publish(expires="2026-10-01T00:00:00Z"), now))
    a, b = repo.publish(), repo.publish()
    case("mix-and-match: snapshot of release N+1 with targets of release N", "mix-and-match",
         lambda: Client(repo.root_md).refresh({**b, "targets.json": a["targets.json"]}, now))
    forged = sign(json.loads(b["timestamp.json"])["signed"], [Key("attacker")])
    case("forged timestamp: signed by a key not in root", "signature",
         lambda: Client(repo.root_md).refresh({**b, "timestamp.json": dump(forged)}, now))

    print("== root rotation, thresholds and fast-forward recovery (root threshold 2)")
    v1_root, old_root, old_ts = repo.root_md, repo.k["root"], repo.k["timestamp"][0]
    victim = Client(v1_root)                     # attacker holding the OLD timestamp key fast-forwards it
    victim.refresh(repo.publish(ts_version=1000, ts_key=old_ts), now)
    repo.k["root"] = [Key("image-root-new-0"), Key("image-root-new-1")]
    repo.k["timestamp"] = [Key("image-timestamp-rotated")]
    current = repo.publish()
    for label, signers, dup in (("1 of 2 old root keys (+ both new keys)", [old_root[0]] + repo.k["root"], False),
                                ("an old key's signature twice (counted once)", [old_root[0]] + repo.k["root"], True),
                                ("only the NEW root keys", repo.k["root"], False)):
        md = repo.make_root(signers, version=2)
        if dup:
            md["signatures"].append(dict(md["signatures"][0]))
        case(f"root v2 signed by {label}", "signature",
             lambda md=md: Client(v1_root).refresh({**current, "2.root.json": dump(md)}, now))
    v2 = repo.make_root(old_root + repo.k["root"], version=2)
    rotated = {**current, "2.root.json": dump(v2)}
    case("root v2 cross-signed by old and new root keys", "accepted", lambda: Client(v1_root).refresh(rotated, now))
    stale = sign(json.loads(current["timestamp.json"])["signed"], [old_ts])
    case("timestamp signed by the rotated-out timestamp key", "signature",
         lambda: Client(v1_root).refresh({**rotated, "timestamp.json": dump(stale)}, now))
    case("fast-forwarded client (trusted timestamp v1000) recovers after rotation", "accepted",
         lambda: victim.refresh(rotated, now))

    print("== Uptane full verification (Director + Image repository)")
    img = Repository("img")
    brake = b"ECU firmware 4.2" * 64
    img.targets = {"ecu/brake-4.2.bin": brake, "ecu/malware.bin": b"payload" * 32}
    img.custom = {"ecu/brake-4.2.bin": {"hardware_id": "brake-v3", "release_counter": 42},
                  "ecu/malware.bin": {"hardware_id": "brake-v3", "release_counter": 99}}
    image = Client(img.root_md)
    image.refresh(img.publish(), now)

    def director(name, data, custom):
        dr = Repository("director")
        dr.targets, dr.custom = {name: data}, {name: custom}
        cl = Client(dr.root_md)
        cl.refresh(dr.publish(), now)
        return cl

    assign = {"hardware_id": "brake-v3", "release_counter": 42, "ecu_serial": "BRK-0001"}

    def plan_is(expected, d, counter):
        got = uptane_full_verification(d, image, "BRK-0001", counter)
        if got != expected:
            raise TufError("unexpected-plan", str(got))

    case("Director assigns brake-4.2; the Image repository agrees", "accepted",
         lambda: plan_is(["ecu/brake-4.2.bin"], director("ecu/brake-4.2.bin", brake, assign), 41))
    case("compromised Director assigns an image the Image repo lacks", "arbitrary-software",
         lambda: plan_is([], director("ecu/evil.bin", b"evil", assign), 41))
    case("compromised Director changes the hash of a real image", "mix-and-match",
         lambda: plan_is([], director("ecu/brake-4.2.bin", b"tampered" * 128, assign), 41))
    case("Image repo carries malware.bin that no Director assigns: not installed", "accepted",
         lambda: plan_is(["ecu/brake-4.2.bin"], director("ecu/brake-4.2.bin", brake, assign), 41))
    case("both agree, but the release counter is below the installed one", "rollback",
         lambda: plan_is([], director("ecu/brake-4.2.bin", brake, assign), 43))
    print(("ALL PASSED" if not fails else "FAILED") + f": {fails} failure(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
```

```text
== TUF client workflow
   ok   valid update                                                         -> accepted
   ok   arbitrary software: target bytes modified                            -> arbitrary-software
   ok   endless data: target longer than its metadata says                   -> endless-data
   ok   rollback: replayed older timestamp                                   -> rollback
   ok   freeze: validly signed but expired metadata                          -> freeze
   ok   mix-and-match: snapshot of release N+1 with targets of release N     -> mix-and-match
   ok   forged timestamp: signed by a key not in root                        -> signature
== root rotation, thresholds and fast-forward recovery (root threshold 2)
   ok   root v2 signed by 1 of 2 old root keys (+ both new keys)             -> signature
   ok   root v2 signed by an old key's signature twice (counted once)        -> signature
   ok   root v2 signed by only the NEW root keys                             -> signature
   ok   root v2 cross-signed by old and new root keys                        -> accepted
   ok   timestamp signed by the rotated-out timestamp key                    -> signature
   ok   fast-forwarded client (trusted timestamp v1000) recovers after rotation -> accepted
== Uptane full verification (Director + Image repository)
   ok   Director assigns brake-4.2; the Image repository agrees              -> accepted
   ok   compromised Director assigns an image the Image repo lacks           -> arbitrary-software
   ok   compromised Director changes the hash of a real image                -> mix-and-match
   ok   Image repo carries malware.bin that no Director assigns: not installed -> accepted
   ok   both agree, but the release counter is below the installed one       -> rollback
ALL PASSED: 0 failure(s)
```

### 2.3 Key topology

#### The Fragile Way

All four role keys in the CI system's secret store, so the release pipeline can "just sign". Compromise of CI is compromise of root.

#### The Silicon-Hardened Production Way

| Role | Keys | Where | Rotation |
|---|---|---|---|
| root | 3 keys, threshold 2 | Separate offline HSMs, separate custodians, signing ceremony | Yearly; new root cross-signed by old threshold |
| targets (Image repo) | 2 keys, threshold 1, plus a delegation per product line | Release HSM, used only by the release job, human approval | On compromise or yearly |
| snapshot, timestamp | 1 key each | Online signing service (cloud HSM / KMS), short expiry (timestamp: hours) | Frequent; automatic |
| Director targets | Online, per fleet | Director service HSM | Frequent |

Root rotation is a protocol, not a file copy (§2.2 cases 8–13). Version N+1 must carry a threshold of version N's root signatures *and* its own. After timestamp or snapshot keys rotate, clients discard their trusted timestamp and snapshot, which is exactly what lets a fleet recover from a fast-forward attack by a stolen online key.

---

## 3. Failure Modes, Brick Recovery & Post-Mortem Debugging

| Symptom | Cause | Detect | Fix |
|---|---|---|---|
| Whole fleet stops updating at the same hour | Timestamp (or snapshot) metadata expired: the online re-signing job died | Client error `freeze`; repository expiry monitor | Monitor expiries with alerting well before; re-signing is a service with an SLO |
| Devices reject new root | New root not cross-signed by the old threshold; or version skipped | `signature` / `rollback` on root | Rotation runbook: N+1 signed by old *and* new thresholds, every intermediate root published |
| Device accepts nothing after a backend incident | Attacker fast-forwarded timestamp/snapshot versions with a stolen online key | `rollback` errors on honest metadata | Rotate timestamp/snapshot keys in a new root: clients delete trusted timestamp/snapshot (§1.2 step 2) |
| Expiry checks pass on an old replay | Device clock wrong or attacker-settable | Clock drift telemetry | Secure time (Uptane time server, RTC with tamper detection); clamp to a monotonic floor persisted on the device |
| Partial-verification Secondary installs a Director-only image | Director compromised; Secondary trusted Director alone | Image repo audit | Full verification on Primaries; Secondaries full where resources allow; release counters |
| Metadata signature fails after a "harmless" refactor | Different JSON canonicalization on signer and client | Signature failures right after a deploy | One canonicalization implementation, golden test vectors in CI |

**Recovery.**
- **The client side.** TUF clients don't brick devices: every failure leaves the current trusted metadata and the installed system untouched. The danger is a fleet that silently stops updating, so monitor "time since last successful refresh" per device.
- **The server side.** The recovery tools are root rotation (offline ceremony) and key revocation through it. Both need to be rehearsed before they're needed.

---

## 4. L7 Bar-Raiser Q&A Chains

### Chain 1 · "Our images are signed. Why do we need TUF?"

**Initial Prompt:** "Every image we ship is signed and verified by the bootloader. Explain to the VP why we should spend a quarter adopting TUF."

**L5 Answer:** "TUF is the industry standard for secure updates, and it supports key rotation, so we should use it."

**Why L5 Bricks Devices at Scale:** It names features instead of the attacks a signed image doesn't stop:
- **Freeze:** an attacker or a misconfigured CDN serves the old manifest forever, and the fleet stays vulnerable while every check passes.
- **Rollback:** replaying a correctly signed old release with a known CVE.
- **Mix-and-match** of metadata across releases.
- **Theft of the single online signing key**, which the bootloader trusts for everything.

The VP hears "standard" and funds nothing, and the gap stays open.

**L7 Principal Defense:**
- **Map attacks to mechanisms:**
  - expiry and timestamp stop freeze;
  - versions and release counters stop rollback;
  - snapshot and hash chaining stop mix-and-match;
  - role separation with offline threshold root contains a key compromise;
  - lengths stop endless data.
- **Show it** (§2.2: each attack rejected with its class).
- **Keep the bootloader's signature and anti-rollback** for the attacker who bypasses the network entirely.
- **The quarter buys** containment of an online-key compromise, which today is a fleet-wide arbitrary-code event.

### Chain 2 · Counting signatures

**Initial Prompt:** "Code review: the threshold check counts valid signatures in the list and compares with the threshold. Approve?"

**L5 Answer:** "Yes. If there are at least `threshold` valid signatures, the metadata is trusted."

**Why L5 Bricks Devices at Scale:**
- **The same signature listed twice counts twice,** so a threshold of 2 is met with one stolen key.
- **A signature by a key that is valid but not authorized for this role counts too.** For example, a timestamp key signing root.

**L7 Principal Defense:**
- **Count unique keyids** that are listed for *this role* in the trusted root, whose signature verifies over the canonical form, each at most once. This is exactly the spec's requirement (§1.2), and the test is §2.2's duplicated-signature case.
- **Add tests** for:
  - an unauthorized-but-valid key;
  - an unknown keyid;
  - an empty signature list.
- **Use a conformance suite** (the TUF project's) in CI for any client implementation.

### Chain 3 · Rotating a compromised online key

**Initial Prompt:** "Our timestamp key was exfiltrated, and the attacker has pushed timestamp version 1,000,000 to part of the fleet. Those devices now reject our real timestamps as rollbacks. Recover."

**L5 Answer:** "Generate a new timestamp key and start signing with it, with a version number above a million."

**Why L5 Bricks Devices at Scale:**
- **Devices don't know the new key** until root says so, and the old key remains trusted, so the attacker can keep going.
- **Racing the attacker's version numbers** is a contest you can lose. The fix leaves the compromised key valid.

**L7 Principal Defense:**
- **Rotate through root.** Publish root N+1, signed by the old root threshold and its own, listing the new timestamp key.
- **Clients then discard their trusted timestamp and snapshot,** because those role keys changed, and accept the honest, lower-numbered metadata (§2.2, the fast-forward recovery case).
- **This is why root is offline and threshold:** it's the role that can fix everything else.
- **Afterwards:** audit what the attacker signed, shorten timestamp expiry, and move the online keys into an HSM with per-signing audit.

### Chain 4 · Uptane's Director

**Initial Prompt:** "Why does Uptane need two repositories? A single TUF repository already prevents tampering."

**L5 Answer:** "The Director tells each vehicle what to install, and the Image repository stores the files. It's a separation of concerns."

**Why L5 Bricks Devices at Scale:**
- **The Director must be online** to compute per-vehicle assignments, so its keys are the most exposed in the system.
- **With only a Director**, its compromise is arbitrary code execution on every vehicle. Calling it "separation of concerns" misses that the *security* depends on cross-checking.

**L7 Principal Defense:**
- **The Image repository is signed offline,** and full verification requires every Director assignment to match it exactly (length, hashes, hardware id, release counter).
- **So a compromised Director can only reorder or withhold legitimate images,** never introduce one or roll one back (§2.2 Uptane cases).
- **Primaries do full verification.** Constrained Secondaries do partial verification, accepting the residual risk explicitly, or full verification where silicon allows.

### Chain 5 · Time

**Initial Prompt:** "Our devices have no battery-backed RTC and boot at 1970 until NTP syncs. How do TUF expiry checks work?"

**L5 Answer:** "Wait for NTP before checking updates."

**Why L5 Bricks Devices at Scale:**
- **NTP is unauthenticated.** An attacker on the network sets the device's clock to the past, and every expired metadata file looks valid again (freeze/replay).
- **NTS** (authenticated NTP) helps, but needs its own trust and reachability.
- **A 1970 clock with naive checks** either accepts everything or rejects everything.

**L7 Principal Defense:**
- **Use a secure, monotonic time floor.**
  - Persist the latest trusted metadata timestamp, and the latest time attested by a signed time source (Uptane's time server model), on the device.
  - Never let the clock go below that floor.
  - Use NTS where available.
  - Treat "clock below floor" as an error, not a reason to trust old metadata.
- **Fix the update start time once per cycle** (§1.2 step 0).

### Chain 6 · One framework for SOTA and FOTA

**Initial Prompt:** "How does TUF or Uptane relate to the A/B and OSTree mechanisms we already have?"

**L5 Answer:** "They replace them. TUF handles update security, so we don't need signed FITs or verity."

**Why L5 Bricks Devices at Scale:**
- **TUF verifies the network delivery;** it says nothing about what's on the disk at the next boot.
- **Dropping boot-time verification** lets anyone who writes the eMMC bypass all of it.
- **Dropping A/B or OSTree atomicity** leaves verified-but-half-written images.

**L7 Principal Defense:**
- **Compose the layers (§1.5):**
  - TUF/Uptane decides *which* artifact a device should have;
  - the artifact carries its own signature (FIT, OSTree commit, RAUC bundle) verified at install and boot;
  - dm-verity or composefs covers runtime;
  - A/B or OSTree supplies atomicity and fallback (03.1, 03.2);
  - anti-rollback counters make commits irreversible (01.1).
- **Each layer stops what the others can't.**

---

## 5. Invariants Checklist

- [ ] Four roles; root offline with threshold ≥ 2 of 3; online keys only for timestamp/snapshot (and the Director).
- [ ] Threshold counted over unique, role-authorized keyids; canonical JSON from one shared implementation with golden vectors.
- [ ] Root rotation: N+1 signed by old and new thresholds, every intermediate root published; timestamp/snapshot discarded on their key rotation.
- [ ] Expiry checked against a fixed, secure, monotonic time; timestamp expiry short and monitored with alerting.
- [ ] Targets fetched with length bounds and hash checks; images also verified at install and boot by their own signatures.
- [ ] Uptane: full verification on Primaries; release counters in SHALL-match custom metadata; partial verification only where justified.
- [ ] Root signing ceremony and key-compromise runbooks rehearsed.

## 6. References

- The Update Framework specification v1.0.37. <https://theupdateframework.github.io/specification/v1.0.37/>
- Uptane Standard 2.1.0. <https://uptane.org/docs/2.1.0/standard/uptane-standard>
- RFC 8032, Edwards-Curve Digital Signature Algorithm (EdDSA). <https://www.rfc-editor.org/rfc/rfc8032>
- Kuppusamy et al., Mercury: bandwidth-effective prevention of rollback attacks (fast-forward attacks). <https://theupdateframework.io/papers/prevention-rollback-attacks-atc2017.pdf>
- In this KB: [03.2 OSTree pull-side trust](02-libostree-internals-content-addressed-object-store-hardlinks-and-boot-swap.md) · [03.4 update clients and multi-ECU](04-delta-updates-casync-rauc-swupdate-mender-and-atomic-ecu-subnode-flashing.md) · [01.1 anti-rollback](../01-Hardware-Root-of-Trust-Secure-Boot-and-OPTEE/01-bootrom-efuse-otp-puf-and-cryptographic-chain-of-trust.md)
