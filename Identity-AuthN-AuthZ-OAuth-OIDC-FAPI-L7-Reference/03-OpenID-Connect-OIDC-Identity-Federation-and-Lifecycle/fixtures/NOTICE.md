# Fixtures: provenance and licensing

Test oracles and normative quotes for Folder 03, fetched on 2026-11-06.

The RFCs are reproduced in full and unmodified. Under the IETF Trust Legal Provisions (BCP 78), RFCs may be copied and distributed in their entirety.

| File | Source | Used by |
|---|---|---|
| `oidc-core-1_0-appendix-a.txt` | Appendix A of <https://openid.net/specs/openid-connect-core-1_0.html> (OpenID Connect Core 1.0 incorporating errata set 2); HTML stripped, text otherwise unchanged | L20 `OidcIdTokenLab.java` (A.2–A.6 tokens, A.7 key, `at_hash`/`c_hash` oracles) |
| `rfc7522.txt` | <https://www.rfc-editor.org/rfc/rfc7522.txt> (SAML 2.0 profile for OAuth 2.0 client authentication and grants) | file 02 |
| `rfc7643.txt` | <https://www.rfc-editor.org/rfc/rfc7643.txt> (SCIM core schema) | file 02, L23 `ScimLab.java` |
| `rfc7644.txt` | <https://www.rfc-editor.org/rfc/rfc7644.txt> (SCIM protocol: filters §3.4.2.2, PATCH §3.5.2, ETags §3.14) | file 02, L23 |
| `rfc8417.txt` | <https://www.rfc-editor.org/rfc/rfc8417.txt> (Security Event Token; `exp` NOT RECOMMENDED, §4.1 confusion) | file 03, L24 `LogoutCaepLab.java` |
| `rfc8725.txt` | <https://www.rfc-editor.org/rfc/rfc8725.txt> (JWT BCP; §2.8 cross-JWT confusion, §3.11 explicit typing) | files 01 and 03 |
| `rfc8935.txt` | <https://www.rfc-editor.org/rfc/rfc8935.txt> (push-based SET delivery; 202 and error codes) | file 03, L24 |
| `rfc8936.txt` | <https://www.rfc-editor.org/rfc/rfc8936.txt> (poll-based SET delivery) | file 03 |

## OpenID Foundation text

The Appendix A extract is reproduced under the OpenID Foundation copyright license stated in each OIDF specification. That licence grants "a non-exclusive, royalty free, worldwide copyright license to reproduce, prepare derivative works from, distribute, perform and display" Implementers Drafts and Final Specifications. Copyright © The OpenID Foundation.

The other OpenID specifications quoted in this folder are linked, not reproduced:
- Back-Channel, Front-Channel and RP-Initiated Logout 1.0;
- Shared Signals Framework 1.0 and CAEP 1.0;
- Discovery 1.0.

See the References section of each file.
