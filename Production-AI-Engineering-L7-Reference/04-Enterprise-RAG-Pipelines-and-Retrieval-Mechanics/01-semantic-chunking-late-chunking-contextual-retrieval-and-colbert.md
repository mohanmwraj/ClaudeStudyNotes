# 01 · Chunking: Semantic Splits, Late Chunking, Contextual Retrieval, and ColBERT

> **Folder:** `04-Enterprise-RAG-Pipelines-and-Retrieval-Mechanics/` · **File 1 of 3**
> **Anchoring papers and posts:** Lewis et al., *Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks*
> (NeurIPS 2020) · Anthropic, *Introducing Contextual Retrieval* (2024) · Günther et al., *Late Chunking: Contextual
> Chunk Embeddings Using Long-Context Embedding Models* (2024) · Khattab & Zaharia, *ColBERT* (SIGIR 2020) ·
> Santhanam et al., *ColBERTv2* (NAACL 2022) and *PLAID* (CIKM 2022) · Kamradt, *5 Levels of Text Splitting* (semantic
> chunking, 2024).
> **Code baseline:** Python 3.10+ (CPython 3.14.5 + NumPy 2.5.4) · Java 21 (JDK 25.0.4, `--release 21`).
> **Previous folder:** [03 · IVF-PQ and engine comparison](../03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/03-ivf-pq-scalar-binary-quantization-and-pgvector-vs-qdrant-milvus.md) ·
> **Next:** [02 · Hybrid search, RRF, reranking](02-hybrid-search-bm25-splade-dense-rrf-and-cross-encoder-reranking.md)

---

## 0. The thesis in one paragraph

A RAG system can only retrieve what its chunks say on their own. Writers state facts with **pronouns, section
context, and references to earlier paragraphs** ("*Its* population is 412k"), and a chunk cut out of its document
loses that context. Its embedding no longer contains the entity the user asks about. On a corpus built to contain
exactly this failure, paragraph chunks reach **0.287 recall@1** and naive fixed-size chunks **0.000**. Four fixes
attack the same loss from different sides:

- **Structure-aware chunking** keeps semantic units intact.
- **Contextual Retrieval** prepends an LLM-written situating sentence before embedding.
- **Late chunking** embeds the whole document first, so every token embedding already carries document context, and
  pools per chunk afterward.
- **ColBERT late interaction** keeps one vector per token and matches each query token separately, avoiding the
  dilution of single-vector pooling.

In the lab, contextual retrieval and late chunking lift recall@5 to **1.000**. ColBERT on contextual chunks reaches
**1.000 recall@1**, at several times the storage. Chunking is also a data-engineering contract: exact offsets for
citations, section paths, and **content-addressed IDs** so re-ingestion re-embeds only what changed.

---

## 1. First principles: what a chunk embedding can and cannot know

### 1.1 Single-vector pooling is a lossy summary

A bi-encoder maps a chunk to one vector $e(c)$, typically by mean-pooling contextualized token states. Relevance is
$\cos(e(q), e(c))$. Two losses follow:

1. **Context loss at the boundary.** Tokens outside the chunk never influence $e(c)$. A pronoun's referent in the
   previous paragraph is invisible.
2. **Dilution inside the chunk.** Pooling averages all content. A chunk about five topics is a weak match for any one
   of them, and a short query matches a long chunk only partially.

Chunk size trades these off. Big chunks keep context but dilute; small chunks are precise but orphaned. There is no
universally right size. There is a right size **for your documents, queries and embedding model**, found by measuring
recall on your own query set.

### 1.2 The strategies

| Strategy | What it does | Fixes | Costs |
|----------|-------------|-------|-------|
| Fixed-size tokens | slice every N tokens (± overlap) | nothing; baseline | cuts sentences, code and tables; orphans pronouns |
| Recursive / structure-aware | split by headings → paragraphs → sentences → words, under a token budget | broken units | still orphans cross-paragraph references |
| Semantic chunking | split where adjacent-sentence embedding similarity drops | topic shifts inside sections | an embedding call per sentence at ingest; unstable boundaries |
| **Contextual Retrieval** | an LLM writes a 50–100-token context per chunk ("This chunk is from X's 2023 10-K, section Y…"), prepended before embedding and BM25 indexing | coreference, implicit subject | one LLM call per chunk at ingest; prompt caching of the full document makes it affordable |
| **Late chunking** | run a long-context embedder over the whole document, then mean-pool token states per chunk span | coreference without an LLM | the document must fit the encoder's context window; the model must be suitable |
| **ColBERT (late interaction)** | store every token's vector; score $\sum_{i\in q}\max_{j\in c} \langle q_i, d_j\rangle$ (MaxSim) | dilution, multi-aspect queries | ~one vector per token; needs PLAID-style compression and a dedicated index |
| Parent–child / small-to-big | retrieve small chunks, return their parent section to the LLM | precise hits with enough context to answer | more context tokens per answer |

Anthropic reported that Contextual Embeddings plus Contextual BM25 reduce top-20 retrieval failures by 49%, and by
67% with reranking (⚠ their benchmark, verify on your corpus). Late chunking (Jina AI) reports consistent gains
specifically on documents with long-range references.

