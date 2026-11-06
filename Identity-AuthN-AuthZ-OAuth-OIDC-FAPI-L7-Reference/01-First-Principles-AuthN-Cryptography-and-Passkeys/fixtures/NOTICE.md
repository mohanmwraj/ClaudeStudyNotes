# Fixtures: provenance and licensing

These files are **test oracles**. The Folder 01 listings parse vectors, keys and serializations out of them, so no expected value is typed in by hand. All were fetched on 2026-11-05.

| File | Source | Used by |
|---|---|---|
| `rfc4226.txt` | <https://www.rfc-editor.org/rfc/rfc4226.txt> (HOTP; Appendix D vectors) | L3 `Totp.java` |
| `rfc6238.txt` | <https://www.rfc-editor.org/rfc/rfc6238.txt> (TOTP; Appendix A seeds, Appendix B table) | L3 |
| `rfc7693.txt` | <https://www.rfc-editor.org/rfc/rfc7693.txt> (BLAKE2; Appendix A digest) | L1 `Argon2id.java` |
| `rfc9106.txt` | <https://www.rfc-editor.org/rfc/rfc9106.txt> (Argon2; section 5 vectors) | L1 |
| `rfc7515.txt` | <https://www.rfc-editor.org/rfc/rfc7515.txt> (JWS; Appendix A) | L9 `Jose.java` |
| `rfc7516.txt` | <https://www.rfc-editor.org/rfc/rfc7516.txt> (JWE; Appendix A.1, A.3) | L11 `JweLab.java` |
| `rfc7518.txt` | <https://www.rfc-editor.org/rfc/rfc7518.txt> (JWA; Appendix C ECDH-ES) | L11 |
| `rfc7638.txt` | <https://www.rfc-editor.org/rfc/rfc7638.txt> (JWK thumbprint; section 3.1) | L9 |
| `rfc8037.txt` | <https://www.rfc-editor.org/rfc/rfc8037.txt> (Ed25519 in JOSE; Appendix A) | L9 |
| `w3c-webauthn-l3-sec16-test-vectors.txt` | Section 16 "Test Vectors" of *Web Authentication Level 3*, W3C Recommendation, 25 August 2026, <https://www.w3.org/TR/webauthn-3/>, with HTML tags and entities stripped and the content otherwise unchanged | L7 `WebAuthnRp.java` |

**Licensing.**
- The RFCs are reproduced in full and unmodified. Under the IETF Trust Legal Provisions (BCP 78), RFCs may be copied and distributed in their entirety.
- The W3C extract is a portion of a W3C Recommendation published under the W3C Software and Document License (<https://www.w3.org/copyright/software-license/>), the "permissive document license" the specification names. Copyright © 2026 World Wide Web Consortium. Source URL above.
