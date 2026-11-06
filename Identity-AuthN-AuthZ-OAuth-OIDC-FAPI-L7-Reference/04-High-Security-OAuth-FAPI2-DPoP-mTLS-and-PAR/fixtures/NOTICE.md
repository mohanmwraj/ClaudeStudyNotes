# Fixtures: provenance and licensing

Test oracles and normative quotes for Folder 04, fetched on 2026-11-06.

The RFCs are reproduced in full and unmodified. Under the IETF Trust Legal Provisions (BCP 78), RFCs may be copied and distributed in their entirety.

| File | Source | Used by |
|---|---|---|
| `rfc9449.txt` | <https://www.rfc-editor.org/rfc/rfc9449.txt> (DPoP; Figures 2, 13, 14 and §6.1 oracles) | L26 `DpopLab.java`, L27 `SpringDpopLab.java`; file 01 |
| `rfc8705.txt` | <https://www.rfc-editor.org/rfc/rfc8705.txt> (mTLS client auth and certificate-bound tokens) | file 01 |
| `rfc9126.txt` | <https://www.rfc-editor.org/rfc/rfc9126.txt> (PAR; §2.2 request_uri) | L30 `ParJarRarLab.java`; file 02 |
| `rfc9101.txt` | <https://www.rfc-editor.org/rfc/rfc9101.txt> (JAR; §4 RS256 request object and JWK `k2bdc`) | L30 |
| `rfc9396.txt` | <https://www.rfc-editor.org/rfc/rfc9396.txt> (RAR; Figure 1) | L30; file 02 |
| `rfc10017.txt` | <https://www.rfc-editor.org/rfc/rfc10017.txt> (Browser-Based Apps, BCP 212) | L32 `BrowserTokenLab.java`, L33 `BffTokenHandlerLab.java`; file 03 |
| `fapi-security-profile-2_0-final.txt` | <https://openid.net/specs/fapi-security-profile-2_0-final.html> (Final, 22 Feb 2025); HTML stripped, text otherwise unchanged | L30, L31 `SasParLab.java` (conformance table quotes); files 01–02 |
| `fapi-message-signing-2_0-final.txt` | <https://openid.net/specs/fapi-message-signing-2_0-final.html> (Final, 25 Sept 2025); HTML stripped | L30 |
| `oauth-v2-jarm-final.txt` | <https://openid.net/specs/oauth-v2-jarm-final.html> (Final, 9 Nov 2022); HTML stripped | file 02 |

## OpenID Foundation text

The three OpenID texts are reproduced under the OpenID Foundation copyright license stated in each specification. That licence grants "a non-exclusive, royalty free, worldwide copyright license to reproduce, prepare derivative works from, distribute, perform and display" Implementers Drafts and Final Specifications. Copyright © The OpenID Foundation.

The FAPI 2.0 Attacker Model is quoted in files 01–02 and linked, not reproduced: <https://openid.net/specs/fapi-attacker-model-2_0-final.html>.
