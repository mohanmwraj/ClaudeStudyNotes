# 05.4 · Encoders (BERT, DeBERTa) vs Decoders (GPT, Llama): When to Use a Small BERT over an LLM

> **Folder 05 · Deep Learning Foundations to Transformers, from First Principles**
> **Measured on:** PyTorch 2.14.1 (RTX 3050 Laptop GPU for fine-tuning and bulk decoder scoring; CPU, 4 threads, for latency), transformers 5.22.0, safetensors 0.8.0, scikit-learn 1.9.1, Windows 11.
> **Real models and data:** `sentence-transformers/all-MiniLM-L6-v2` (encoder, 22.7M), `HuggingFaceTB/SmolLM2-135M-Instruct` (decoder, 135M), 20 CLINC150 intents.
> **Design sources:** Devlin et al. (BERT, 2019), He et al. (DeBERTa, 2021), Radford et al. (GPT-2, 2019), Touvron et al. (Llama, 2023), Allal et al. (SmolLM2, 2025), Warner et al. (ModernBERT, 2024). Full list in §8.

---

## 0. Orientation: Same Blocks, Different Mask, Different Job

Andrew Ng's framing: **an encoder reads the whole input at once, so every word sees every other word. A decoder reads left to right, so each word sees only the past, which is exactly what you need to *generate* and less than you want to *understand* a fixed text.** Both are stacks of the same attention + MLP blocks (05.1, 05.3). The causal mask is the architectural difference, and it determines what each is good at and what it costs.

The head-to-head in this file, on the same 20-intent task:

```text
method                                         params  test acc
(a) frozen MiniLM + LR                          22.7M    0.9867
(b) MiniLM fine-tuned (3 epochs)                22.7M    0.9867
(c) SmolLM2-135M zero-shot (label log-lik)       135M    0.1717
(d) SmolLM2-135M frozen features + LR            135M    0.9067

encoder (eager PyTorch) + LR head: p50    19.6 ms
decoder zero-shot over 20 labels:  p50 12118.4 ms   (02.3's ONNX int8 encoder path: ~2 ms)
```

**A 22.7M-parameter encoder beat a 6× larger decoder by 8 points even when both got a trained linear head, and by 81 points against the decoder's zero-shot prompting, at 1/600th of the CPU latency.** That's the quantitative case for "small BERT over an LLM" on classification, retrieval and reranking. The rest of this file explains why, and re-implements the encoder from its raw weights, so nothing about it is a black box.

### The backend-engineer bridge

| You already know | Model-family equivalent |
|---|---|
| A batch job that reads a whole file before deciding | **Encoder**: bidirectional, one pass, one decision |
| A streaming producer that emits one record at a time | **Decoder**: causal, generates token by token with a KV cache |
| Choosing a column store for analytics and a row store for OLTP | **Encoders for understanding, decoders for generation** |
| Reading a wire protocol from the spec, not the SDK | **Re-implementing a model from its weights** to remove the black box (§3.1) |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The three families: encoder, decoder, encoder–decoder | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Pre-training objectives: masked LM vs next-token prediction | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 BERT from its weights: where the parameters live | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Why encoders win at classification, retrieval and reranking | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Decoders as classifiers: zero-shot, prompting, and their cost | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Encoder improvements: RoBERTa, DeBERTa, ModernBERT | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.7 Decoder-based embedding models | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.8 The decision matrix: small encoder vs LLM | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Scaling-law theory for encoders vs decoders | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The three families: encoder, decoder, encoder–decoder `[MUST-KNOW: Core AI Engineer Edge]`

```text
encoder (BERT, RoBERTa, DeBERTa, MiniLM, ModernBERT)
  attention mask: none (bidirectional)  │ output: one contextual vector per input token
  use: classification, NER/PII tagging, embeddings, cross-encoder reranking

decoder (GPT, Llama, Mistral, Qwen, SmolLM)
  attention mask: causal (lower-triangular) │ output: next-token distribution at each position
  use: generation, chat, reasoning, tool use, and, via prompting, everything else

encoder–decoder (T5, BART, original Transformer)
  encoder reads the input bidirectionally; decoder generates with cross-attention to it
  use: translation, summarization, structured rewriting
```

05.3 §1.6 verified the mask's effect: in a decoder, changing token 7 can't change token 5's representation. In an encoder, every token's representation depends on the whole input. That's why an encoder's token states are richer *for a fixed input*, and why a decoder can stream outputs and an encoder can't.

### 1.2 Pre-training objectives: masked LM vs next-token prediction `[MUST-KNOW: Core AI Engineer Edge]`

- **Masked language modelling (BERT):** hide ~15% of tokens and predict them from *both* sides. The model learns representations that summarize the full context of each token, which is good for understanding tasks. Sentence-embedding models (MiniLM here) are then contrastively fine-tuned (04.2) so mean-pooled vectors capture sentence meaning.
- **Next-token prediction (GPT/Llama):** predict token t+1 from tokens ≤ t. Every position gives a training signal, and the objective is exactly "generate text". It scales smoothly with data and parameters, which is what made decoders the frontier. Instruction tuning and RLHF/DPO (01.3 §1.18) then turn a next-token predictor into an assistant.

The objectives explain the measurements. SmolLM2's mean-pooled hidden states (method d) carry less class-separable information than MiniLM's (0.907 vs 0.987). Its last-layer states are shaped to predict the *next* token, not to summarize the input, and it was never contrastively trained for sentence similarity.