### 1.3 The lab: reproducing the failure and the fixes

`chunking_lab.py` builds 20 city profiles × 4 paragraphs. Only the first paragraph names the city, and the other
three state facts with "Its…". The "encoder" is a transparent toy: hash-seeded word vectors, bag-of-words pooling,
pronouns carry nothing. That is exactly why naive chunks fail, and it is a mechanism demo, not a benchmark. Queries
ask "*{city}* population / economy / climate / founding".

| Strategy | Recall@1 | Recall@5 | Vectors stored |
|----------|---------:|---------:|---------------:|
| fixed 12-token chunks | **0.000** | 0.050 | 80 |
| paragraph chunks | 0.287 | 0.425 | 80 |
| contextual retrieval (prefix) | 0.713 | **1.000** | 80 |
| late chunking (document-contextualized tokens) | 0.613 | **1.000** | 80 |
| ColBERT MaxSim, paragraph | 0.263 | 0.463 | 360 tokens |
| **ColBERT MaxSim, contextual** | **1.000** | **1.000** | 680 tokens |

What each row teaches:

1. **Fixed windows destroy the answer.** They split "Its population is" from "412k residents", so no chunk contains
   both the cue and the fact.
2. **Paragraph chunks keep units intact but orphan the subject.** The query's entity term has nothing to match.
3. **Context puts the right chunk in the top 5 every time**, but recall@1 trails (0.71 / 0.61). The prefix adds the
   city name to *every* chunk of that document, and the name-dense "founding" paragraph competes at rank 1. Pooling
   dilutes the "population" signal. This is the gap a reranker (File 02) closes.
4. **ColBERT MaxSim resolves it.** Each query token is matched to its best chunk token, so "population" must find
   "population" and "avalon" must find "avalon". The price is one vector per token. In production, a 512-token passage
   with 128-d vectors under PLAID's residual compression costs on the order of tens of KB vs ~3 KB for one float32
   768-d vector, so plan **several times the storage** plus a specialized index.

### 1.4 Late chunking, precisely

Standard pipeline: chunk → encode each chunk separately → pool. Late chunking reverses the order:

```
tokens = tokenize(whole document)                 (must fit the encoder's window: 8K-32K for modern embedders)
H      = encoder(tokens)                          (every h_i has attended to the whole document)
for each chunk span [a, b):  e(chunk) = mean(h_a ... h_{b-1})     (then normalize)
```

The chunk boundaries are applied **after** contextualization, so "Its" in paragraph 3 has already attended to the
city's name in paragraph 1. There is no LLM call and no extra tokens in the index. It requires a long-context
embedding model whose token states are meaningful for pooling (it works best with mean-pooled models; ⚠ verify per
model). Documents longer than the window need overlapping macro-windows.

### 1.5 Contextual Retrieval, operationally

Per chunk, a prompt: *"Here is the whole document … Here is a chunk … Give a short succinct context to situate this
chunk within the overall document for the purposes of improving search retrieval."* The output (50–100 tokens) is
prepended to the chunk for **both** the embedding and the BM25 index. Cost control:

- **Prompt caching.** The full document is a stable prefix across all of its chunks, which is exactly Folder 01 File
  03's prefix-cache physics. With caching, per-chunk cost is dominated by the chunk plus the output tokens.
- **A small, fast model**, batched at ingest. Contexts are cached by chunk content hash, so they are regenerated only
  when a chunk changes (§2).
- **A domain template.** The context should name what users search for (product, customer, fiscal period, system
  name), and the prompt should say so.

---

## 2. Chunking as a data contract (the Java blueprint)

Retrieval quality is half of chunking. The other half is that **chunks are records** that must support citations,
updates, deletes and audits:

| Requirement | Why | Implementation (§3.2) |
|------------|-----|----------------------|
| Exact source offsets | citations link to the exact span; highlight in the UI; legal/audit | `text == source.substring(start, end)` asserted for every chunk |
| Section path | context for the prefix; filtering ("only in Runbooks > Incidents") | heading stack → `"Payments Service Runbook > Incident: settlement backlog"` |
| Atomic units | code blocks, tables and lists are meaningless when split | fenced blocks are never split, even if they exceed the budget |
| Token budget measured with the **embedding model's tokenizer** | a word count misestimates subword tokens 1.3–2× | pluggable `ToIntFunction<String>`; the test uses words |
| Overlap | spans that straddle a boundary appear in both chunks | carry back whole units up to `overlapTokens`, never into atomic blocks |
| **Content-addressed IDs** | idempotent upserts; incremental re-embedding; stale-chunk deletion | `SHA-256(docId, sectionPath, text)`: a one-number edit changes **1 of 5** IDs |

The ID design decision is the subtle one. Including the document **version** in the ID (the first draft of the
listing did this) changes every ID on every edit, which forces a full re-embed and a full delete of the old chunks.
Content addressing keeps unchanged chunks' IDs (and embeddings, and contextual prefixes) stable. The ingestion
pipeline (File 03) then upserts the new IDs and deletes the IDs that disappeared.

