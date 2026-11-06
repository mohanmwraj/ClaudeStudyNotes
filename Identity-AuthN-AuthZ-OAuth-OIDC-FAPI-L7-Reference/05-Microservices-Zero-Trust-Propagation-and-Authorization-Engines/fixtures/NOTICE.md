# Fixtures: provenance and licensing

Test oracles and normative quotes for Folder 05, fetched on 2026-11-06.

| File | Source | Used by |
|---|---|---|
| `rfc7662.txt` | <https://www.rfc-editor.org/rfc/rfc7662.txt> (Token Introspection; §2.2 example response) | L34 `PhantomTokenLab.java`; file 01 |
| `rfc9068.txt` | <https://www.rfc-editor.org/rfc/rfc9068.txt> (JWT access tokens, `at+jwt`) | L34 |
| `rfc9701.txt` | <https://www.rfc-editor.org/rfc/rfc9701.txt> (JWT introspection responses) | L34 |
| `rfc8693.txt` | <https://www.rfc-editor.org/rfc/rfc8693.txt> (Token Exchange; Figure 6 nested `act`) | L36 `TokenExchangeLab.java`; file 02 |
| `rfc8707.txt` | <https://www.rfc-editor.org/rfc/rfc8707.txt> (Resource Indicators) | files 01–02 |
| `SPIFFE-ID.md`, `X509-SVID.md`, `JWT-SVID.md`, `SPIFFE_Trust_Domain_and_Bundle.md` | <https://github.com/spiffe/spiffe/tree/main/standards> at commit `03e916d8f920e5dd0b39e625868ba26c2c3ad687` (2026-10-29) | L38 `SpiffeSvidLab.java`; file 02 |

## Licensing

- The RFCs are reproduced in full and unmodified. Under the IETF Trust Legal Provisions (BCP 78), RFCs may be copied and distributed in their entirety.
- The SPIFFE standards are reproduced unmodified from the SPIFFE project. That repository is licensed under the Apache License 2.0 (<https://github.com/spiffe/spiffe/blob/main/LICENSE>). Copyright the SPIFFE authors.

The Zanzibar paper (file 04) is cited and linked, not reproduced: <https://www.usenix.org/conference/atc19/presentation/pang>.