### 1.3 BERT from its weights: where the parameters live `[MUST-KNOW: Core AI Engineer Edge]`

§3.1 loads `model.safetensors` directly and runs the forward pass with plain tensor operations:

```text
h = LayerNorm(E_token[ids] + E_pos[0..n−1] + E_type[0])
for each of 6 layers (post-norm, 05.1 §1.8):
    a = softmax(Q Kᵀ/√32 + padding_mask) V    (12 heads × 32 dims; no causal mask)
    h = LayerNorm(h + a W_O)
    h = LayerNorm(h + GELU(h W₁) W₂)          (384 → 1536 → 384, exact erf GELU)
sentence = normalize(masked_mean(h))
```

It matches Hugging Face's `BertModel` to **2.55e-15** (float64) on a padded batch, with sentence-embedding cosines of 1.0. There's no magic in the model: the config, the weights and these dozen lines are all of it. That's useful when porting to another runtime (02.3's ONNX export), debugging a numerical drift, or auditing what a vendor model does.

**Where the 22.6M parameters live:**

```text
  token embeddings (vocab x hidden)     11,720,448   51.9%
  position + type embeddings               197,888    0.9%
  attention (Q,K,V,O)                    3,548,160   15.7%
  feed-forward (2 matrices)              7,089,408   31.4%
```

**Half the model is the vocabulary table** (30,522 × 384), and it costs a lookup per token, not FLOPs. The *compute* is in the layers: ~10.6M multiply-adds per token. Two practical consequences:

- Parameter count is a poor proxy for small models' speed. Count the layer FLOPs.
- Vocabulary and tokenizer choices dominate small-model size. A multilingual vocabulary (250k tokens) can make the embedding table bigger than all the layers combined.

### 1.4 Why encoders win at classification, retrieval and reranking `[MUST-KNOW: Core AI Engineer Edge]`

1. **Bidirectional context.** For a fixed input, every token's representation uses the whole input. A classifier or retriever wants exactly that summary.
2. **Training aligned with the task.** Sentence-embedding encoders are contrastively trained so that cosine similarity means semantic similarity (04.2). Cross-encoders are trained to score (query, passage) pairs. A next-token decoder's hidden states aren't shaped for either.
3. **One forward pass, no generation.** Classification is one encoder pass plus a matrix–vector product. A decoder used generatively either generates the label (sampling, parsing, retries) or scores every candidate label (one sequence per label, §1.5).
4. **Size.** Encoders this good are 20–400M parameters. They run on a CPU, in ~2 ms with ONNX int8 (02.3), and fine-tune in minutes (§3.2: three epochs on 2,000 examples on a laptop GPU).

Fine-tuning didn't improve on the frozen encoder here (0.9867 both). The frozen representation already separates these 20 intents, so a linear head is enough, consistent with 02.1's learning curves. Fine-tuning earns its cost on harder or out-of-domain tasks, as error analysis would show.

### 1.5 Decoders as classifiers: zero-shot, prompting, and their cost `[MUST-KNOW: Core AI Engineer Edge]`

Method (c) lists the 20 intent names in a prompt, appends each candidate label, and picks the one with the highest mean token log-probability. That's a standard zero-shot scoring technique, with no generation and no parsing:

- **Accuracy 0.1717** (chance is 0.05). A 135M decoder has neither the instruction-following nor the world knowledge to do this reliably. Zero-shot classification quality rises steeply with model size, which is why "use an LLM" in production usually means a much larger, hosted model, and the cost tables of 01.1 §2.
- **12.1 s per query on CPU**, because scoring 20 labels means 20 sequences of ~150 tokens through 30 layers, with prompt prefill repeated per label (a shared-prefix KV cache would amortize it). Even a perfect zero-shot decoder pays a per-query cost proportional to prompt length × candidates.
- **Method (d)**, a decoder as a frozen feature extractor with a trained head, recovers much of the gap (0.907). Decoder representations do contain the information, just less linearly accessible than in a contrastively trained encoder. Purpose-built decoder-based embedding models close the gap (§1.7).

### 1.6 Encoder improvements: RoBERTa, DeBERTa, ModernBERT `[GOOD-TO-KNOW: Architectural Literacy]`

- **RoBERTa** (2019): same architecture as BERT, trained longer on more data with dynamic masking and without next-sentence prediction. A large gain from data and training recipe alone (a data-centric result).
- **DeBERTa** (He et al., 2021): disentangled attention (separate content and relative-position vectors) and an enhanced mask decoder. DeBERTa-v3 remains a top choice for fine-tuned classification and NLI-based judges, including the entailment checks in 01.3's semantic entropy.
- **ModernBERT** (Warner et al., 2024): RoPE, GeGLU FFNs, alternating local/global attention, an 8k context, and Flash-style kernels. It brings decoder-era architecture to encoders: longer documents, faster inference.

### 1.7 Decoder-based embedding models `[GOOD-TO-KNOW: Architectural Literacy]`