---

## 3. Production code blueprints

### 3.1 Python: the coreference failure and four fixes

```python
"""chunking_lab.py - why chunking strategy decides RAG recall: fixed-size vs paragraph chunks, Contextual Retrieval,
late chunking, and ColBERT MaxSim, on a corpus built to contain the classic failure (facts stated with pronouns).

The "encoder" is a transparent toy: hash-seeded word vectors, bag-of-words pooling, stop-words and pronouns carry no
content. Late chunking is modelled as document-contextualized token vectors (token + lambda * document mean), the
effect long-context attention has on real token embeddings. Mechanisms transfer; absolute numbers do not.
"""
from __future__ import annotations

import hashlib
import re

import numpy as np

D = 256
STOP = set("a an the is was are were of in on at to and or with during include includes relies its it it's this that "
           "these those their they city located region founded residents period grew quickly major employers climate "
           "rainfall economy population".split()) - {"population", "economy", "climate", "rainfall", "founded", "region"}
_cache: dict[str, np.ndarray] = {}


def wvec(w: str) -> np.ndarray:
    if w not in _cache:
        seed = int.from_bytes(hashlib.blake2b(w.encode(), digest_size=8).digest(), "little")
        v = np.random.default_rng(seed).standard_normal(D)
        _cache[w] = v / np.linalg.norm(v)
    return _cache[w]


def tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def content(toks: list[str]) -> list[str]:
    return [t for t in toks if t not in STOP]


def embed(text: str) -> np.ndarray:
    vs = [wvec(t) for t in content(tokens(text))]
    v = np.sum(vs, axis=0) if vs else np.zeros(D)
    return v / (np.linalg.norm(v) + 1e-12)


# ---------------------------------------------------------------------- corpus
NAMES = ("avalon brightwater cindermoor dunhallow emberfall frostholm glenrae harrowgate ironvale juniper "
         "kestrel lowmere marrowdale northcliff oakhaven pellmar quillon ravenmoor stonebrook thornwick").split()
INDUSTRY = "shipbuilding textiles software tourism mining fishing logistics pharmaceuticals".split()
CLIMATE = "temperate arid humid alpine maritime".split()
ERA = "industrial colonial postwar digital".split()


def corpus(seed: int = 3):
    rng = np.random.default_rng(seed)
    docs = []
    for i, name in enumerate(NAMES):
        pop = f"{rng.integers(100, 999)}k"
        ind = rng.choice(INDUSTRY, 2, replace=False)
        paras = [
            ("founding", f"{name.title()} is a city located in the {rng.choice(['north', 'south', 'east', 'west'])} "
                         f"region. {name.title()} was founded in {1600 + 7 * i}."),
            ("population", f"Its population is {pop} residents. The city grew quickly during the "
                           f"{rng.choice(ERA)} period."),
            ("economy", f"Its economy relies on {ind[0]} and {ind[1]}. Major employers include "
                        f"{name[:3]}corp and {name[-3:]}works."),
            ("climate", f"The climate is {rng.choice(CLIMATE)} with {rng.integers(300, 1500)}mm rainfall."),
        ]
        docs.append({"name": name, "paras": paras})
    return docs


QUERIES = {"population": "{n} population", "economy": "{n} economy industries", "climate": "{n} climate rainfall",
           "founding": "{n} founded region"}


# ---------------------------------------------------------------------- chunkers
def chunk_fixed(doc, size: int = 12):
    toks = tokens(" ".join(p for _, p in doc["paras"]))
    return [" ".join(toks[i:i + size]) for i in range(0, len(toks), size)]


def chunk_paragraph(doc):
    return [p for _, p in doc["paras"]]


def contextual_prefix(doc) -> str:
    """Stand-in for Contextual Retrieval's LLM call: 'situate this chunk within the whole document'."""
    return f"This chunk is from the profile of the city of {doc['name'].title()}."


def late_chunk_vectors(doc, lam: float = 1.5) -> list[np.ndarray]:
    """Embed the WHOLE document at token level (context mixes into every token), THEN pool per chunk span."""
    paras = chunk_paragraph(doc)
    all_content = [t for p in paras for t in content(tokens(p))]
    doc_ctx = np.mean([wvec(t) for t in all_content], axis=0)
    out = []
    for p in paras:
        toks = content(tokens(p))
        v = np.sum([wvec(t) + lam * doc_ctx for t in toks], axis=0)
        out.append(v / np.linalg.norm(v))
    return out


def maxsim(q: str, chunk_text: str) -> float:
    """ColBERT late interaction: sum over query tokens of the best-matching chunk token."""
    qt = [wvec(t) for t in content(tokens(q))]
    dt = np.array([wvec(t) for t in content(tokens(chunk_text))])
    return float(sum(np.max(dt @ v) for v in qt)) if len(dt) else 0.0


def evaluate():
    docs = corpus()
    results = {}

    def relevant(doc_idx, kind, text, d):
        """A chunk is relevant if it belongs to the right document and carries the fact's answer token."""
        para = dict(d["paras"])[kind]
        answer = [t for t in content(tokens(para)) if t not in {"population", "economy", "climate", "rainfall",
                                                                  "founded", "region"}][-1]
        return answer in tokens(text)

    strategies = {
        "fixed 12-token chunks": lambda d: [(c, embed(c)) for c in chunk_fixed(d)],
        "paragraph chunks": lambda d: [(c, embed(c)) for c in chunk_paragraph(d)],
        "contextual retrieval": lambda d: [(c, embed(contextual_prefix(d) + " " + c)) for c in chunk_paragraph(d)],
        "late chunking": lambda d: list(zip(chunk_paragraph(d), late_chunk_vectors(d))),
    }
    for name, fn in strategies.items():
        index = [(di, text, vec) for di, d in enumerate(docs) for text, vec in fn(d)]
        mat = np.array([v for _, _, v in index])
        r1 = r5 = 0
        total = 0
        for di, d in enumerate(docs):
            for kind, tmpl in QUERIES.items():
                qv = embed(tmpl.format(n=d["name"]))
                order = np.argsort(-(mat @ qv))
                hits = [relevant(di, kind, index[j][1], d) and index[j][0] == di for j in order[:5]]
                r1 += hits[0]
                r5 += any(hits)
                total += 1
        results[name] = (r1 / total, r5 / total, len(index))

    for name, use_ctx in (("ColBERT MaxSim, paragraph", False), ("ColBERT MaxSim, contextual", True)):
        index = [(di, text, (contextual_prefix(d) + " " + text) if use_ctx else text)
                 for di, d in enumerate(docs) for text in chunk_paragraph(d)]
        r1 = r5 = 0
        total = 0
        tok_count = sum(len(content(tokens(t))) for _, _, t in index)
        for di, d in enumerate(docs):
            for kind, tmpl in QUERIES.items():
                q = tmpl.format(n=d["name"])
                scores = np.array([maxsim(q, t) for _, _, t in index])
                order = np.argsort(-scores)
                hits = [relevant(di, kind, index[j][1], d) and index[j][0] == di for j in order[:5]]
                r1 += hits[0]
                r5 += any(hits)
                total += 1
        results[name] = (r1 / total, r5 / total, tok_count)
    return results


def main() -> None:
    res = evaluate()
    print(f"{len(NAMES)} city profiles x 4 paragraphs; 3 of 4 facts are stated with pronouns ('Its population is ...')")
    print(f"{'strategy':28s} {'recall@1':>9s} {'recall@5':>9s} {'vectors stored':>15s}")
    for name, (r1, r5, nvec) in res.items():
        print(f"{name:28s} {r1:9.3f} {r5:9.3f} {nvec:15d}")
    para, ctx, late = res["paragraph chunks"], res["contextual retrieval"], res["late chunking"]
    assert para[0] < 0.4, "pronoun-only chunks cannot be matched to their entity"
    assert ctx[1] == 1.0 and late[1] == 1.0, "context puts the right chunk in the top 5 every time"
    assert ctx[0] > para[0] + 0.3 and late[0] > para[0] + 0.3
    # Pooling dilutes: the name-heavy 'founding' chunk can outrank the right one at rank 1. MaxSim matches each
    # query token separately, so 'population' must find 'population' - the late-interaction advantage.
    assert res["ColBERT MaxSim, contextual"][0] > ctx[0] + 0.2
    colbert_vectors = res["ColBERT MaxSim, paragraph"][2]
    print(f"\nColBERT stores one vector per token: {colbert_vectors} vs {para[2]} single vectors "
          f"({colbert_vectors / para[2]:.1f}x); at 128-d int8 residuals (PLAID-style) that is still "
          f"~{colbert_vectors / para[2] * 128 / (768 * 4):.2f}x the bytes of 768-d float32 single vectors")
    print("\nall chunking self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
20 city profiles x 4 paragraphs; 3 of 4 facts are stated with pronouns ('Its population is ...')
strategy                      recall@1  recall@5  vectors stored
fixed 12-token chunks            0.000     0.050              80
paragraph chunks                 0.287     0.425              80
contextual retrieval             0.713     1.000              80
late chunking                    0.613     1.000              80
ColBERT MaxSim, paragraph        0.263     0.463             360
ColBERT MaxSim, contextual       1.000     1.000             680

ColBERT stores one vector per token: 360 vs 80 single vectors (4.5x); at 128-d int8 residuals (PLAID-style) that is still ~0.19x the bytes of 768-d float32 single vectors

all chunking self-checks passed
```

### 3.2 Java 21: a structure-aware, citation-safe, idempotent chunker

```java
// ChunkingPipeline.java - Java 21 production chunker for RAG ingestion: structure-aware recursive splitting
// (sections -> paragraphs -> sentences -> words), token budgets with overlap, atomic code/table blocks, exact source
// offsets for citations, a contextual header per chunk, and content-addressed chunk ids for idempotent upserts.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out ChunkingPipeline.java
//                     java -ea -cp out dev.l7.ai.inference.ChunkingPipeline
package dev.l7.ai.inference;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.function.ToIntFunction;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ChunkingPipeline {

    /** A chunk: text is EXACTLY source.substring(start, end); header is prepended only for embedding. */
    public record Chunk(String id, String docId, int docVersion, String sectionPath, int start, int end, String text,
                        String embedText, int tokens) {}

    public record Config(int maxTokens, int overlapTokens, ToIntFunction<String> tokenizer) {}

    /** Whitespace word count; production plugs in the embedding model's own tokenizer. */
    static int words(String s) {
        int n = 0;
        boolean in = false;
        for (int i = 0; i < s.length(); i++) {
            boolean ws = Character.isWhitespace(s.charAt(i));
            if (!ws && !in) n++;
            in = !ws;
        }
        return n;
    }

    private record Span(int start, int end, boolean atomic) {}

    private static final Pattern HEADING = Pattern.compile("(?m)^(#{1,6})\\s+(.+)$");
    private static final Pattern FENCE = Pattern.compile("(?ms)^```.*?^```\\s*$");
    private static final Pattern SENTENCE = Pattern.compile("[^.!?\\n]+(?:[.!?]+|$)\\s*");

    private final Config cfg;

    public ChunkingPipeline(Config cfg) {
        if (cfg.overlapTokens() >= cfg.maxTokens()) throw new IllegalArgumentException("overlap must be < max");
        this.cfg = cfg;
    }

    public List<Chunk> chunk(String docId, int version, String title, String src) {
        List<Chunk> out = new ArrayList<>();
        // 1) sections by headings; remember the heading path for context and citations
        Matcher h = HEADING.matcher(src);
        List<int[]> sections = new ArrayList<>();
        List<String> paths = new ArrayList<>();
        String[] stack = new String[7];
        int prev = 0;
        String prevPath = title;
        while (h.find()) {
            if (h.start() > prev) {
                sections.add(new int[] {prev, h.start()});
                paths.add(prevPath);
            }
            int level = h.group(1).length();
            stack[level] = h.group(2).trim();
            for (int l = level + 1; l < stack.length; l++) stack[l] = null;
            StringBuilder p = new StringBuilder();
            for (int l = 1; l <= level; l++) {
                if (stack[l] == null || (l == 1 && stack[l].equals(title))) continue;   // H1 == title: don't repeat it
                p.append(p.isEmpty() ? "" : " > ").append(stack[l]);
            }
            prevPath = p.isEmpty() ? title : title + " > " + p;
            prev = h.start();
        }
        sections.add(new int[] {prev, src.length()});
        paths.add(prevPath);

        for (int s = 0; s < sections.size(); s++) {
            List<Span> units = units(src, sections.get(s)[0], sections.get(s)[1]);
            pack(docId, version, title, paths.get(s), src, units, out);
        }
        return out;
    }

    /** Paragraph-level units; fenced code blocks are atomic; oversize paragraphs split by sentence, then words. */
    private List<Span> units(String src, int from, int to) {
        List<Span> spans = new ArrayList<>();
        String sec = src.substring(from, to);
        Matcher f = FENCE.matcher(sec);
        int cursor = 0;
        while (f.find()) {
            paragraphs(src, from + cursor, from + f.start(), spans);
            spans.add(new Span(from + f.start(), from + f.end(), true));
            cursor = f.end();
        }
        paragraphs(src, from + cursor, to, spans);
        return spans;
    }

    private void paragraphs(String src, int from, int to, List<Span> spans) {
        int i = from;
        while (i < to) {
            int j = src.indexOf("\n\n", i);
            int end = (j < 0 || j >= to) ? to : j + 2;
            if (!src.substring(i, end).isBlank()) {
                if (cfg.tokenizer().applyAsInt(src.substring(i, end)) <= cfg.maxTokens()) spans.add(new Span(i, end, false));
                else sentences(src, i, end, spans);
            } else if (!spans.isEmpty()) {
                Span last = spans.remove(spans.size() - 1);                  // keep blank lines with the previous unit
                spans.add(new Span(last.start(), end, last.atomic()));
            }
            i = end;
        }
    }

    private void sentences(String src, int from, int to, List<Span> spans) {
        Matcher m = SENTENCE.matcher(src).region(from, to);
        int last = from;
        while (m.find()) {
            if (m.end() == m.start()) break;
            int start = last;                                                // absorb any gap so offsets stay contiguous
            if (cfg.tokenizer().applyAsInt(src.substring(start, m.end())) <= cfg.maxTokens()) {
                spans.add(new Span(start, m.end(), false));
            } else {
                int a = start;                                               // a single monster sentence: split by words
                Matcher w = Pattern.compile("\\S+\\s*").matcher(src).region(start, m.end());
                int count = 0;
                while (w.find()) {
                    if (++count == cfg.maxTokens()) {
                        spans.add(new Span(a, w.end(), false));
                        a = w.end();
                        count = 0;
                    }
                }
                if (a < m.end()) spans.add(new Span(a, m.end(), false));
            }
            last = m.end();
        }
        if (last < to) spans.add(new Span(last, to, false));
    }

    /** Greedy packing of units into chunks under the budget, with token overlap carried between chunks. */
    private void pack(String docId, int version, String title, String path, String src, List<Span> units, List<Chunk> out) {
        int i = 0;
        while (i < units.size()) {
            int start = units.get(i).start(), end = units.get(i).end();
            int j = i + 1;
            while (j < units.size()
                    && cfg.tokenizer().applyAsInt(src.substring(start, units.get(j).end())) <= cfg.maxTokens()) {
                end = units.get(j).end();
                j++;
            }
            emit(docId, version, title, path, src, start, end, out);
            if (j >= units.size()) break;
            int k = j;                                                       // step back for overlap, never into atomic units
            while (k - 1 > i && !units.get(k - 1).atomic()
                    && cfg.tokenizer().applyAsInt(src.substring(units.get(k - 1).start(), end)) <= cfg.overlapTokens()) k--;
            i = k;
        }
    }

    private void emit(String docId, int version, String title, String path, String src, int start, int end, List<Chunk> out) {
        String text = src.substring(start, end);
        String header = "Document: " + title + ". Section: " + path + ".";   // Contextual-Retrieval-style prefix
        out.add(new Chunk(id(docId, path, text), docId, version, path, start, end, text,
                header + "\n" + text, cfg.tokenizer().applyAsInt(text)));
    }

    /** Deterministic, content-addressed id (doc + section + text, NOT version or offsets): re-ingesting is a no-op
     *  upsert, and a new version re-embeds only the chunks whose content changed; stale ids are deleted. */
    static String id(String docId, String sectionPath, String text) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update((docId + "|" + sectionPath + "|").getBytes(StandardCharsets.UTF_8));
            md.update(text.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(md.digest(), 0, 12);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The naive baseline: fixed windows of N words, blind to structure. */
    static List<String> naiveFixed(String src, int n) {
        String[] w = src.trim().split("\\s+");
        List<String> out = new ArrayList<>();
        for (int i = 0; i < w.length; i += n) out.add(String.join(" ", java.util.Arrays.copyOfRange(w, i, Math.min(w.length, i + n))));
        return out;
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        String doc = """
                # Payments Service Runbook

                The payments service settles card transactions. It depends on the ledger and the fraud scorer.

                ## Incident: settlement backlog

                When the settlement queue exceeds 50,000 messages, page the on-call. It usually means the ledger is slow.
                Check ledger p99 first. If it is above 800 ms, fail over to the secondary region.

                ```bash
                kubectl -n payments scale deploy/settler --replicas=24
                kubectl -n payments rollout status deploy/settler
                ```

                ## Configuration

                The retry budget is 10% of requests. Timeouts are 2 s for the ledger and 300 ms for the fraud scorer. \
                Idempotency keys are required on every POST. Keys expire after 24 hours. Duplicate keys return the \
                original response. This paragraph is deliberately long so that the sentence splitter has to work, \
                because a single paragraph that exceeds the budget must be split on sentence boundaries, never mid-word.
                """;
        ChunkingPipeline p = new ChunkingPipeline(new Config(40, 8, ChunkingPipeline::words));
        List<Chunk> chunks = p.chunk("runbook-payments", 3, "Payments Service Runbook", doc);
        for (Chunk c : chunks) {
            String flat = c.text().strip().replace("\n", " / ");
            System.out.printf("%s  [%4d,%4d) %2d tok  %-52s | %s%n", c.id(), c.start(), c.end(), c.tokens(), c.sectionPath(),
                    flat.substring(0, Math.min(56, flat.length())));
        }
        // Invariants
        int covered = 0;
        for (Chunk c : chunks) {
            check(doc.substring(c.start(), c.end()).equals(c.text()), "offsets reproduce the source exactly (citations)");
            check(c.tokens() <= 40 || c.text().contains("```"), "budget respected (atomic code blocks excepted)");
            check(c.embedText().startsWith("Document: Payments Service Runbook. Section: "), "contextual header");
            covered = Math.max(covered, c.end());
        }
        check(covered == doc.length() && chunks.get(0).start() == 0, "full coverage");
        check(chunks.stream().filter(c -> c.text().contains("```bash")).allMatch(c -> c.text().contains("rollout status")),
                "code block is never split");
        check(chunks.stream().noneMatch(c -> c.text().matches("(?s).*\\bsentence boun$")), "no mid-word cuts");
        List<Chunk> again = p.chunk("runbook-payments", 3, "Payments Service Runbook", doc);
        check(again.stream().map(Chunk::id).toList().equals(chunks.stream().map(Chunk::id).toList()), "ids are deterministic");
        List<Chunk> v4 = p.chunk("runbook-payments", 4, "Payments Service Runbook", doc.replace("800 ms", "900 ms"));
        long changed = v4.stream().map(Chunk::id).filter(id -> chunks.stream().noneMatch(c -> c.id().equals(id))).count();
        System.out.printf("%nre-ingest same version: %d/%d ids identical; v4 edits one number: %d/%d ids change "
                + "(only that chunk is re-embedded; its old id is deleted)%n", chunks.size(), chunks.size(), changed, v4.size());
        check(changed == 1, "content-addressed ids make re-ingestion incremental");

        List<String> naive = naiveFixed(doc, 40);
        long midSentence = naive.stream().filter(s -> !s.matches("(?s).*([.!?]|```)$")).count();
        boolean incidentLost = naive.stream().filter(s -> s.contains("fail over")).noneMatch(s -> s.contains("Incident"));
        System.out.printf("naive 40-word windows: %d chunks, %d end mid-sentence, newlines/code formatting flattened, "
                + "'fail over' chunk lost its 'Incident' heading: %s; no offsets, no section path, no stable ids%n",
                naive.size(), midSentence, incidentLost);
        check(midSentence > 0 && incidentLost, "the naive splitter cuts sentences and drops structure");
        System.out.println("all ChunkingPipeline self-checks passed");
    }
}
```

Output (verified, deterministic):

```text
a6479f9d67371cf4821c6612  [   0, 124) 19 tok  Payments Service Runbook                             | # Payments Service Runbook /  / The payments service set
a64a9d308b65f2386a4f872d  [ 124, 346) 37 tok  Payments Service Runbook > Incident: settlement backlog | ## Incident: settlement backlog /  / When the settlement
bf6caad959091a6c468b7dbf  [ 346, 464) 14 tok  Payments Service Runbook > Incident: settlement backlog | ```bash / kubectl -n payments scale deploy/settler --rep
aed83d8791d2bd6e2994a3c8  [ 464, 657) 35 tok  Payments Service Runbook > Configuration             | ## Configuration /  / The retry budget is 10% of request
8c852c86bfdd846ffee443cc  [ 629, 886) 40 tok  Payments Service Runbook > Configuration             | Keys expire after 24 hours. Duplicate keys return the or

re-ingest same version: 5/5 ids identical; v4 edits one number: 1/5 ids change (only that chunk is re-embedded; its old id is deleted)
naive 40-word windows: 4 chunks, 2 end mid-sentence, newlines/code formatting flattened, 'fail over' chunk lost its 'Incident' heading: true; no offsets, no section path, no stable ids
all ChunkingPipeline self-checks passed
```