Several leading embedding models are fine-tuned *decoders*, with contrastive training on top of an LLM backbone and pooling at the last token or by mean. They take high places on embedding leaderboards because the backbone brings broad knowledge. The trade-off is size: billions of parameters instead of tens of millions, so encoding costs GPU time per query and per document. For high-QPS routing and caching, small encoders remain the economical choice. For a hard retrieval domain where quality matters more than cost, a large decoder-based embedder can earn its price. Measure on your own eval (04.2's protocol).

### 1.8 The decision matrix: small encoder vs LLM `[MUST-KNOW: Core AI Engineer Edge]`

| Task | Small encoder (fine-tuned or frozen + head) | LLM (prompted) |
|---|---|---|
| Intent routing, topic or language detection | ✅ 0.987 at ~2 ms (this folder + 02.3) | Fallback for the escalated, uncertain band |
| PII, toxicity, injection classification | ✅ Token-level tagging plus calibrated heads (02.3) | Second-stage judge for the uncertain band |
| Retrieval embeddings | ✅ Bi-encoders (04.2) | Too slow per query and per document |
| Reranking top-50 | ✅ Cross-encoder or LambdaMART (04.3) | Final-stage verification for a few candidates |
| Extraction into a fixed schema | Token-classification encoder if the spans are explicit | ✅ When the spans need inference or normalization |
| Open-ended generation, reasoning, tool use | ❌ | ✅ |
| Zero labelled data, day 0 | Weak (needs labels or prototypes) | ✅ Zero/few-shot, then distil into an encoder |

The production pattern is **distillation via the cascade**: the LLM handles traffic the encoder can't yet, its audited decisions become labels, and the encoder takes over more traffic each retraining cycle (Folder 07).

### 1.9 Scaling-law theory for encoders vs decoders `[SKIP: Academic/Research Only]`

How loss scales with parameters, data and compute differs across objectives and architectures (Kaplan et al., Hoffmann et al.'s Chinchilla). It's important for pre-training budget decisions, and irrelevant to choosing between an existing small encoder and a hosted LLM for a production task, where the measured eval decides.

---

## 2. Where It Beats an LLM in Production

The whole file is this section. Measured on one task:

| | Small encoder (MiniLM) | Small decoder (SmolLM2-135M) | Hosted frontier LLM |
|---|---|---|---|
| Accuracy (20 intents) | **0.987** | 0.172 zero-shot / 0.907 with a trained head | Likely high (unmeasured here; needs your eval) |
| CPU latency per query | 19.6 ms eager, ~2 ms ONNX int8 | 12.1 s zero-shot | A network round trip plus generation |
| Cost per query | CPU time | CPU/GPU time × prompt × candidates | Tokens × price (01.1 §2) |
| Labels needed | A few dozen per class (02.1 learning curve) | None for zero-shot | None |
| Calibration | Temperature/Platt (02.1) | Log-probs if self-hosted | Often no log-probs (01.3 §1.16) |

The strategy that falls out: **LLM for coverage on day 0, encoder for scale from day 30**, with the cascade (Folder 07) moving traffic from the first to the second as labels accumulate.

---

## 3. Production Code Blueprint

### 3.1 MiniLM (BERT) re-implemented from raw weights

```python
"""minilm_forward_from_weights.py - a BERT-family encoder (all-MiniLM-L6-v2) re-implemented from its raw weights.

Reads model.safetensors directly and runs the forward pass with plain tensor ops:
  embeddings (word + position + token type) -> LayerNorm -> 6 x [self-attention -> add & LayerNorm ->
  GELU FFN -> add & LayerNorm] -> masked mean pooling -> L2 normalize.
  1. Matches Hugging Face's BertModel on a padded batch, and the sentence embeddings agree.
  2. Where the 22.7M parameters live (half are the vocabulary embedding table).
  3. FLOPs per token, and the bidirectional attention that makes it an ENCODER.
"""
import json
import math
import os

import torch
from safetensors.torch import load_file
from transformers import AutoModel, AutoTokenizer

mdir = os.path.join(os.environ["KB_DL"], "models", "minilm")
cfg = json.load(open(os.path.join(mdir, "config.json")))
W = {k.removeprefix("bert."): v.double() for k, v in load_file(os.path.join(mdir, "model.safetensors")).items()}
Hd, NH, L, EPS = cfg["hidden_size"], cfg["num_attention_heads"], cfg["num_hidden_layers"], cfg["layer_norm_eps"]
dh = Hd // NH
print(f"config: hidden {Hd}, heads {NH} (head dim {dh}), layers {L}, FFN {cfg['intermediate_size']}, act {cfg['hidden_act']}, "
      f"vocab {cfg['vocab_size']:,}, max positions {cfg['max_position_embeddings']}")


def ln(x, p):
    return torch.nn.functional.layer_norm(x, (Hd,), W[p + ".weight"], W[p + ".bias"], EPS)


def lin(x, p):
    return x @ W[p + ".weight"].T + W[p + ".bias"]


def encoder(ids, mask):
    n = ids.shape[1]
    h = W["embeddings.word_embeddings.weight"][ids] + W["embeddings.position_embeddings.weight"][:n] \
        + W["embeddings.token_type_embeddings.weight"][0]
    h = ln(h, "embeddings.LayerNorm")
    bias = (1.0 - mask[:, None, None, :].double()) * torch.finfo(torch.float64).min   # padded keys get -inf
    for i in range(L):
        p = f"encoder.layer.{i}."
        split = lambda z: z.view(z.shape[0], n, NH, dh).transpose(1, 2)
        q, k, v = (split(lin(h, p + f"attention.self.{w}")) for w in ("query", "key", "value"))
        a = torch.softmax(q @ k.transpose(-1, -2) / math.sqrt(dh) + bias, -1)   # bidirectional: no causal mask
        ctx = (a @ v).transpose(1, 2).reshape(h.shape)
        h = ln(h + lin(ctx, p + "attention.output.dense"), p + "attention.output.LayerNorm")   # post-LN residual
        f = torch.nn.functional.gelu(lin(h, p + "intermediate.dense"))
        h = ln(h + lin(f, p + "output.dense"), p + "output.LayerNorm")
    return h


tok = AutoTokenizer.from_pretrained(mdir)
texts = ["how would you say fly in italian", "set a five minute timer",
         "can i put in a pto request for september 1st to september 8th please"]
enc = tok(texts, padding=True, return_tensors="pt")
ours = encoder(enc["input_ids"], enc["attention_mask"])
hf = AutoModel.from_pretrained(mdir, use_safetensors=True).eval().double()
with torch.no_grad():
    ref = hf(**enc).last_hidden_state
m = enc["attention_mask"].unsqueeze(-1).double()
pool = lambda h: torch.nn.functional.normalize((h * m).sum(1) / m.sum(1), dim=-1)
real = enc["attention_mask"].bool()
print(f"\n== 1. ours vs Hugging Face BertModel (float64, padded batch of 3) ==")
print(f"max |token states| diff on real tokens = {(ours - ref)[real].abs().max().item():.2e}; "
      f"sentence-embedding cosines: {[round(float(c), 12) for c in (pool(ours) * pool(ref)).sum(-1)]}")
assert (ours - ref)[real].abs().max() < 1e-9

print("\n== 2. where the parameters live ==")
groups = {"token embeddings (vocab x hidden)": 0, "position + type embeddings": 0, "attention (Q,K,V,O)": 0,
          "feed-forward (2 matrices)": 0, "LayerNorms": 0}
for k, v in W.items():
    if k.startswith("pooler"):
        continue
    if "word_embeddings" in k:
        groups["token embeddings (vocab x hidden)"] += v.numel()
    elif "embeddings" in k and "LayerNorm" not in k:
        groups["position + type embeddings"] += v.numel()
    elif "LayerNorm" in k:
        groups["LayerNorms"] += v.numel()
    elif "attention" in k:
        groups["attention (Q,K,V,O)"] += v.numel()
    else:
        groups["feed-forward (2 matrices)"] += v.numel()
tot = sum(groups.values())
for k, v in groups.items():
    print(f"  {k:36s} {v:>11,}  {v / tot:6.1%}")
print(f"  {'total (without the unused pooler)':36s} {tot:>11,}")

print("\n== 3. compute per token ==")
macs = L * (4 * Hd * Hd + 2 * Hd * cfg["intermediate_size"])
print(f"~{macs / 1e6:.1f}M multiply-adds per token in the layers (+ attention scores 2*n*{Hd} per token per layer); "
      f"the embedding table (half the parameters) costs one row LOOKUP per token, not FLOPs")
print("encoder = bidirectional attention: every token sees the whole input, so it is natural for classification,")
print("retrieval and reranking; a decoder masks future tokens so it can generate left to right")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
config: hidden 384, heads 12 (head dim 32), layers 6, FFN 1536, act gelu, vocab 30,522, max positions 512

== 1. ours vs Hugging Face BertModel (float64, padded batch of 3) ==
max |token states| diff on real tokens = 2.55e-15; sentence-embedding cosines: [1.0, 1.0, 1.0]

== 2. where the parameters live ==
  token embeddings (vocab x hidden)     11,720,448   51.9%
  position + type embeddings               197,888    0.9%
  attention (Q,K,V,O)                    3,548,160   15.7%
  feed-forward (2 matrices)              7,089,408   31.4%
  LayerNorms                                 9,984    0.0%
  total (without the unused pooler)     22,565,888

== 3. compute per token ==
~10.6M multiply-adds per token in the layers (+ attention scores 2*n*384 per token per layer); the embedding table (half the parameters) costs one row LOOKUP per token, not FLOPs
encoder = bidirectional attention: every token sees the whole input, so it is natural for classification,
retrieval and reranking; a decoder masks future tokens so it can generate left to right

ALL ASSERTIONS PASSED
```

### 3.2 Encoder vs decoder on the same task

```python
"""encoder_vs_decoder_classification.py - a small encoder vs a 6x larger decoder LM on the same intent task.

Task: 20 CLINC150 intents (2,000 training / 600 test utterances).
  (a) frozen MiniLM encoder (22.7M) + logistic regression
  (b) MiniLM fine-tuned end to end (GPU if present)
  (c) SmolLM2-135M-Instruct (a 135M decoder) zero-shot: score each intent name's log-likelihood after a prompt
  (d) SmolLM2-135M as a frozen feature extractor (mean-pooled hidden states) + logistic regression
Plus single-query CPU latency for the encoder path vs the decoder zero-shot path.
"""
import json
import os
import time

import numpy as np
import torch
from sklearn.linear_model import LogisticRegression
from transformers import AutoModel, AutoModelForCausalLM, AutoTokenizer

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
meta = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))
labels = meta["labels"]
rng = np.random.default_rng(141)
pick = np.sort(rng.choice(150, 20, replace=False))
remap = {c: i for i, c in enumerate(pick)}
mtr, mte = np.isin(Z["y_train"], pick), np.isin(Z["y_test"], pick)
ytr = np.array([remap[c] for c in Z["y_train"][mtr]])
yte = np.array([remap[c] for c in Z["y_test"][mte]])
Ttr = [t for t, k in zip(meta["texts"]["train"], mtr) if k]
Tte = [t for t, k in zip(meta["texts"]["test"], mte) if k]
names = [labels[c].replace("_", " ") for c in pick]
print(f"20 intents: {', '.join(names[:6])}, ...; train {len(Ttr)}, test {len(Tte)}")
dev = "cuda" if torch.cuda.is_available() else "cpu"
torch.manual_seed(0)
res = {}

lr = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"][mtr], ytr)
res["(a) frozen MiniLM + LR"] = lr.score(Z["X_test"][mte], yte)

mdir = os.path.join(DL, "models", "minilm")
tok = AutoTokenizer.from_pretrained(mdir)
enc = AutoModel.from_pretrained(mdir, use_safetensors=True).to(dev)
head = torch.nn.Linear(384, 20).to(dev)
opt = torch.optim.AdamW([{"params": enc.parameters(), "lr": 5e-5}, {"params": head.parameters(), "lr": 1e-3}], weight_decay=0.01)


def embed(model, ts):
    e = tok(ts, padding=True, truncation=True, max_length=64, return_tensors="pt").to(dev)
    h = model(**e).last_hidden_state
    m = e["attention_mask"].unsqueeze(-1).float()
    return torch.nn.functional.normalize((h * m).sum(1) / m.sum(1), dim=-1)


ytr_t = torch.tensor(ytr, device=dev)
for epoch in range(3):
    enc.train()
    for idx in torch.randperm(len(Ttr)).split(32):
        loss = torch.nn.functional.cross_entropy(head(embed(enc, [Ttr[i] for i in idx]) * 20), ytr_t[idx.to(dev)])
        opt.zero_grad()
        loss.backward()
        opt.step()
enc.eval()
with torch.no_grad():
    pred = torch.cat([head(embed(enc, Tte[i:i + 128]) * 20).argmax(1) for i in range(0, len(Tte), 128)]).cpu().numpy()
res["(b) MiniLM fine-tuned (3 epochs)"] = float(np.mean(pred == yte))

ddir = os.path.join(DL, "models", "smollm2-135m")
dtok = AutoTokenizer.from_pretrained(ddir)
dec = AutoModelForCausalLM.from_pretrained(ddir, use_safetensors=True).eval().to(dev)
n_dec = sum(p.numel() for p in dec.parameters())
prompt = lambda t: f"Possible intents: {', '.join(names)}.\nUser request: {t}\nThe intent of this request is:"
label_ids = [dtok(" " + n, add_special_tokens=False)["input_ids"] for n in names]


@torch.inference_mode()
def zero_shot(t, device):
    p_ids = dtok(prompt(t), add_special_tokens=False)["input_ids"]
    seqs = [p_ids + l for l in label_ids]
    width = max(len(s) for s in seqs)
    pad = dtok.pad_token_id if dtok.pad_token_id is not None else 0
    ids = torch.tensor([s + [pad] * (width - len(s)) for s in seqs], device=device)
    att = torch.tensor([[1] * len(s) + [0] * (width - len(s)) for s in seqs], device=device)
    logp = torch.log_softmax(dec(input_ids=ids, attention_mask=att).logits.float(), -1)
    scores = []
    for r, l in enumerate(label_ids):                              # mean log-prob of the label's own tokens
        pos = range(len(p_ids) - 1, len(p_ids) - 1 + len(l))
        scores.append(np.mean([logp[r, p, tok_].item() for p, tok_ in zip(pos, l)]))
    return int(np.argmax(scores))


pred = np.array([zero_shot(t, dev) for t in Tte])
res["(c) SmolLM2-135M zero-shot (label log-lik)"] = float(np.mean(pred == yte))


@torch.inference_mode()
def dec_features(ts):
    out = []
    for i in range(0, len(ts), 64):
        e = dtok(ts[i:i + 64], padding=True, return_tensors="pt").to(dev)
        h = dec.model(**e).last_hidden_state.float()
        m = e["attention_mask"].unsqueeze(-1).float()
        out.append(torch.nn.functional.normalize((h * m).sum(1) / m.sum(1), dim=-1).cpu().numpy())
    return np.vstack(out)


if dtok.pad_token is None:
    dtok.pad_token = dtok.eos_token
lr_dec = LogisticRegression(C=10, max_iter=5000).fit(dec_features(Ttr), ytr)
res["(d) SmolLM2-135M frozen features + LR"] = lr_dec.score(dec_features(Tte), yte)

print(f"\n{'method':44s} {'params':>8} {'test acc':>9}")
params = {"(a)": "22.7M", "(b)": "22.7M", "(c)": f"{n_dec / 1e6:.0f}M", "(d)": f"{n_dec / 1e6:.0f}M"}
for k, v in res.items():
    print(f"{k:44s} {params[k[:3]]:>8} {v:>9.4f}")

print("\n== single-query latency on CPU, 4 threads (one measured run, 20 test queries) ==")
torch.set_num_threads(4)
enc_cpu, dec_cpu = enc.to("cpu"), dec.to("cpu")
dev = "cpu"
ts_enc, ts_dec = [], []
for t in Tte[:20]:
    t0 = time.perf_counter()
    with torch.no_grad():
        lr.predict(embed(enc_cpu, [t]).numpy())
    ts_enc.append((time.perf_counter() - t0) * 1e3)
    t0 = time.perf_counter()
    zero_shot(t, "cpu")
    ts_dec.append((time.perf_counter() - t0) * 1e3)
print(f"encoder (eager PyTorch) + LR head: p50 {np.median(ts_enc):7.1f} ms")
print(f"decoder zero-shot over 20 labels:  p50 {np.median(ts_dec):7.1f} ms   (02.3's ONNX int8 encoder path: ~2 ms)")
assert res["(a) frozen MiniLM + LR"] > res["(c) SmolLM2-135M zero-shot (label log-lik)"]
print("\nALL ASSERTIONS PASSED")
```

Output (verified accuracies; the latency lines are one measured run):

```text
20 intents: accept reservations, account blocked, calendar update, cancel, change user name, directions, ...; train 2000, test 600

method                                         params  test acc
(a) frozen MiniLM + LR                          22.7M    0.9867
(b) MiniLM fine-tuned (3 epochs)                22.7M    0.9867
(c) SmolLM2-135M zero-shot (label log-lik)       135M    0.1717
(d) SmolLM2-135M frozen features + LR            135M    0.9067

== single-query latency on CPU, 4 threads (one measured run, 20 test queries) ==
encoder (eager PyTorch) + LR head: p50    19.6 ms
decoder zero-shot over 20 labels:  p50 12118.4 ms   (02.3's ONNX int8 encoder path: ~2 ms)

ALL ASSERTIONS PASSED
```

How to read it:

- **(a) vs (b):** fine-tuning bought nothing on an easy, in-domain task. Error analysis decides when it's worth it.
- **(c):** the zero-shot decoder is better than chance (0.05) and far from useful. Don't extrapolate "LLMs can classify" from frontier models to a 135M model, or the reverse. Measure the model you'd deploy.
- **(d):** decoder states contain the information, but less linearly accessibly. A trained head recovers most of it, still 8 points behind the encoder.
- **Latency:** 12 s per query on CPU for decoder zero-shot is the cost of 20 × ~150-token sequences through 30 layers without prefix caching.

---

## 4. The Andrew Ng Lens: Choose the Smallest Model That Passes the Eval

### 4.1 Eval-driven model selection

Ng's evals-first discipline makes model choice an empirical question: define the task metric, the latency budget and the cost per request, then test candidates from smallest to largest and stop at the first that passes. Here the smallest candidate passed (0.987 at ~2 ms), so the larger ones don't need to be built into the hot path at all.

### 4.2 Bias and variance across model families

- The **zero-shot decoder's** failure (0.17) is *avoidable bias*: the model can't represent the task as prompted. A bigger model or a trained head is the fix.
- The **encoder's** remaining 1.3% error is mostly irreducible here (confusable phrasings). More data per intent or label clarification are the levers, not a bigger model.
- The **decoder-features head's** 9.3% error, with ample data, is a *representation* gap. That's a reason to prefer a contrastively trained encoder for this job.

### 4.3 Data-centric distillation

The best long-term use of an LLM in a classification system is often as an *annotator*. Let it label the long tail, audit a sample against humans (calibrate it, 01.3 §1.13), and train the small encoder on those labels. The deployed system is fast and cheap, and its quality is set by label quality, the data-centric principle.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "We'll just prompt a small open LLM for classification" disappoints | 0.17 accuracy (135M zero-shot) | Zero-shot ability needs scale | Encoder + head, or a large hosted LLM for the escalated band | Eval candidate models from smallest to largest |
| F2 | Decoder-based classifier too slow | Seconds per query on CPU | Prompt length × candidates × layers | Encoders; prefix KV caching; constrained decoding | Latency budget per stage |
| F3 | Decoder hidden states make a mediocre embedding | 0.907 vs 0.987 with the same head | Next-token objective; no contrastive training | Use a purpose-trained embedding model | Benchmark embeddings on the task, not leaderboards |
| F4 | Re-implemented model drifts from the reference | Diffs ≫ 1e-6 | GELU variant, LayerNorm eps, post/pre-norm, mask fill, position ids | Match the config exactly (§3.1 reaches 2.6e-15) | Golden-output test in CI |
| F5 | Small model is unexpectedly large in memory | Embedding table dominates (52% here; more for multilingual vocabularies) | Vocabulary size | Vocabulary pruning; a smaller-vocab model; int8 embeddings | Inspect parameter breakdowns, not just totals |
| F6 | Fine-tuning costs GPU time for no gain | Fine-tuned = frozen (0.9867) | The frozen representation already separates the classes | Keep frozen + head; fine-tune only when error analysis says so | A learning curve and error buckets before fine-tuning |
| F7 | Encoder truncates long documents silently | Max 512 positions (MiniLM) | Absolute position table | Chunk + aggregate; long-context encoders (ModernBERT 8k) | Length distribution checked against the model's limit |
| F8 | Label scoring biased toward short label names | Systematic preference for some labels | Sum vs mean log-prob normalization | Length-normalize (mean) or calibrate per label | Per-label confusion matrix |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why would you ever use BERT when we have GPT-class models?"</b></summary>

**Initial Prompt.** An executive question in an architecture review.

**L5 Answer.** "BERT is cheaper."

**Why L5 Fails in Production.** Cheaper is true but incomplete, and it implies a quality sacrifice that the measurements don't show for understanding tasks.

**L7 Principal Defense.** "For classification, retrieval and reranking, a small encoder is often *better* and dramatically cheaper. On 20 intents, a 22.7M MiniLM with a linear head scored 0.987, and a 135M decoder scored 0.907 even with the same trained head, and 0.17 zero-shot. Latency: ~2 ms per query on CPU (ONNX int8) vs 12 s for the decoder's zero-shot scoring. Encoders read bidirectionally and are contrastively trained so their vectors mean something. Decoders are trained to predict the next token. Hosted frontier LLMs are the right tool for generation, reasoning and day-0 coverage, so we use them for the escalated band and as annotators to train the encoder."

**Bar-Raiser Follow-ups.**
- *"What would change your mind?"* A task needing reasoning or world knowledge the encoder lacks, measured as avoidable bias the encoder can't close with data.

</details>

<details><summary><b>Q2 · "What's actually different between BERT and GPT architecturally?"</b></summary>

**Initial Prompt.** A whiteboard question.

**L5 Answer.** "BERT is an encoder and GPT is a decoder."

**Why L5 Fails in Production.** It names the categories without the mechanism, which is one mask and one objective.

**L7 Principal Defense.** "Same building blocks: attention + MLP + norms + residuals. Two differences. (1) The attention mask: GPT adds a causal mask (−∞ above the diagonal), so position t sees only ≤ t, which we verified bit-exactly in 05.3. BERT has none, so each token sees the whole input. (2) The objective: BERT predicts masked tokens from both sides, GPT predicts the next token. Details differ too (BERT: post-norm, learned absolute positions, GELU; Llama: pre-norm RMSNorm, RoPE, SwiGLU), and those matter for ports, as my from-weights MiniLM implementation shows (it must be post-norm with exact GELU to match to 1e-15)."

**Bar-Raiser Follow-ups.**
- *"Can a decoder do classification?"* Yes: scoring labels, generating them, or a head on its states. It costs more and, at small sizes, works worse (§3.2).

</details>

<details><summary><b>Q3 · "Our small open LLM gets 17% on our intent task zero-shot. Should we fine-tune it?"</b></summary>

**Initial Prompt.** The team picked a 135M decoder to avoid API costs.

**L5 Answer.** "Yes, fine-tune it with LoRA."

**Why L5 Fails in Production.** It might help, but it ignores that an encoder of a sixth the size already scores 0.987 with no fine-tuning.

**L7 Principal Defense.** "Check the cheaper baseline first. A frozen MiniLM with a logistic head got 0.987. Even the decoder's own frozen features with a trained head reached 0.907, so the decoder's problem is prompting and zero-shot ability, not information content. Fine-tuning the decoder could close the gap, but it's still 6× the parameters, slower per query and a generation stack to operate. Unless the task needs generation, use the encoder. If it needs generation (writing the reply, not just routing), keep the encoder as the router and send generation to an appropriately sized LLM."

**Bar-Raiser Follow-ups.**
- *"When is a small fine-tuned decoder right?"* Short constrained generation (template filling, SQL for a fixed schema) where a hosted LLM is too slow or costly. Validate it against both the encoder-plus-template option and the hosted model.

</details>

<details><summary><b>Q4 · "Where do the parameters of a small BERT go, and why does it matter?"</b></summary>

**Initial Prompt.** Memory planning for edge deployment.

**L5 Answer.** "Mostly in the attention layers."

**Why L5 Fails in Production.** For small encoders, the embedding table dominates. Here it's 51.9% of parameters, while attention is 15.7%.

**L7 Principal Defense.** "MiniLM-L6: 11.7M of 22.6M parameters are the 30,522 × 384 token-embedding table, 7.1M are the FFNs and 3.5M attention. Compute is different: the table is a lookup (no FLOPs), and the layers do ~10.6M multiply-adds per token. So memory is driven by vocabulary × hidden size, and speed by layers × hidden². For edge use: prune the vocabulary to the tokens your domain uses, quantize the embedding table to int8, and count layer FLOPs for latency. A multilingual vocabulary (~250k tokens) can make the table larger than the rest of the model."

**Bar-Raiser Follow-ups.**
- *"Why does int8 quantization help memory more than speed here?"* Half the bytes are a lookup table, so quantizing it saves memory directly while the speedup comes from the layers' matmuls (02.3: 4× smaller, 2.3× faster).

</details>

<details><summary><b>Q5 · "How do you verify a model port to a new runtime is exactly right?"</b></summary>

**Initial Prompt.** Moving an encoder from PyTorch to an in-house C++ or ONNX runtime.

**L5 Answer.** "Compare a few outputs and check they look similar."

**Why L5 Fails in Production.** "Look similar" hides GELU variants, eps values and masking bugs that shift embeddings slightly, and that shifts every similarity threshold downstream.

**L7 Principal Defense.** "Golden-output tests against the reference in float64 on padded batches. My from-weights MiniLM matches Hugging Face to 2.55e-15 on token states, with sentence cosines exactly 1.0. The checklist: activation variant (`hidden_act`), LayerNorm eps (1e-12 for BERT), post- vs pre-norm, the attention-mask fill (finfo.min), the position and token-type embeddings, the pooling mask. Then compare the exported runtime on a fixed test set at the task level: ONNX fp32 had identical accuracy in 02.3, and any quantized version is gated on the task metric and re-derived thresholds."

**Bar-Raiser Follow-ups.**
- *"Why float64 for the test?"* To separate implementation bugs from float32 rounding, then measure fp32/fp16 tolerances separately.

</details>

<details><summary><b>Q6 · "Should our embedding model be a big decoder-based one from the leaderboard?"</b></summary>

**Initial Prompt.** A team wants a 7B-parameter embedding model at the top of a public benchmark.

**L5 Answer.** "Yes, it's the best on the leaderboard."

**Why L5 Fails in Production.** Leaderboards average over many tasks that aren't yours, and they ignore cost: encoding with a 7B model needs GPUs for every query and document.

**L7 Principal Defense.** "Run our retrieval eval (04.2's protocol: nDCG@10, recall@100 on our queries) for both the leaderboard model and a small encoder. Price encoding: corpus size × tokens through 7B parameters for indexing, plus per-query encoding latency. If the big model wins by a margin that matters on our metric and the budget allows, it's justified for the retrieval index, while routing and caching can still use the small encoder. Often a small encoder plus BM25 hybrid, an adapter, and a reranker closes most of the gap (04.2: +5.2 points from an adapter alone)."

**Bar-Raiser Follow-ups.**
- *"Dimension and storage?"* Large embedders often output 3–4k dims, so check Matryoshka support (01.2) and quantization (01.1) before committing.

</details>

<details><summary><b>Q7 · "When is fine-tuning the encoder worth it?"</b></summary>

**Initial Prompt.** Fine-tuning gave no gain in one experiment. Was it a mistake to try?

**L5 Answer.** "Fine-tuning always helps if you train long enough."

**Why L5 Fails in Production.** It didn't help here (0.9867 frozen and fine-tuned), and it costs a training pipeline and a model per task.

**L7 Principal Defense.** "Fine-tune when error analysis shows representational failure: confusable classes the frozen space doesn't separate, a domain or language the encoder handles poorly (02.3's German prompts), or a learning curve that has flattened well below target with the frozen encoder. Here the frozen representation already separates the 20 intents, so a linear head is the right call. When fine-tuning is warranted, start with SetFit-style contrastive tuning or a query adapter (04.2) before full fine-tuning, to keep the encoder sharable across heads."

**Bar-Raiser Follow-ups.**
- *"How to keep sharing one encoder?"* Multi-task fine-tuning, or per-task LoRA adapters on a shared encoder (01.2 §1.10).

</details>

<details><summary><b>Q8 · "Design the model stack for a support assistant: routing, PII redaction, retrieval, answering."</b></summary>

**Initial Prompt.** End-to-end architecture.

**L5 Answer.** "Use one LLM for everything with a good prompt."

**Why L5 Fails in Production.** It pays generation cost and latency for every sub-task, loses calibrated thresholds, and makes each component's quality unmeasurable on its own.

**L7 Principal Defense.** "Match each stage to the cheapest model that passes its eval. Routing and OOS gating: a MiniLM encoder plus an LR head plus a distance gate, ~2 ms (02.3). PII redaction: regexes for structured PII plus a fine-tuned token-classification encoder (DeBERTa-class) for names and addresses, calibrated per label. Retrieval: BM25 plus a bi-encoder hybrid, a query adapter, a LambdaMART reranker (04.x). Answering: a hosted LLM over the top passages, with semantic-entropy or grounding checks on high-stakes answers (01.3). Cascade escalation where the encoders are uncertain (Folder 07). Every stage has its own eval, so failures are attributable."

**Bar-Raiser Follow-ups.**
- *"Why not let the LLM do PII redaction?"* It's a high-volume, latency-sensitive classification with strict recall needs and audit requirements. A calibrated encoder plus deterministic rules is faster, cheaper and auditable.

</details>

---

## 7. Invariants Checklist

- [ ] Model candidates are evaluated smallest-first on the task metric, latency and cost. The first that passes ships.
- [ ] Understanding tasks (routing, classification, tagging, retrieval, reranking) default to encoders. Decoders need a measured reason.
- [ ] Model ports pass a float64 golden-output test against the reference, then a task-level test in the target runtime.
- [ ] Parameter budgets are broken down (embeddings vs layers). Latency is estimated from layer FLOPs.
- [ ] Encoder fine-tuning is justified by error analysis or a learning curve, not by default.
- [ ] LLMs in classification systems act as escalation targets and audited annotators that feed the encoder's training data.
- [ ] Document lengths are checked against each encoder's position limit (512 for BERT-class models), with chunking where needed.

---

## 8. References

1. J. Devlin et al., *BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding*, NAACL 2019. https://arxiv.org/abs/1810.04805
2. Y. Liu et al., *RoBERTa: A Robustly Optimized BERT Pretraining Approach*, 2019. https://arxiv.org/abs/1907.11692
3. P. He et al., *DeBERTa: Decoding-enhanced BERT with Disentangled Attention*, ICLR 2021. https://arxiv.org/abs/2006.03654
4. B. Warner et al., *Smarter, Better, Faster, Longer: A Modern Bidirectional Encoder* (ModernBERT), 2024. https://arxiv.org/abs/2412.13663
5. A. Radford et al., *Language Models are Unsupervised Multitask Learners* (GPT-2), 2019.
6. H. Touvron et al., *LLaMA: Open and Efficient Foundation Language Models*, 2023. https://arxiv.org/abs/2302.13971
7. L. Ben Allal et al., *SmolLM2: When Smol Goes Big*, 2025. https://arxiv.org/abs/2502.02737 (model: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct)
8. W. Wang et al., *MiniLM*, 2020. https://arxiv.org/abs/2002.10957
9. C. Raffel et al., *Exploring the Limits of Transfer Learning with a Unified Text-to-Text Transformer* (T5), JMLR 2020. https://arxiv.org/abs/1910.10683
10. Hugging Face, *safetensors* format. https://huggingface.co/docs/safetensors/
11. L. Tunstall et al., *SetFit*, 2022. https://arxiv.org/abs/2209.11055