---

## 4. Production failure modes and P99 debugging

### F1 · "The answer is in the docs but retrieval never finds it"

- **Symptom:** golden-set questions fail although the source contains the answer.
- **Signature:** the relevant chunk exists but ranks low. Its text lacks the entity or term the query uses: pronouns,
  "the company", "this service", or the subject lives in a heading.
- **Root cause:** context loss at chunk boundaries (paragraph recall@1 0.287 in the lab).
- **Fix:** contextual prefixes (LLM-generated, or at least title + section path), late chunking, or parent-child
  retrieval.
- **Prevention:** a retrieval golden set with coreference-heavy questions, measured per chunking change.

### F2 · Code and tables retrieved as garbage

- **Symptom:** answers quote half a command or a table row without its header.
- **Root cause:** fixed-size or naive splitters cut atomic blocks. The naive splitter in §3.2 flattens newlines and
  orphans the "fail over" instruction from its "Incident" heading.
- **Fix:** structure-aware splitting with atomic code/table blocks. Tables get their header row repeated in each
  chunk, or are linearized one row per chunk with column names.

### F3 · Token budget overflow at embed time

- **Symptom:** the embedding API truncates or rejects inputs, and silently truncated chunks lose their tails.
- **Root cause:** a budget measured in words or characters while the model counts subword tokens (code and non-English
  text tokenize 1.5–3× denser).
- **Fix:** count with the model's tokenizer, budget the contextual prefix too, and alert on truncation.

### F4 · Re-ingesting one edited page re-embeds the whole corpus

- **Symptom:** embedding cost spikes and ingestion lags after small edits.
- **Root cause:** chunk IDs include version, timestamps or offsets, so every edit changes every ID (5/5 in the first
  draft of §3.2).
- **Fix:** content-addressed IDs. Cache embeddings and contextual prefixes by content hash. Upsert new IDs and delete
  vanished ones.

### F5 · Citations point to the wrong place

- **Symptom:** a "source" link highlights text that doesn't contain the quoted claim.
- **Root cause:** chunk text was normalized (whitespace collapsed, markup stripped) but offsets were computed on the
  normalized text, or not stored at all.
- **Fix:** offsets into the canonical source with `text == source[start:end]` as an ingestion invariant. Normalize only
  the embedding input.

### F6 · Contextual Retrieval cost explodes

- **Symptom:** the ingestion LLM bill exceeds the serving bill.
- **Root cause:** the full document is resent per chunk without prompt caching, contexts are regenerated on every
  re-ingest, or a large model is used.
- **Fix:** prompt caching of the document prefix, a small model, a content-hash cache of contexts, and generation only
  for new or changed chunks (F4).

---

## 5. FAANG L7 bar-raiser Q&A chains

### Q1 · "How do you choose a chunk size?"

- **L5 answer:** "512 tokens with 50 overlap is standard."
- **Why L5 fails at scale:** a constant ignores document structure, query length, the embedding model, and
  coreference. It optimizes nothing measurable.
- **L7 principal defense:**
  1. Chunk size trades context loss (small) against dilution (large).
  2. Measure recall@k and answer quality on a golden set of real queries, per document type.
  3. Use structure-aware splitting with atomic blocks, plus contextual prefixes or late chunking to remove the context
     penalty of small chunks.
  4. Use parent-child retrieval to return enough context to the LLM.
  5. Re-measure when the embedding model or document mix changes.

### Q2 · "Contextual Retrieval vs late chunking: which would you deploy?"

- **L5 answer:** "Contextual retrieval, Anthropic published it."
- **Why L5 fails:** it doesn't weigh cost, latency, model constraints or the BM25 side.
- **L7 defense:**
  - **Contextual Retrieval** costs an LLM call per chunk (affordable with prompt caching and a small model), works
    with any embedder, **and improves BM25 too**, because the prefix is lexical.
  - **Late chunking** costs nothing extra at ingest, but requires a long-context embedder whose pooled token states
    behave well, and documents that fit its window. It doesn't help BM25.
  - **In the lab** both reach recall@5 = 1.0. Contextual edges ahead at rank 1 (0.71 vs 0.61).
  - **Decision:** for hybrid search, Contextual Retrieval. For embed-only at low ingest budget, late chunking. Either
    way, add a reranker for rank-1 precision.

### Q3 · "Why does ColBERT beat single-vector retrieval on multi-aspect queries? What does it cost?"

- **L5 answer:** "It uses more vectors so it's more accurate."
- **Why L5 fails:** it misses the mechanism (MaxSim vs pooling) and the storage and index implications.
- **L7 defense:**
  - **Mechanism:** single-vector pooling averages away a chunk's components. MaxSim requires each query token to find
    its best counterpart. On contextual chunks: recall@1 1.000 vs 0.713 for pooled vectors.
  - **Cost:** one vector per token (several × the storage even with PLAID's centroid + 2-bit residual compression), a
    specialized candidate-generation index, and higher query cost.
  - **Deployment patterns:** ColBERT as a **reranker** over a single-vector or hybrid first stage (cheap and most of
    the gain), or a dedicated late-interaction engine (PLAID; engines with multi-vector support).

### Q4 · "Design the ingestion contract for chunks."

- **L5 answer:** "Split the text, embed it, store the vectors."
- **Why L5 fails:** no citations, no update semantics, no deletes, no cost control.
- **L7 defense:** every chunk record carries:
  - doc ID, section path, exact offsets (`text == source[start:end]`), token count by the model's tokenizer;
  - a content-addressed ID (no version or offsets);
  - the embed text (contextual prefix + text), the doc version as an attribute, and ACL references (File 03).

  Ingestion upserts new IDs, deletes vanished ones, and caches embeddings and contexts by content hash. A one-word
  edit then re-embeds one chunk (1/5 in §3.2), not the document.

### Q5 · "Users complain the bot can't find answers in tables."

- **L5 answer:** "Use a bigger chunk size."
- **Why L5 fails:** tables split across chunks lose headers, and pooled embeddings of numeric grids are weak.
- **L7 defense:**
  1. Treat tables as atomic, or linearize them row by row with column names ("Region: EMEA; Q3 revenue: 12.4M; …").
  2. Index each row as a chunk with a table-level contextual prefix.
  3. Add BM25 for exact values and IDs (File 02).
  4. For analytical questions, route to text-to-SQL over the structured source instead of RAG.

---

## 6. Invariants checklist

- [ ] Chunk text equals `source[start:end]`. Offsets and section paths are stored for every chunk.
- [ ] Code blocks, tables and lists are atomic. Budgets use the embedding model's tokenizer and include the prefix.
- [ ] Chunk IDs are content-addressed (doc + section + text). Embeddings and contexts are cached by content hash.
      Re-ingestion upserts new IDs and deletes vanished ones.
- [ ] Every chunk is situated: a contextual prefix (LLM or title + section path) or late-chunked embeddings.
- [ ] Chunking changes are gated on a golden-set recall@k that includes coreference and table questions.
- [ ] Contextual Retrieval uses prompt caching and a small model, and runs only for new or changed chunks.

## 7. References

1. P. Lewis et al. *Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks.* NeurIPS 2020.
2. Anthropic. *Introducing Contextual Retrieval.* Engineering blog, September 2024.
3. M. Günther et al. *Late Chunking: Contextual Chunk Embeddings Using Long-Context Embedding Models.*
   arXiv:2409.04701, 2024.
4. O. Khattab, M. Zaharia. *ColBERT: Efficient and Effective Passage Search via Contextualized Late Interaction over
   BERT.* SIGIR 2020.
5. K. Santhanam et al. *ColBERTv2: Effective and Efficient Retrieval via Lightweight Late Interaction.* NAACL 2022;
   *PLAID: An Efficient Engine for Late Interaction Retrieval.* CIKM 2022.
6. G. Kamradt. *The 5 Levels of Text Splitting for Retrieval* (semantic chunking), 2024.
