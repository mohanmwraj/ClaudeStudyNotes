# Master formula sheet

> Re-read this before every contest. It collects every formula, identity, theorem and numeric constant in the kit, grouped by area.
> Each row has a one-line meaning and a link to the file that derives it. `04/01` means `04-Number-Theory/01-…`.
> 🧊 = rare or IGM-depth. Conditions are part of each formula: a formula used outside its condition (prime modulus, $n<p$,
> convexity, a DAG, …) is the most common source of a wrong answer. Section 17 lists what was re-checked numerically for this sheet.

**Contents:** 1 Complexity · 2 Limits and constants · 3 Bits · 4 Number theory · 5 Combinatorics · 6 Probability ·
7 DP and DP-optimisation conditions · 8 Linear algebra · 9 Polynomials and FFT · 10 Graphs, flows, matching · 11 Trees ·
12 Strings · 13 Games · 14 Geometry · 15 Randomised algorithms · 16 First terms · 17 Verification notes

---

## 1. Complexity, sums and amortised bounds

### 1.1 Constraint → intended complexity (rules of thumb, approximate)

About $10^8$ simple operations per second in C++ is a safe planning figure (tight loops reach several times more; Java is usually within
a factor 1–2). At $n=2\cdot10^5$: $n\log_2 n\approx3.5\cdot10^6$, $n\sqrt n\approx9\cdot10^7$, $n^2=4\cdot10^{10}$ (too slow).
Sources: [01/01](../01-Foundations/01-complexity-and-constraint-reading.md), [16/07](../16-IGM-Frontier/07-how-grandmasters-think.md).

| Constraint | Typical intended complexity | Constraint | Typical intended complexity |
|---|---|---|---|
| $n\le 10$–$12$ | $n!$, $n^n$ (tiny) | $n\le5000$ | $n^2$ |
| $n\le 20$ | $2^n n$; $3^n$ for $n\le16$–$17$ | $n\le 2\cdot10^5$ | $n\log n$, $n\log^2 n$, $n\sqrt n$ |
| $n\le 40$ | $2^{n/2}$ (meet in the middle) | $n\le10^6$–$10^7$ | $n$, $n\log\log n$ |
| $n\le500$ | $n^3$ | $n\le10^{18}$ | $\log n$, $\sqrt[3]n$, closed form, matrix power |

Landmarks: $\log_2 10^3\approx10$, $\log_2 10^5\approx16.6$, $\log_2(2\cdot10^5)\approx17.6$, $\log_2 10^6\approx20$, $\log_2 10^9\approx30$,
$\log_2 10^{18}\approx60$. $3^{15}\approx1.4\cdot10^7$, $3^{16}\approx4.3\cdot10^7$, $3^{18}\approx3.9\cdot10^8$, $2^{20}\cdot20\approx2.1\cdot10^7$.
Memory: 256 MB $=2^{28}$ B holds $\approx6.7\cdot10^7$ `int`, $3.3\cdot10^7$ `long long`, $2\cdot10^9$ bits; a `std::set` node is $\approx40$ B.

### 1.2 Sums

| Formula | Meaning | Src |
|---|---|---|
| $\sum_{i=1}^n i=\frac{n(n+1)}2$, $\ \sum i^2=\frac{n(n+1)(2n+1)}6$, $\ \sum i^3=\left(\frac{n(n+1)}2\right)^2$ | Faulhaber, small $k$ | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) |
| $\sum i^4=\frac{n(n+1)(2n+1)(3n^2+3n-1)}{30}$; in general $\sum_{i\le n}i^k$ is a polynomial of degree $k+1$ | interpolate from $k+2$ samples | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) |
| $\sum_{i=0}^{n-1}r^i=\frac{r^n-1}{r-1}$; $\sum_{i=0}^k2^i=2^{k+1}-1$; $\sum_{i=0}^n i2^i=(n-1)2^{n+1}+2$ | geometric; modulo $m$ use doubling or the block matrix of §8 | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $H_n=\sum_{i\le n}\frac1i=\ln n+\gamma+O(1/n)$, $\gamma\approx0.5772$ | harmonic number | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| $\sum_{d=1}^n\lfloor n/d\rfloor=\sum_{i\le n}d(i)=n\ln n+(2\gamma-1)n+O(\sqrt n)$ | "loop over multiples" is $O(n\log n)$; $\approx1.4\cdot10^7$ at $n=10^6$ | [01/01](../01-Foundations/01-complexity-and-constraint-reading.md) |
| $\sum_{p\le n}n/p=O(n\log\log n)$ | Eratosthenes | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| $\#\lbrace\lfloor n/d\rfloor\rbrace\le2\sqrt n$ | $d\le\sqrt n$ gives $\sqrt n$ values, $d>\sqrt n$ gives quotients $<\sqrt n$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\log_2 n!=n\log_2n-n\log_2e+O(\log n)$; $n!\approx\sqrt{2\pi n}\,(n/e)^n$ | Stirling; sorting needs $\lceil\log_2 n!\rceil$ comparisons | [01/05](../01-Foundations/05-sorting-and-comparators.md) |
| pairs $\binom n2$, triples $\binom n3\approx n^3/6$; subarrays $\frac{n(n+1)}2$; $\sum_{k}k(n-k+1)=\binom{n+2}3$ | loop counts; total subarray length | [02/03](../02-Core-Techniques/03-two-pointers-and-sliding-window.md) |
| interval-DP triple loop: $\sum_{\ell}(n-\ell+1)(\ell-1)=\frac{n^3-n}6$ | $n=500$: $2\cdot10^7$ | [06/05](../06-Dynamic-Programming/05-interval-dp.md) |
| $\binom{2n}n\sim\frac{4^n}{\sqrt{\pi n}}$; $\binom nk\le\left(\frac{en}k\right)^k$ | size estimates | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_{h\ge0}\lfloor n/2^{h+1}\rfloor h\le n$ | bottom-up heap build is $O(n)$ | [08/10](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md) |

### 1.3 Recurrences

**Master theorem** ($a\ge1$, $b>1$, $c^*=\log_ba$) for $T(n)=aT(n/b)+f(n)$ ([01/01](../01-Foundations/01-complexity-and-constraint-reading.md)):
(1) $f=O(n^{c^*-\varepsilon})\Rightarrow T=\Theta(n^{c^*})$; (2) $f=\Theta(n^{c^*}\log^kn)$, $k\ge0$ $\Rightarrow T=\Theta(n^{c^*}\log^{k+1}n)$;
(3) $f=\Omega(n^{c^*+\varepsilon})$ and $af(n/b)\le\kappa f(n)$ for some $\kappa<1$ $\Rightarrow T=\Theta(f)$.

| Recurrence | Solution | Where | Src |
|---|---|---|---|
| $T(n/2)+O(1)$ / $2T(n/2)+O(1)$ | $\log n$ / $n$ | binary search / segment tree build | [01/01](../01-Foundations/01-complexity-and-constraint-reading.md) |
| $2T(n/2)+O(n)$ / $2T(n/2)+O(n\log n)$ | $n\log n$ / $n\log^2n$ | merge sort / CDQ | [16/01](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md) |
| $3T(n/2)+O(n)$ | $n^{\log_23}\approx n^{1.585}$ | Karatsuba | [01/01](../01-Foundations/01-complexity-and-constraint-reading.md) |
| $T(n/2)+T(n/4)+O(n)$ | $n$ | fractions summing to $<1$ | [01/01](../01-Foundations/01-complexity-and-constraint-reading.md) |
| $T(n/2)+O(n\log n)$ | $n\log n$ | Newton iteration on power series | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| $T(n-1)+O(n)$ / $2T(n-1)+O(1)$ / $nT(n-1)$ | $n^2$ / $2^n$ / $n!$ | Hanoi: exactly $2^n-1$ moves | [01/04](../01-Foundations/04-recursion-brute-force-and-backtracking.md) |
| $T(n-1)+T(n-2)+O(1)$ | $\Theta(\varphi^n)$, $\varphi\approx1.618$ | naive Fibonacci | [01/04](../01-Foundations/04-recursion-brute-force-and-backtracking.md) |
| subset recursion tree / permutation tree | $2^{n+1}-1$ nodes / $n!\sum_{j\le n}\frac1{j!}<e\cdot n!$ nodes | backtracking cost | [01/04](../01-Foundations/04-recursion-brute-force-and-backtracking.md) |

### 1.4 Amortised and structural bounds

| Bound | Meaning | Src |
|---|---|---|
| $\sum c_i=\sum\hat c_i-\Phi_m+\Phi_0$ | potential method (e.g. doubling array: $\Phi=2\,\text{size}-\text{cap}$, $\hat c=3$) | [01/01](../01-Foundations/01-complexity-and-constraint-reading.md) |
| two pointers: $\le2n$ moves; monotonic stack/deque: each index pushed and popped once | $O(n)$ total | [02/03](../02-Core-Techniques/03-two-pointers-and-sliding-window.md), [02/04](../02-Core-Techniques/04-monotonic-stack-and-deque.md) |
| two-stack queue: amortised $O(1)$ applications of any associative $\oplus$ | sliding-window gcd/OR/matrix products | [02/03](../02-Core-Techniques/03-two-pointers-and-sliding-window.md) |
| $\min_B(aB+b/B)=2\sqrt{ab}$ at $B=\sqrt{b/a}$; $B$ off by $2\times$ costs $\le1.25\times$ | every sqrt-decomposition block size | [16/06](../16-IGM-Frontier/06-advanced-sqrt-techniques.md) |
| Mo: $O(n^2/B+qB)$, $B=n/\sqrt q$ → $O(n\sqrt q)$; with updates $B=n^{2/3}$ → $O(n^{5/3})$ | add/remove steps | [08/07](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md) |
| $\sum s_i=S\Rightarrow\#\lbrace s_i>B\rbrace<S/B$ and $\#\text{distinct }s_i\le\sqrt{2S}$ | heavy/light split; few distinct sizes | [16/06](../16-IGM-Frontier/06-advanced-sqrt-techniques.md) |
| orient edges low→high degree: $\text{out}(v)\le\sqrt{2m}$ | triangles and 4-cycles in $O(m\sqrt m)$ | [16/06](../16-IGM-Frontier/06-advanced-sqrt-techniques.md) |
| DSU: union by size depth $\le\lfloor\log_2n\rfloor$; with path compression $O(m\,\alpha(n))$, $\alpha\le4$ | rollback DSU: no compression, $O(\log n)$ find | [08/06](../08-Data-Structures/06-dsu-and-variants.md) |
| small-to-large: an element moves $\le\log_2n$ times → $O(n\log n)$ moves | general merging lemma | [10/03](../10-Trees/03-small-to-large-and-dsu-on-tree.md) |
| $g\leftarrow\gcd(g,a_i)$ over $i$: $O(n+\log\max a)$ total; per right end $\le\lfloor\log_2\max a\rfloor+1$ distinct subarray gcds | each change at least halves | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| segment tree: $\le4n$ array, $\le2\lceil\log_2n\rceil$ canonical pieces, $\le4$ nodes visited per level | iterative: $2n$ | [08/02](../08-Data-Structures/02-segment-tree-basics.md) |
| Fenwick: $\le\lfloor\log_2n\rfloor+1$ iterations; $n+1$ cells | $O(n)$ build | [08/01](../08-Data-Structures/01-fenwick-tree.md) |
| persistent point update: $\lceil\log_2n\rceil+1$ new nodes; dynamic tree $\approx q(\log_2C-\log_2q+2)$ nodes | memory planning | [08/08](../08-Data-Structures/08-persistent-data-structures.md), [08/04](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md) |
| range mod: $a\ge x\Rightarrow a\bmod x<a/2$ → $O((n+q)\log n\log V)$; chmin beats $O((n+q)\log n)$ amortised | potential arguments | [08/04](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md) |
| tree knapsack merges: $\sum S\cdot s_c\le\binom n2$; capped at $k$: $O(nk)$ | not $O(n^3)$ | [06/08](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md) |
| splay/LCT access lemma: $\le3(r(t)-r(x))+1$ | LCT amortised $O(\log n)$ | [16/03](../16-IGM-Frontier/03-link-cut-trees.md) |
| integer binary search: $\lceil\log_2(N+1)\rceil$ probes; reals: $\lceil\log_2((R-L)/\varepsilon)\rceil$ | $\le61$ for $N\le2\cdot10^{18}$ | [02/02](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md) |
| ternary: $\log(W/\varepsilon)/\log\frac32$ iterations; golden section: $\log(W/\varepsilon)/\log\varphi$ evaluations | $1/\varphi=\varphi-1$ makes one probe reusable | [02/06](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md) |
| Floyd cycle finding: first meeting $t^*=\lambda\max(1,\lceil\mu/\lambda\rceil)\le\mu+\lambda$ | $O(\mu+\lambda)$ time, $O(1)$ memory | [02/03](../02-Core-Techniques/03-two-pointers-and-sliding-window.md) |
| comparisons: max $n-1$; min and max $\lceil3n/2\rceil-2$; second largest $n+\lceil\log_2n\rceil-2$ | adversary lower bounds | [03/05](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) |

---

## 2. Integer limits, precision and constants

| Item | Value | Src |
|---|---|---|
| `int` / `long long` | $2^{31}-1=2147483647\approx2.1\cdot10^9$ / $2^{63}-1=9223372036854775807\approx9.22\cdot10^{18}$ | [01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) |
| unsigned 32 / 64 / `__int128` | $\approx4.3\cdot10^9$ / $\approx1.84\cdot10^{19}$ / $\approx\pm1.7\cdot10^{38}$ (64-bit GCC only) | [01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) |
| `double` / `long double` (GCC x86) | 53-bit / 64-bit significand: integers exact up to $2^{53}\approx9.0\cdot10^{15}$ / $2^{64}$ | [01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) |
| fits in signed 64 bits | $20!$ (not $21!$), $F_{92}$ (not $F_{93}$), all $\binom nk$ with $n\le66$; unsigned: all $n\le67$ | [01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) |
| safe infinity | `1e18` or `LLONG_MAX/4` ($\approx2.3\cdot10^{18}$) so that `INF+INF` fits; `0x3f3f3f3f` $=1061109567$ for `memset` | [01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) |
| powers of two | $2^{10}=1024$, $2^{16}=65536$, $2^{20}=1048576$, $2^{30}\approx1.07\cdot10^9$, $2^{32}\approx4.29\cdot10^9$, $2^{60}\approx1.15\cdot10^{18}$, $2^{62}\approx4.6\cdot10^{18}$ | [03/05](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) |
| $10^9+7$ | prime, primitive root 5; $(10^9+7)^2\approx1.0\cdot10^{18}<2^{63}$ | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $998244353=119\cdot2^{23}+1$ | prime, primitive root 3, NTT length up to $2^{23}$ | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| other NTT primes | $167772161=5\cdot2^{25}+1$, $469762049=7\cdot2^{26}+1$ (root 3); $754974721=45\cdot2^{24}+1$ (root 11) | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| other primes | $10^9+9$, $2^{61}-1$ (Mersenne, hashing), $10^{18}+3$, $999999999999999989$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| lazy reduction | residues $<10^9+7$: up to 9 products fit a signed 64-bit sum, 18 an unsigned one; the habit "reduce every 8 / 16" is safe for any $p<2^{30}$ | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $(a\cdot b)\bmod m$ for $m\le10^{18}$ | needs 128 bits: `(unsigned __int128)a*b%m`, Java `Math.multiplyHigh` | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $2^{61}-1$ reduction | $x=q\cdot2^{61}+r\Rightarrow x\equiv q+r$, one conditional subtraction | [11/01](../11-Strings/01-string-hashing.md) |
| 🧊 Barrett / Montgomery | $q=\lfloor x\mu/2^k\rfloor$ is within 2 of $\lfloor x/m\rfloor$; $\mathrm{REDC}(T)=(T+(Tm'\bmod R)m)/R\equiv TR^{-1}$ | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |

**Division and comparison rules** ([01/06](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)). C++ and Java `/` truncate toward zero and `%` takes the sign of the dividend:
$$\left\lfloor\tfrac ab\right\rfloor=\texttt{a/b}-[\texttt{a\%b}\ne0\wedge(a<0)\ne(b<0)],\qquad\left\lceil\tfrac ab\right\rceil=-\left\lfloor\tfrac{-a}b\right\rfloor,\qquad a\bmod m=((a\,\%\,m)+m)\,\%\,m.$$
For $a\ge0,b>0$: $\lceil a/b\rceil=(a+b-1)/b$. For $b,d>0$: $\frac ab<\frac cd\iff ad<cb$. Overflow test for $a,b>0$: $ab>L\iff a>\lfloor L/b\rfloor$.
$\sqrt x<k\iff x<k^2$ (integer `sqrt` through `double` is off by one near $10^{18}$: correct it). Floating equality: $\lvert a-b\rvert\le\varepsilon\max(1,\lvert a\rvert,\lvert b\rvert)$.
Safe midpoint $lo+\lfloor(hi-lo)/2\rfloor$ ([02/02](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md)).

---

## 3. Bits and XOR

| Identity | Meaning | Src |
|---|---|---|
| `x & -x` lowest set bit; `x & (x-1)` clears it; `x \| (x+1)` sets the lowest 0; $x>0$ power of two $\iff$ `x & (x-1)` $=0$ | two's complement | [01/03](../01-Foundations/03-bit-manipulation.md) |
| $a\oplus b=c\iff a=b\oplus c$; $\bigoplus_{l..r}=P_r\oplus P_{l-1}$ | XOR is addition in $\mathbb F_2^{\,w}$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| $0\oplus1\oplus\cdots\oplus n=n,\ 1,\ n+1,\ 0$ for $n\bmod4=0,1,2,3$ | pairs $2k\oplus(2k+1)=1$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| $a+b=(a\oplus b)+2(a\mathbin\&b)=(a\mathbin\vert b)+(a\mathbin\&b)$; $a\oplus b=(a\mathbin\vert b)-(a\mathbin\&b)$ | carries; so $a\oplus b\le a+b$, $a\oplus b\equiv a+b\pmod2$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| array with XOR $u$, sum $v$ exists $\iff v\ge u$, $2\mid v-u$; $c=\frac{v-u}2$: $[u,c,c]$, or $[u+c,c]$ iff $u\mathbin\&c=0$ | constructive | [03/03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) |
| $i\oplus(2^k-1-i)=2^k-1$, $i\mathbin\&(2^k-1-i)=0$ | complement pairing | [03/03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) |
| $\sum_{i<j}a_i\oplus a_j=\sum_k2^kc_k(n-c_k)$; $\sum_{i<j}a_i\mathbin\&a_j=\sum_k2^k\binom{c_k}2$; $\sum_{i<j}a_i\mathbin\vert a_j=\sum_k2^k\left[\binom n2-\binom{n-c_k}2\right]$ | $c_k$ = count with bit $k$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| $\#\lbrace0\le x\le n:\text{bit }k\rbrace=\left\lfloor\frac{n+1}{2^{k+1}}\right\rfloor2^k+\max\!\left(0,(n+1)\bmod2^{k+1}-2^k\right)$ | period $2^{k+1}$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| `for (s=m; s; s=(s-1)&m)`: all submasks; over all $m$: $\sum_m2^{\lvert m\rvert}=3^n$; $\sum_m\lvert m\rvert=n2^{n-1}$ | each element: out / in $m$ only / in both | [01/03](../01-Foundations/03-bit-manipulation.md) |
| supermasks `s=(s+1)\|m`; Gosper: `c=x&-x; r=x+c; x=(((r^x)>>2)/c)\|r` | next mask, same popcount | [01/03](../01-Foundations/03-bit-manipulation.md) |
| Gray $g(i)=i\oplus(i\gg1)$; inverse $i=g\oplus(g\gg1)\oplus(g\gg2)\oplus\cdots$; $G_{k+1}=0G_k,1G_k^{\text{rev}}$ | neighbours differ in one bit | [03/03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) |
| $\max_{l\le x<y\le r}x\oplus y=2^{k+1}-1$, $k$ = highest bit where $l,r$ differ | $l<r$ | [01/03](../01-Foundations/03-bit-manipulation.md) |
| $2^b>\sum_{j<b}2^j$ | why max/min XOR (trie, basis) is greedy from the top bit | [11/05](../11-Strings/05-trie-and-binary-trie.md) |
| the minimum $a_i\oplus a_j$ is attained by neighbours in sorted order | $a<b<c\Rightarrow a\oplus c\ge\min(a\oplus b,b\oplus c)$ | [11/05](../11-Strings/05-trie-and-binary-trie.md) |

---

## 4. Number theory

### 4.1 Divisibility, gcd and lcm

| Identity | Meaning | Src |
|---|---|---|
| $\gcd(a,b)=\gcd(b,a\bmod b)=\gcd(a,b-a)$; $\gcd(ka,kb)=\lvert k\rvert\gcd(a,b)$; $\gcd(0,x)=x$ | Euclid | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $\gcd(a,b)\operatorname{lcm}(a,b)=ab$; compute $\operatorname{lcm}=a/\gcd\cdot b$ | divide first | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $\gcd=\prod p^{\min(v_p(a),v_p(b))}$, $\operatorname{lcm}=\prod p^{\max}$; $\operatorname{lcm}(a,\gcd(b,c))=\gcd(\operatorname{lcm}(a,b),\operatorname{lcm}(a,c))$ and dual | divisibility is a distributive lattice | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| Euclid's lemma: $\gcd(a,b)=1$, $a\mid bc\Rightarrow a\mid c$; $\gcd(a,b)=\gcd(a,c)=1\Rightarrow\gcd(a,bc)=1$ | unique factorisation | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $\gcd(a^m-1,a^n-1)=a^{\gcd(m,n)}-1$; $\gcd(F_m,F_n)=F_{\gcd(m,n)}$ | Euclid on exponents / indices | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $\gcd(a_1+x,\dots,a_n+x)=\gcd(a_1+x,a_2-a_1,\dots,a_n-a_1)$ | gcd under a common shift | [03/04](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md) |
| Lamé: $k$ Euclid steps on $a>b\ge1\Rightarrow b\ge F_{k+1}$, $a\ge F_{k+2}$; so $k\le\log_\varphi b+O(1)\approx1.44\log_2b$ | worst case: consecutive Fibonacci | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| binary gcd: $\gcd(2a,2b)=2\gcd(a,b)$, $\gcd(2a,b)=\gcd(a,b)$ ($b$ odd), $\gcd(a,b)=\gcd(\lvert a-b\rvert,\min)$ | Stein, no divisions | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |

### 4.2 Bézout and linear Diophantine equations

| Statement | Meaning | Src |
|---|---|---|
| $\lbrace ax+by\rbrace=\gcd(a,b)\,\mathbb Z$; step $(x,y)=(y',\,x'-\lfloor a/b\rfloor y')$ | extended Euclid | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| output satisfies $\lvert x\rvert\le b/g$, $\lvert y\rvert\le a/g$ ($a,b>0$) | products fit 64 bits for $a,b\le10^9$ | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $ax+by=c$ solvable $\iff g\mid c$; all solutions $x=x_0+k\frac bg$, $y=y_0-k\frac ag$ | count in boxes by intersecting $k$-intervals | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| Frobenius ($\gcd(a,b)=1$): largest $c$ not of the form $ax+by$, $x,y\ge0$, is $ab-a-b$; exactly $\frac{(a-1)(b-1)}2$ such $c$ | 🧊 Sylvester | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |
| $\lvert x\rvert+\lvert y\rvert$ over solutions is convex piecewise linear in $k$ | try floors/ceilings of $-x_0g/b$ and $y_0g/a$ | [04/01](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) |

### 4.3 Modular arithmetic and inverses

| Rule | Meaning | Src |
|---|---|---|
| $a\equiv a'$, $b\equiv b'\Rightarrow a\pm b\equiv a'\pm b'$, $ab\equiv a'b'$; $a^k\equiv a'^k$ (the exponent does **not** reduce mod $m$) | ring rules | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $ac\equiv bc\pmod m\iff a\equiv b\pmod{m/\gcd(c,m)}$ | cancellation | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $a\equiv b$ mod $m_1$ and mod $m_2$ $\iff a\equiv b\pmod{\operatorname{lcm}(m_1,m_2)}$ | basis of CRT | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $b^{-1}\bmod m$ exists $\iff\gcd(b,m)=1$ | units form a group | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $b^{-1}\equiv b^{p-2}\pmod p$ ($p$ prime, $p\nmid b$); $b^{-1}\equiv b^{\varphi(m)-1}$; or extended Euclid for any $m$ | $O(\log m)$ each | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $\text{inv}[i]=-\lfloor p/i\rfloor\cdot\text{inv}[p\bmod i]\pmod p$, $\text{inv}[1]=1$ | all inverses $1..n$ in $O(n)$, $p$ prime, $n<p$ | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| batch: prefix products, one inverse, walk back | $n$ inverses in $O(n+\log p)$ | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $\text{ifact}[N]=\text{fact}[N]^{p-2}$, $\text{ifact}[i-1]=i\cdot\text{ifact}[i]$; $i^{-1}=(i-1)!\,(i!)^{-1}$ | **only for prime $p>N$**: $p!\equiv0$ | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $(a/b)\bmod m=(a\bmod bm)/b$ when $b\mid a$ exactly | division without an inverse (e.g. $\frac{r^n-1}{r-1}$, Burnside's $\frac1{\lvert G\rvert}$) | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $\frac ab\mapsto ab^{-1}\bmod p$ respects $+$, $\times$ | rational answers in residues; never compare residues | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |
| $a^e$ in $\le2\lfloor\log_2e\rfloor+1$ multiplications; $0^0=1$ by convention | binary exponentiation | [04/02](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) |

### 4.4 Fermat, Euler, Wilson, orders

| Theorem | Meaning | Src |
|---|---|---|
| Fermat: $a^{p-1}\equiv1\pmod p$ for $p\nmid a$; $a^p\equiv a$ always | so $a^e\equiv a^{e\bmod(p-1)}$ if $p\nmid a$; if $p\mid a$ the answer is $0$ for $e\ge1$ | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| Euler: $a^{\varphi(n)}\equiv1\pmod n$ for $\gcd(a,n)=1$ | | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| generalised Euler: $a^e\equiv a^{(e\bmod\varphi(m))+\varphi(m)}\pmod m$ for every $a$ when $e\ge\log_2m$ | towers $a^{b^{c}}$; the $\varphi$-chain reaches 1 in $\le2\log_2m+O(1)$ steps | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| Wilson: $(p-1)!\equiv-1\pmod p$; $(n-1)!\equiv0\pmod n$ for composite $n>4$ ($3!\equiv2\bmod4$) | | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $n!\equiv-\big((n+1)(n+2)\cdots(p-1)\big)^{-1}\pmod p$ | $n!$ in $O(p-n)$ for $n$ near $p$ | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $a^e\equiv1\iff\operatorname{ord}(a)\mid e$; $\operatorname{ord}(a)\mid\varphi(n)$; $\operatorname{ord}(a^k)=\frac{\operatorname{ord}(a)}{\gcd(k,\operatorname{ord}(a))}$ | orders | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| cyclic group of order $N$: exactly $\varphi(d)$ elements of order $d$ for each $d\mid N$ | | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| 🧊 Carmichael $\lambda(n)\mid\varphi(n)$, e.g. $\lambda(8)=2$ | smallest universal exponent | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |

### 4.5 Arithmetic functions and Dirichlet identities ($n=\prod p_i^{e_i}$)

| Formula | Meaning | Src |
|---|---|---|
| $d(n)=\prod(e_i+1)$; $\sigma(n)=\prod\frac{p_i^{e_i+1}-1}{p_i-1}$; $\sigma_k(n)=\prod\frac{p_i^{k(e_i+1)}-1}{p_i^k-1}$ | independent exponent choices | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| $\prod_{d\mid n}d=n^{d(n)/2}$; square divisors $\prod(\lfloor e_i/2\rfloor+1)$; odd divisors $\prod_{p_i\ne2}(e_i+1)$ | pair $d$ with $n/d$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| $\varphi(p^k)=p^{k-1}(p-1)$; $\varphi(n)=n\prod_{p\mid n}(1-\frac1p)$; $\varphi(mn)=\varphi(m)\varphi(n)\frac{g}{\varphi(g)}$, $g=\gcd(m,n)$ | multiplicative | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $\varphi(n)$ even for $n\ge3$; $\varphi(n)\le n/2$ for even $n$ | | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $\sum_{d\mid n}\varphi(d)=n$; $\sum_{\gcd(k,n)=1,\,k\le n}k=\frac{n\varphi(n)}2$ ($n\ge2$); $\#\lbrace x\le m:\gcd(x,m)=g\rbrace=\varphi(m/g)$ | group $1..n$ by gcd | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $\sum_{k=1}^n\gcd(k,n)=\sum_{d\mid n}d\,\varphi(n/d)$ | $\mathrm{id}*\varphi$ | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| coprime pairs in $[1,n]^2$: $2\sum_{k\le n}\varphi(k)-1$; Farey length $1+\sum_{k\le n}\varphi(k)$; $\sum_{k\le n}\varphi(k)\approx\frac3{\pi^2}n^2$ | $P(\text{coprime})=6/\pi^2$ | [04/04](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md) |
| $\sum_{d\mid n}\mu(d)=[n=1]$; $\sum_{d\mid n}\frac{\mu(d)}d=\frac{\varphi(n)}n$ | | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\mu*\mathbf1=\varepsilon$, $\varphi*\mathbf1=\mathrm{id}$, $\mu*\mathrm{id}=\varphi$, $\mathbf1*\mathbf1=d$, $\mathrm{id}*\mathbf1=\sigma$ | Dirichlet convolution $(f*g)(n)=\sum_{d\mid n}f(d)g(n/d)$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $g=f*\mathbf1\iff f=g*\mu$; multiples form: $G(d)=\sum_{d\mid k}F(k)\iff F(d)=\sum_{d\mid k}\mu(k/d)G(k)$ | Möbius inversion | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| linear sieve, $p=\operatorname{spf}(i)$, $p\mid i$: $\varphi(ip)=p\varphi(i)$, $\mu(ip)=0$, $d(ip)=d(i)\frac{e+2}{e+1}$; $p\nmid i$: $f(ip)=f(i)f(p)$ | multiplicative functions in $O(N)$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |

### 4.6 Möbius sums, floor blocks, prefix sums of multiplicative functions

| Formula | Meaning | Src |
|---|---|---|
| $\#\lbrace i\le n,j\le m:\gcd(i,j)=1\rbrace=\sum_d\mu(d)\lfloor n/d\rfloor\lfloor m/d\rfloor$; $\gcd=k$: use $\lfloor n/k\rfloor,\lfloor m/k\rfloor$ | insert $[\gcd=1]=\sum_{d\mid\gcd}\mu(d)$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\sum_{i\le n}\sum_{j\le m}\gcd(i,j)=\sum_d\varphi(d)\lfloor n/d\rfloor\lfloor m/d\rfloor$ | $\gcd=\sum_{d\mid\gcd}\varphi(d)$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| 🧊 $\sum_{i,j\le n}\operatorname{lcm}(i,j)=\sum_{d\le n}d\sum_{k\le n/d}\mu(k)k^2\,T(\lfloor\frac n{dk}\rfloor)^2$, $T(x)=\frac{x(x+1)}2$ | group by gcd, remove coprimality | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| block $[l,r]$ with constant $\lfloor n/i\rfloor$: $r=\lfloor n/\lfloor n/l\rfloor\rfloor$; two numerators: take the min of both ends | $O(\sqrt n)$ sums | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\lfloor\lfloor n/a\rfloor/b\rfloor=\lfloor n/(ab)\rfloor$; $\sum_{i\le n}(k\bmod i)=nk-\sum_{i\le n}i\lfloor k/i\rfloor$; $\sum_{i\le n}\sigma(i)=\sum_dd\lfloor n/d\rfloor\approx\frac{\pi^2}{12}n^2$ | | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\text{floor\_sum}(n,m,a,b)=\sum_{i<n}\lfloor\frac{ai+b}m\rfloor$: reduce $a,b$ mod $m$, then recurse on $(\lfloor\frac{an+b}m\rfloor,a,m,(an+b)\bmod m)$ | $O(\log m)$, Euclid-like | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| Dirichlet hyperbola ($ab=N$): $\sum_{k\le N}(f*g)(k)=\sum_{d\le a}f(d)G(\frac Nd)+\sum_{d\le b}g(d)F(\frac Nd)-F(a)G(b)$ | lattice points under $de=N$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| Du's sieve: $g(1)S(n)=\sum_{i\le n}(f*g)(i)-\sum_{d=2}^ng(d)S(\lfloor n/d\rfloor)$ | $O(n^{3/4})$, $O(n^{2/3})$ with a sieve to $n^{2/3}$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| $\Phi(n)=\frac{n(n+1)}2-\sum_{d=2}^n\Phi(\lfloor n/d\rfloor)$; $M(n)=1-\sum_{d=2}^nM(\lfloor n/d\rfloor)$ | prefix sums of $\varphi$, $\mu$ to $\sim10^{10}$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |

### 4.7 Linear congruences and CRT

| Statement | Meaning | Src |
|---|---|---|
| $ax\equiv b\pmod m$ solvable $\iff g=\gcd(a,m)\mid b$; then $x\equiv\frac bg(\frac ag)^{-1}\pmod{\frac mg}$, i.e. $g$ solutions mod $m$ | | [04/05](../04-Number-Theory/05-crt-and-linear-congruences.md) |
| coprime $m_i$: unique $x\bmod M$, $x=\sum a_iM_i(M_i^{-1}\bmod m_i)$, $M_i=M/m_i$; $\mathbb Z/M\cong\prod\mathbb Z/m_i$ | CRT | [04/05](../04-Number-Theory/05-crt-and-linear-congruences.md) |
| two congruences solvable $\iff a_1\equiv a_2\pmod g$; $t=\frac{a_2-a_1}g(\frac{m_1}g)^{-1}\bmod\frac{m_2}g$, $x\equiv a_1+m_1t\pmod{\operatorname{lcm}}$ | general merge | [04/05](../04-Number-Theory/05-crt-and-linear-congruences.md) |
| #roots of $f(x)\equiv0\pmod m$ is multiplicative over $p^k\parallel m$; $x^2\equiv1\pmod m$ has $2^{\omega(m)}$ roots for odd $m$ | | [04/05](../04-Number-Theory/05-crt-and-linear-congruences.md) |
| $\#\lbrace x\in[L,R]:x\equiv x_0\ (M)\rbrace=\lfloor\frac{R-x_0}M\rfloor-\lfloor\frac{L-1-x_0}M\rfloor$ (floor division) | | [04/05](../04-Number-Theory/05-crt-and-linear-congruences.md) |
| Garner: $x=r_1+p_1\big((r_2-r_1)p_1^{-1}\bmod p_2\big)+\dots$ | mixed radix, intermediates stay small | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |

### 4.8 Primitive roots, residues, primality

| Statement | Meaning | Src |
|---|---|---|
| a primitive root mod $n$ exists $\iff n\in\lbrace1,2,4,p^k,2p^k\rbrace$ ($p$ odd); there are $\varphi(\varphi(n))$ | | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| $g$ primitive $\iff g^{\varphi(n)/q}\ne1$ for every prime $q\mid\varphi(n)$; 🧊 if $g$ fails mod $p^2$, $g+p$ works | test and lifting | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| $x^k\equiv a\pmod p$ solvable $\iff a^{(p-1)/\gcd(k,p-1)}\equiv1$; then $\gcd(k,p-1)$ solutions | via indices | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| Euler's criterion $a^{(p-1)/2}\equiv\left(\frac ap\right)$; $\left(\frac{-1}p\right)=(-1)^{\frac{p-1}2}$, $\left(\frac2p\right)=(-1)^{\frac{p^2-1}8}$ | quadratic residues | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| 🧊 reciprocity $\left(\frac pq\right)\left(\frac qp\right)=(-1)^{\frac{p-1}2\frac{q-1}2}$ | Jacobi symbols in $O(\log)$ | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| $p\equiv3\pmod4$: $\sqrt a\equiv\pm a^{(p+1)/4}$ | else Tonelli–Shanks | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| Carmichael numbers 561, 1105, 1729 pass Fermat for every coprime base | never use the Fermat test | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| Miller–Rabin: a composite passes $\le\frac14$ of bases; bases $\lbrace2,3,5,\dots,37\rbrace$ (first 12 primes) are deterministic for $n<2^{64}$; $\lbrace2,7,61\rbrace$ for $n<4\,759\,123\,141$ | | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |
| BSGS: $x=in-j$, $n=\lceil\sqrt m\rceil$, $O(\sqrt m)$; Pollard rho: expected $O(\sqrt p)=O(n^{1/4})$ steps | birthday paradox | [04/06](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) |

### 4.9 $p$-adic valuations

| Formula | Meaning | Src |
|---|---|---|
| Legendre: $v_p(n!)=\sum_{k\ge1}\lfloor n/p^k\rfloor=\frac{n-s_p(n)}{p-1}$ ($s_p$ = base-$p$ digit sum) | trailing zeros of $n!$ = $v_5(n!)$ | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| Kummer: $v_p\binom{m+n}m$ = number of carries when adding $m+n$ in base $p$ | | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| 🧊 LTE: odd $p$, $p\mid x-y$, $p\nmid xy$: $v_p(x^n-y^n)=v_p(x-y)+v_p(n)$; $p=2$, $x,y$ odd, $n$ even: $v_2(x^n-y^n)=v_2(x-y)+v_2(x+y)+v_2(n)-1$ | | [04/07](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md) |
| trailing zeros of $\prod x_i$ = $\min(\sum v_2(x_i),\sum v_5(x_i))$ | | [06/04](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md) |

### 4.10 Number-theory constants

| Quantity | Value | Src |
|---|---|---|
| $\pi(10^3..10^9)$ | 168; 1 229; 9 592; 78 498; 664 579; 5 761 455; 50 847 534 | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| prime density near $n$ | $\approx1/\ln n$ ($\pi(x)\sim x/\ln x$): 1 in 28 near $10^{12}$, 1 in 41 near $10^{18}$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| max $d(n)$ for $n\le10^3,10^4,10^5,10^6$ | 32 (840), 64 (7560), 128 (83160), 240 (720720) | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| max $d(n)$ for $n\le10^7,10^8,10^9$ | 448 (8648640), 768 (73513440), 1344 (735134400) | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| max $d(n)$ for $n\le10^{12},10^{15},10^{18}$ | 6720, 26 880, 103 680 (897612484786617600) | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| divisor-count rules | $d(n)\le2\sqrt n$ always; "$d(n)\approx\sqrt[3]n$" is only an order of magnitude (the maxima are $1.5$–$3.4\times\sqrt[3]n$ for $10^3\le n\le10^9$ and below $\sqrt[3]n$ from $10^{12}$): use the table | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| max $\omega(n)$ (distinct primes) | 9 for $n\le10^9$ ($2\cdot3\cdots23=223092870$); 15 for $n\le10^{18}$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| max prime gap below $10^9$ / $10^{18}$ | 282 / 1442: "next prime" is a few hundred steps away | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |
| 🧊 cube-root trick | after trial division to $n^{1/3}$ the cofactor is $1$, $q$, $q^2$ or $q_1q_2$ | [04/03](../04-Number-Theory/03-sieves-and-factorization.md) |

---

## 5. Combinatorics

### 5.1 Counting and binomial identities

| Identity | Meaning | Src |
|---|---|---|
| $n^k$; $n^{\underline k}=\frac{n!}{(n-k)!}$; $\binom nk=\frac{n!}{k!(n-k)!}$, $0$ for $k<0$ or $k>n$ | sequences; ordered selections; subsets | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\binom n{c_1,\dots,c_m}=\frac{n!}{\prod c_i!}$; circular arrangements $(n-1)!$ | multiset permutations ("aabac": $\frac{5!}{3!}=20$) | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\binom nk=\binom{n-1}{k-1}+\binom{n-1}k$; $\binom nk=\binom n{n-k}$ | Pascal; symmetry | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $k\binom nk=n\binom{n-1}{k-1}$, i.e. $\binom nk=\frac nk\binom{n-1}{k-1}$ | absorption | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\binom nm\binom mk=\binom nk\binom{n-k}{m-k}$ | trinomial revision | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_k\binom nk=2^n$; $\sum_k(-1)^k\binom nk=[n=0]$; even-$k$ sum = odd-$k$ sum $=2^{n-1}$ ($n\ge1$) | $(1\pm1)^n$ | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_kk\binom nk=n2^{n-1}$; $\sum_kk(k-1)\binom nk=n(n-1)2^{n-2}$; $\sum_kk^2\binom nk=n(n+1)2^{n-2}$ | weighted row sums | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_i\binom mi\binom n{k-i}=\binom{m+n}k$; $\sum_k\binom nk^2=\binom{2n}n$ | Vandermonde | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_{m=0}^n\binom mk=\binom{n+1}{k+1}$; $\sum_{k=0}^m\binom{n+k}k=\binom{n+m+1}m$ | hockey stick; parallel summation | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\binom{-n}k=(-1)^k\binom{n+k-1}k$ | upper negation: $(1-x)^{-n}=\sum\binom{n+k-1}kx^k$ | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $\sum_k\binom{n-k}k=F_{n+1}$ | Fibonacci diagonal (domino/square tilings of $1\times n$) | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $(x_1+\dots+x_m)^n=\sum_c\binom nc\prod x_i^{c_i}$ | multinomial theorem | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| Lucas: $\binom nk\equiv\prod_i\binom{n_i}{k_i}\pmod p$ (base-$p$ digits); $\binom nk$ odd $\iff k\mathbin\&n=k$ | prime $p$ only | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| $t$-fold prefix sum of a single $1$ at position 1 is $\binom{i+t-2}{t-1}$ at $i$ | repeated prefix sums make binomials | [02/01](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) |

### 5.2 Binomial coefficients modulo $m$ (choose by modulus)

| Situation | Method and cost | Caveat | Src |
|---|---|---|---|
| prime $p>\text{MAXN}$ | factorials + inverse factorials: $O(\text{MAXN}+\log p)$ once, $O(1)$ per query | the prime must exceed MAXN, not just $n$: if $\text{MAXN}\ge p$ the tables contain $0$ | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| small prime $p$, huge $n$ | Lucas: $O(p)$ precompute, $O(\log_pn)$ per query | prime moduli only | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| composite $m$ | factor $m=\prod p^e$, solve modulo each $p^e$ (prime-power method, $O(p^e)$ precompute), glue with CRT | Lucas does not work modulo $p^e$ | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| any $m$, $n\lesssim5000$ | Pascal triangle, $O(n^2)$ | no division needed | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |
| huge $n$, small $k$ | $\prod_{i<k}(n-i)\cdot(k!)^{-1}$, $O(k)$ | needs $k<p$ | [05/01](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) |

### 5.3 Stars and bars, multisets

| Count | Formula | Src |
|---|---|---|
| $x_1+\dots+x_k=n$, $x_i\ge0$ / $x_i\ge1$ / $x_i\ge l_i$ | $\binom{n+k-1}{k-1}$ / $\binom{n-1}{k-1}$ / $\binom{n-\sum l_i+k-1}{k-1}$ | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| $x_1+\dots+x_k\le n$, $x_i\ge0$ | $\binom{n+k}k$ (slack variable) | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| $0\le x_i\le c$ / $0\le x_i\le c_i$ | $\sum_j(-1)^j\binom kj\binom{n-j(c+1)+k-1}{k-1}$ / $\sum_S(-1)^{\lvert S\rvert}\binom{n-\sum_S(c_i+1)+k-1}{k-1}$ | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| compositions of $n$: any number of parts / $k$ parts | $2^{n-1}$ / $\binom{n-1}{k-1}$ | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| multisets of size $m$ from $n$ types = non-decreasing length-$m$ sequences over $[1,n]$ | $\binom{n+m-1}m$; strictly increasing: $\binom nm$ | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| $m$ positions in $[1,n]$ with gaps $\ge d$ | $\binom{n-(m-1)(d-1)}m$ ($d=2$: no two adjacent) | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |
| monotone lattice paths $(0,0)\to(a,b)$ | $\binom{a+b}a$ | [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md) |

### 5.4 Inclusion–exclusion and inversion

| Formula | Meaning | Src |
|---|---|---|
| $\lvert\bigcup A_i\rvert=\sum_{\emptyset\ne S}(-1)^{\lvert S\rvert+1}\lvert\bigcap_SA_i\rvert$; none: $\sum_S(-1)^{\lvert S\rvert}\lvert\bigcap_SA_i\rvert$ | | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| exactly $k$ properties: $E_k=\sum_{j\ge k}(-1)^{j-k}\binom jkS_j$, $S_j=\sum_{\lvert S\rvert=j}\lvert\bigcap_SA_i\rvert$ | Jordan | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| 🧊 Bonferroni: truncating after an odd / even number of terms gives an upper / lower bound | | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| $D_n=n!\sum_{j=0}^n\frac{(-1)^j}{j!}=(n-1)(D_{n-1}+D_{n-2})=nD_{n-1}+(-1)^n=\operatorname{round}(n!/e)$ ($n\ge1$) | derangements | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| exactly $k$ fixed points: $\binom nkD_{n-k}$ | | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| surjections $[n]\to[k]$: $\sum_{j=0}^k(-1)^j\binom kj(k-j)^n=k!\,S(n,k)$; arrays over $m$ symbols using exactly $k$: $\binom mk\cdot$ that | $A_i$ = "value $i$ unused" | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| $\#\lbrace x\le N:\gcd(x,n)=1\rbrace=\sum_{S\subseteq\text{primes}(n)}(-1)^{\lvert S\rvert}\lfloor N/\prod_Sp\rfloor$ | | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| "max of the array is exactly $M$": $M^n-(M-1)^n$ | | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| $g(k)=\sum_{t\ge k}\binom tkf(t)\iff f(k)=\sum_{t\ge k}(-1)^{t-k}\binom tkg(t)$ | binomial inversion ("at least" → "exactly") | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| $g(S)=\sum_{T\subseteq S}f(T)\iff f(S)=\sum_{T\subseteq S}(-1)^{\lvert S\setminus T\rvert}g(T)$ | subset Möbius | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| 🧊 $\max(S)=\sum_{\emptyset\ne T\subseteq S}(-1)^{\lvert T\rvert+1}\min(T)$ | min–max IE, also for expectations | [05/03](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) |
| paths avoiding sorted obstacles: $\text{dp}_i=\text{paths}(s,o_i)-\sum_{o_j\prec o_i}\text{dp}_j\,\text{paths}(o_j,o_i)$ | "first obstacle hit", $O(k^2)$ | [06/04](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md) |

### 5.5 Catalan numbers, ballot problems, lattice paths

| Formula | Meaning | Src |
|---|---|---|
| $C_n=\frac1{n+1}\binom{2n}n=\binom{2n}n-\binom{2n}{n+1}$ | reflection | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $C_{n+1}=\sum_{i=0}^nC_iC_{n-i}$; $C_{n+1}=\frac{2(2n+1)}{n+2}C_n$; $C(x)=\frac{1-\sqrt{1-4x}}{2x}$; $C_n\sim\frac{4^n}{n^{3/2}\sqrt\pi}$ | first return; GF from $C=1+xC^2$ | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $C_n$ counts balanced bracket strings of length $2n$, Dyck paths, BSTs on $n$ keys, triangulations of an $(n+2)$-gon; $n$ factors have $C_{n-1}$ full parenthesisations | | [06/05](../06-Dynamic-Programming/05-interval-dp.md) |
| $n$ `(` and $m\le n$ `)` with every prefix balanced: $\binom{n+m}m-\binom{n+m}{m-1}$ | | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $\pm1$ walks from height $h$ to $0$ in $r$ steps staying $\ge0$: $\binom rd-\binom r{d+1}$, $d=\frac{r+h}2$ | reflect at $-1$ | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| ballot: $a>b$ votes, $A$ strictly ahead throughout: probability $\frac{a-b}{a+b}$, count $\frac{a-b}{a+b}\binom{a+b}a$ | | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| Fuss–Catalan: $k$-ary trees with $n$ internal nodes $\frac1{(k-1)n+1}\binom{kn}n$; 🧊 Narayana $\frac1n\binom nk\binom n{k-1}$, $\sum_kN(n,k)=C_n$ | | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| Delannoy (steps R, U, diagonal): $D(m,n)=\sum_k\binom mk\binom nk2^k$ | | [06/04](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md) |

### 5.6 Stirling, Bell, Lah, partitions

| Formula | Meaning | Src |
|---|---|---|
| $S(n,k)=S(n-1,k-1)+kS(n-1,k)$; $S(n,k)=\frac1{k!}\sum_j(-1)^j\binom kj(k-j)^n$ | set partitions into $k$ blocks | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $x^n=\sum_kS(n,k)x^{\underline k}$; $S(n,2)=2^{n-1}-1$, $S(n,n-1)=\binom n2$ | | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $c(n,k)=c(n-1,k-1)+(n-1)c(n-1,k)$; $\sum_kc(n,k)=n!$; $c(n,1)=(n-1)!$ | permutations with $k$ cycles | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $x^{\overline n}=\sum_kc(n,k)x^k$; $x^{\underline n}=\sum_k(-1)^{n-k}c(n,k)x^k$ | rising / falling factorials | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $B_n=\sum_kS(n,k)$; $B_{n+1}=\sum_k\binom nkB_k$; Bell triangle $a_{i,0}=a_{i-1,i-1}$, $a_{i,j}=a_{i,j-1}+a_{i-1,j-1}$ | all set partitions | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| 🧊 Lah $L(n,k)=\binom{n-1}{k-1}\frac{n!}{k!}$ | partitions into $k$ ordered lists | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $p(n,k)=p(n-1,k-1)+p(n-k,k)$ (exactly $k$ parts); $p(100)=190\,569\,292$; $p(n)\sim\frac1{4n\sqrt3}e^{\pi\sqrt{2n/3}}$ | integer partitions | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| $p(n)=\sum_{j\ge1}(-1)^{j+1}\big[p(n-\frac{j(3j-1)}2)+p(n-\frac{j(3j+1)}2)\big]$ | pentagonal recurrence, $O(n\sqrt n)$ | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| distinct parts = odd parts; at most $k$ parts = parts $\le k$ | GF / conjugation | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |

### 5.7 Twelvefold way ($n$ balls into $k$ boxes)

| balls / boxes | any | at most 1 per box | at least 1 per box |
|---|---|---|---|
| distinct / distinct | $k^n$ | $k^{\underline n}$ | $k!\,S(n,k)$ |
| identical / distinct | $\binom{n+k-1}{k-1}$ | $\binom kn$ | $\binom{n-1}{k-1}$ |
| distinct / identical | $\sum_{j\le k}S(n,j)$ | $[n\le k]$ | $S(n,k)$ |
| identical / identical | $\sum_{j\le k}p(n,j)$ | $[n\le k]$ | $p(n,k)$ |

Derivations: [05/02](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md), [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md).

### 5.8 Fibonacci identities ($F_0=0$, $F_1=1$)

| Identity | Meaning | Src |
|---|---|---|
| $\begin{pmatrix}1&1\\1&0\end{pmatrix}^n=\begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$ | matrix form | [07/08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |
| $F_{m+n}=F_mF_{n+1}+F_{m-1}F_n$; $F_{2n}=F_n(2F_{n+1}-F_n)$, $F_{2n+1}=F_n^2+F_{n+1}^2$ | addition; fast doubling $O(\log n)$ | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $F_{n+1}F_{n-1}-F_n^2=(-1)^n$ | Cassini ($\det Q^n$) | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $\sum_{i=1}^nF_i=F_{n+2}-1$; $\sum_{i=1}^nF_i^2=F_nF_{n+1}$ | telescoping | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $\gcd(F_m,F_n)=F_{\gcd(m,n)}$; $F_n=\frac{\varphi^n-\psi^n}{\sqrt5}$, $\varphi,\psi=\frac{1\pm\sqrt5}2$ | Binet | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| Zeckendorf: every $n\ge1$ is uniquely a sum of non-consecutive Fibonacci numbers (greedy) | | [05/04](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md) |
| Pisano period $\pi(m)\le6m$ | $F_n\bmod m$ is periodic | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |

### 5.9 Counting under symmetry

Burnside needs a finite group $G$ acting on a finite set. Dividing by $\lvert G\rvert$ modulo $p$ needs $\gcd(\lvert G\rvert,p)=1$; otherwise compute the sum modulo $p\lvert G\rvert$ and divide exactly.

| Formula | Meaning | Src |
|---|---|---|
| $\lvert Gx\rvert\,\lvert G_x\rvert=\lvert G\rvert$ | orbit–stabiliser | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| $\#\text{orbits}=\frac1{\lvert G\rvert}\sum_{g\in G}\lvert\mathrm{Fix}(g)\rvert$ | Burnside: the average number of fixed objects | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| $k$ colours: $\lvert\mathrm{Fix}(\pi)\rvert=k^{c(\pi)}$, so $\#=\frac1{\lvert G\rvert}\sum_\pi k^{c(\pi)}$ ($c$ = number of cycles) | unweighted special case of Pólya | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| cycle index $Z_G=\frac1{\lvert G\rvert}\sum_g\prod_ix_i^{c_i(g)}$; substitute $x_i=\sum_cw_c^i$ | Pólya, colour-weighted | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| rotation by $r$ of $\mathbb Z_n$: $\gcd(r,n)$ cycles of length $n/\gcd(r,n)$ | | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| necklaces (rotations only): $N(n,k)=\frac1n\sum_{i=1}^nk^{\gcd(i,n)}=\frac1n\sum_{d\mid n}\varphi(n/d)\,k^d$ | $n=6,k=2$: 14 | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| bracelets (dihedral, order $2n$): $\frac{N+R}2$, $R=k^{(n+1)/2}$ ($n$ odd), $R=\frac{k^{n/2+1}+k^{n/2}}2$ ($n$ even) | reflections differ by parity of $n$ | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| Lyndon (aperiodic) necklaces $L(n,k)=\frac1n\sum_{d\mid n}\mu(d)k^{n/d}$; $k^n=\sum_{d\mid n}d\,L(d,k)$ | Möbius inversion | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| fixed content $c_1..c_m$: $\frac1n\sum_{d\mid\gcd(n,c_1,\dots,c_m)}\varphi(d)\binom{n/d}{c_1/d,\dots,c_m/d}$ | | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| proper $k$-colourings of the cycle $C_d$: $(k-1)^d+(-1)^d(k-1)$; necklaces with no equal neighbours: $\frac1n\sum_{d\mid n}\varphi(n/d)\big((k-1)^d+(-1)^d(k-1)\big)$ | | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| $n\times n$ grid up to rotation: $\frac14\big(k^{n^2}+2k^{\lceil n^2/4\rceil}+k^{\lceil n^2/2\rceil}\big)$; with reflections add $2k^{(n^2+n)/2}+2k^{n\lceil n/2\rceil}$ and divide by 8 | $C_4$ / $D_4$ | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |
| cube faces up to rotation: $\frac1{24}(k^6+3k^4+12k^3+8k^2)$ | 2 colours: 10 | [05/05](../05-Combinatorics-and-Probability/05-burnside-and-polya.md) |

### 5.10 Labelled trees and mappings

| Formula | Meaning | Src |
|---|---|---|
| $n^{n-2}$ labelled trees (Cayley); $n^{n-1}$ rooted | Prüfer bijection | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| trees with degrees $d_i$: $\frac{(n-2)!}{\prod(d_i-1)!}$ | $v$ appears $d_v-1$ times in the Prüfer code | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| forests with $k$ trees, $k$ given vertices in different trees: $k\,n^{n-k-1}$ | generalised Cayley | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| spanning trees of $K_{a,b}$: $a^{b-1}b^{a-1}$; of $C_n$: $n$ | | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| functional graphs on $n$ labelled vertices: $n^n$; permutations $n!$ | | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |

### 5.11 Permutations, sequences, orderings

| Fact | Meaning | Src |
|---|---|---|
| inversions $\in[0,\binom n2]$, every value achievable; $\text{inv}$ = adjacent swaps to sort | | [03/03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) |
| sign $=(-1)^{n-c}$ ($c$ cycles incl. fixed points); min swaps to sort $=n-c$; order $=\operatorname{lcm}$(cycle lengths) | | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |
| adjacent swap changes inversions by $\pm1$; reversing a length-$L$ segment changes them by $\equiv\binom L2\pmod2$; a 3-cycle is even | parity invariants | [03/04](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md) |
| Erdős–Szekeres: $>(r-1)(s-1)$ distinct numbers contain an increasing run of length $r$ or a decreasing one of length $s$; tight | | [03/03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) |
| rearrangement: $\sum x_iy_{n+1-i}\le\sum x_iy_{\sigma(i)}\le\sum x_iy_i$ for sorted $x,y$ | pair large with large | [01/05](../01-Foundations/05-sorting-and-comparators.md) |
| $\arg\min_x\sum\lvert x-a_i\rvert$ = any median (weighted median with weights); $\arg\min\sum(x-a_i)^2=\bar a$ | slope argument | [02/06](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md) |
| $\arg\min_x\max_i(t_i+\lvert x-x_i\rvert)=\frac12\big(\max(x_i+t_i)+\min(x_i-t_i)\big)$ | | [02/06](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md) |
| pigeonhole: $n$ items in $k$ boxes put $\ge\lceil n/k\rceil$ in one; among $S_0..S_n\bmod n$ two coincide → a subarray with sum $\equiv0$ | guaranteed existence | [03/04](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md) |
| concatenation order $a\prec b\iff a+b<b+a$ is a strict weak order (compares $\frac{\mathrm{val}(a)}{K^{\lvert a\rvert}-1}$) | "largest number" greedy | [03/01](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) |
| scheduling: $\sum C_i$ by SPT; $\sum w_iC_i$ by $p_i/w_i$ (Smith, $p_iw_j\le p_jw_i$); $L_{\max}$ by deadline (EDF) | adjacent exchange | [03/01](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) |
| unit jobs with deadlines: $S$ feasible $\iff\forall t:\lvert\lbrace i\in S:d_i\le t\rbrace\rvert\le t$ | a matroid, so greedy is optimal | [03/02](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md) |
| even split of $a$ into $p$ parts minimises $\sum$ squares: $r(q+1)^2+(p-r)q^2$, $q=\lfloor a/p\rfloor$, $r=a\bmod p$ | convex allocation | [03/02](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md) |
| Huffman: cost $=\sum$ of internal-node weights; merge the two smallest | | [03/01](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) |
| min rooms = max overlap; max disjoint intervals = min stabbing points | interval graphs are perfect | [02/05](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md), [03/01](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) |

### 5.12 Contribution technique

| Quantity | Formula | Src |
|---|---|---|
| $\sum_{\text{subarrays}}\text{sum}$; subarrays containing $i$ (1-based) | $\sum_ia_i\,i(n-i+1)$; $i(n-i+1)$ | [05/07](../05-Combinatorics-and-Probability/07-contribution-technique.md) |
| $\sum_{\text{subsets}}\text{sum}$; over subsets of size $k$ | $2^{n-1}\sum a_i$; $\binom{n-1}{k-1}\sum a_i$ | [05/07](../05-Combinatorics-and-Probability/07-contribution-technique.md) |
| $\sum_{\text{subarrays}}\min$ ($L_i$ = previous $\le$, $R_i$ = next $<$) | $\sum_ia_i(i-L_i)(R_i-i)$; check $\sum(i-L_i)(R_i-i)=\frac{n(n+1)}2$ | [02/04](../02-Core-Techniques/04-monotonic-stack-and-deque.md) |
| $\sum_{\text{subsets}}\max$ / $\min$ (sorted ascending, 0-based) | $\sum a_i2^i$ / $\sum a_i2^{n-1-i}$; size $k$: $\sum a_i\big(\binom i{k-1}-\binom{n-1-i}{k-1}\big)$ for $\max-\min$ | [05/07](../05-Combinatorics-and-Probability/07-contribution-technique.md) |
| $\sum_{i<j}\lvert a_i-a_j\rvert$ (sorted, 0-based); $\sum_{i<j}a_ia_j$ | $\sum a_i(2i-n+1)$; $\frac{(\sum a)^2-\sum a^2}2$ | [05/07](../05-Combinatorics-and-Probability/07-contribution-technique.md) |
| $\sum_{u<v}\operatorname{dist}(u,v)$ in a tree | $\sum_{e}w_e\,s_e(n-s_e)$ | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| over all permutations: fixed points / inversions | $n!$ / $n!\binom n2/2$ | [05/07](../05-Combinatorics-and-Probability/07-contribution-technique.md) |
| $\sum_S\sum_{x\in S}w(x)=\sum_xw(x)\,\#\lbrace S\ni x\rbrace$; expectation = contribution sum / #structures | the general principle | [16/07](../16-IGM-Frontier/07-how-grandmasters-think.md) |

---

## 6. Probability and expected value

| Formula | Meaning | Src |
|---|---|---|
| $P(A\cup B)=P(A)+P(B)-P(A\cap B)$; $P(A\cap B)=P(B)P(A\mid B)$; $P(A)=\sum_iP(B_i)P(A\mid B_i)$; Bayes $P(B\mid A)=\frac{P(A\mid B)P(B)}{P(A)}$ | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| $E[X+Y]=E[X]+E[Y]$ always; $E[XY]=E[X]E[Y]$ if independent; $E[I_A]=P(A)$ | linearity, indicators | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| $E[X]=\sum_{k\ge1}P(X\ge k)$ for $X\in\mathbb Z_{\ge0}$; $E[X]=\int_0^\infty P(X>t)\,dt$ for $X\ge0$ | tail sums (expected maximum) | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| $E[X]=\sum_iP(B_i)E[X\mid B_i]$; $E(s)=c(s)+\sum_tp(s\to t)E(t)$ | total expectation = expectation DP | [06/10](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md) |
| self-loop with probability $q$: $E(s)=\frac{c(s)+\sum_{t\ne s}p_tE(t)}{1-q}$; one cyclic unknown $E_i=a_i+b_iE_0\Rightarrow E_0=\frac{a_0}{1-b_0}$ | removing cycles | [06/10](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md) |
| geometric: $E=\frac1p$, $\operatorname{Var}=\frac{1-p}{p^2}$; repeated attempts costing $C$ each, success $\pi$: $C/\pi$ | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| Wald: $E[\sum_{i\le N}Y_i]=E[N]E[Y]$ for i.i.d. $Y_i$ and a stopping time $N$ | | [06/10](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md) |
| $\operatorname{Bin}(n,p)$: $E=np$, $\operatorname{Var}=np(1-p)$, $E[X^{\underline k}]=n^{\underline k}p^k$ | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| coupon collector: all $n$: $nH_n$; first $k$ distinct: $\sum_{i<k}\frac n{n-i}$; 🧊 unequal $p_i$: $\sum_{\emptyset\ne S}\frac{(-1)^{\lvert S\rvert+1}}{\sum_{i\in S}p_i}$ | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| max of $n$ rolls of an $m$-sided die: $P(\max\le k)=(k/m)^n$, $E=m-\sum_{k=1}^{m-1}(k/m)^n$ | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| $n$ i.i.d. $U(0,1)$: $E[\min]=\frac1{n+1}$, $E[k\text{-th smallest}]=\frac k{n+1}$ | exchangeable gaps | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| random permutation: $E[\text{fixed points}]=1$, $E[\text{cycles}]=H_n$, $E[\text{inversions}]=\frac{n(n-1)}4$, $E[\text{records}]=H_n$ | element $i$ is a record w.p. $1/i$ | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| $\operatorname{Var}X=E[X^2]-E[X]^2$; $\operatorname{Var}\sum X_i=\sum\operatorname{Var}X_i+2\sum_{i<j}\operatorname{Cov}$; $E[(\sum I_i)^2]=\sum P(A_i)+2\sum_{i<j}P(A_i\cap A_j)$ | second moments via pairs | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| fair walk on $[0,N]$ from $i$: $P(\text{hit }N\text{ first})=\frac iN$, $E[\text{time}]=i(N-i)$; 🧊 biased, $r=q/p\ne1$: $\frac{1-r^i}{1-r^N}$ | gambler's ruin | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| birthday: $P(\text{no repeat in }k\text{ draws from }n)\approx e^{-k^2/(2n)}$; first repeat after $\approx\sqrt{\pi n/2}$ draws | | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| Markov $P(X\ge a)\le\frac{E[X]}a$; Chebyshev $P(\lvert X-\mu\rvert\ge t)\le\frac{\operatorname{Var}X}{t^2}$ | bounds for randomised algorithms | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| answer $\frac ab$ modulo $p$: $a\cdot b^{p-2}\bmod p$ | never divide by a residue that may be 0 | [05/06](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |

---

## 7. Dynamic programming and the conditions behind DP optimisations

### 7.1 DP identities

| Formula | Meaning | Src |
|---|---|---|
| $f(t)=\bigoplus_{s\to t}f(s)\otimes w(s,t)$; time $=\sum_s\deg^-(s)=O(V+E)$ | Bellman equation over a semiring, evaluated in topological order | [06/01](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md) |
| counting needs disjoint classes (sum rule) and independent parts (product rule) | why decompositions must be unambiguous | [06/01](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md) |
| $f(i)=\sum_{j=i-k}^{i-1}f(j)=P(i-1)-P(i-k-1)$ | range transition in $O(1)$ | [07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| state counts: subsets $2^n$; (subset, last) $n2^n$; (set, submask) $3^n$; intervals $\frac{n(n+1)}2$ | $2^{20}\cdot20$ `int` $=80$ MB | [06/06](../06-Dynamic-Programming/06-bitmask-dp.md) |
| knapsack loops: 0/1 capacity downward, unbounded upward; multisets coins outer; ordered sequences sum outer | | [06/02](../06-Dynamic-Programming/02-knapsack-family.md) |
| GFs: 0/1 $\prod(1+x^{w_i})$; multisets $\prod\frac1{1-x^{c_j}}$; sequences $\frac1{1-\sum x^{c_j}}$ | coefficient of $x^s$ = count | [06/02](../06-Dynamic-Programming/02-knapsack-family.md) |
| binary splitting $c=(1,2,\dots,2^{k-1},r)$, $0\le r<2^k$: subset sums are exactly $0..c$ | bounded knapsack $O(W\sum\log c_i)$ | [06/02](../06-Dynamic-Programming/02-knapsack-family.md) |
| bitset subset sum $R\leftarrow R\lor(R\ll w)$: $O(nS/64)$; $\sum w_i=S\Rightarrow\le\sqrt{2S}$ distinct $w_i$ | | [16/05](../16-IGM-Frontier/05-bitset-optimization.md) |
| any $m$ numbers have a non-empty block with sum $\equiv0\pmod m$ | "divisible subset" is YES for $n\ge m$ | [06/02](../06-Dynamic-Programming/02-knapsack-family.md) |
| ins/del distance $=\lvert a\rvert+\lvert b\rvert-2\,\mathrm{LCS}$; LPS $=\mathrm{LCS}(s,s^R)$; min insertions to a palindrome $=n-\mathrm{LPS}$ | | [06/03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md) |
| distinct subsequences $D(i)=2D(i-1)-D(p-1)$, $p$ = previous occurrence of $s_i$ | | [06/03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md) |
| strictly increasing integers $\iff a_i-i$ non-decreasing; 2-D chains: sort by $x$ asc, ties $y$ desc, then strict LIS on $y$ | | [06/03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md) |
| min #non-increasing subsequences covering $a$ = strict LIS length (and symmetric) | Dilworth on sequences | [06/03](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md) |
| $\#\lbrace x\in[L,R]:P\rbrace=F(R)-F(L-1)$; $r'=(10r+d)\bmod m$ | digit DP | [06/07](../06-Dynamic-Programming/07-digit-dp.md) |
| length-$r$ digit strings with $\le k$ non-zero digits: $\sum_{j\le k}\binom rj9^j$; $k$-digit numbers with distinct digits $9\cdot\frac{9!}{(10-k)!}$, total $8\,877\,690$ | closed-form completions | [06/07](../06-Dynamic-Programming/07-digit-dp.md) |
| tree: $\text{sz}(v)=1+\sum\text{sz}(c)$; reroot distance sums $S(c)=S(v)+n-2\,\text{sz}(c)$; connected sets containing $v$ in its subtree $\prod_c(h(c)+1)$ | | [06/08](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md) |
| edge on a shortest $s$–$t$ path iff $d_s(u)+w+d_t(v)=d_s(t)$; on **all** of them iff also $\text{cnt}_s(u)\,\text{cnt}_t(v)=\text{cnt}_s(t)$ | count modulo random primes | [06/09](../06-Dynamic-Programming/09-dp-on-dags-and-graphs.md) |
| domino tilings: $2\times n$: $T_n=T_{n-1}+T_{n-2}$; $3\times n$: $T_n=4T_{n-2}-T_{n-4}$ ($1,3,11,41,\dots$); $nm$ odd: 0 | | [06/11](../06-Dynamic-Programming/11-broken-profile-dp.md) |
| Kasteleyn: $T(n,m)=\prod_{j=1}^{\lceil n/2\rceil}\prod_{k=1}^{\lceil m/2\rceil}\left(4\cos^2\frac{\pi j}{n+1}+4\cos^2\frac{\pi k}{m+1}\right)$ | real-valued check ($8\times8$: 12 988 816) | [06/11](../06-Dynamic-Programming/11-broken-profile-dp.md) |

### 7.2 Optimisation techniques: shape, validity condition, cost

| Technique | Transition shape | Valid when | Cost | Src |
|---|---|---|---|---|
| prefix sums | $dp_i=\sum_{j\in[L_i,R_i]}dp_j$ | always | $O(n)$ | [07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| monotonic deque | $dp_i=h(i)+\min_{j\in[L_i,R_i]}g(j)$ | $L_i,R_i$ non-decreasing **and** $g(j)$ independent of $i$ | $O(n)$ | [07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| CHT, deque | $dp_i=d_i+\min_j(m_jx_i+b_j)$ | slopes inserted sorted; pointer queries need sorted $x$ (else binary search, $O(\log n)$) | amortised $O(1)$ | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| LineContainer | same | any insertion and query order (integer queries) | $O(\log n)$ | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| Li Chao tree | same; also any functions of which two cross at most once | query domain of size $C$ known (or dynamic nodes) | $O(\log C)$; segments $O(\log^2C)$ insert | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| divide and conquer | $dp_t(i)=\min_{j<i}dp_{t-1}(j)+C(j,i)$ | $C$ satisfies QI (min) or reverse QI (max) $\Rightarrow\mathrm{opt}(i)\le\mathrm{opt}(i+1)$ for any previous layer | $O(kn\log n)$ | [07/03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md) |
| Knuth, interval | $dp[i][j]=C(i,j)+\min_{i\le k<j}dp[i][k]+dp[k+1][j]$ | $C$ satisfies QI **and** $C(b,c)\le C(a,d)$ for $[b,c]\subseteq[a,d]$, $C$ independent of $k$ | $O(n^2)$ | [07/04](../07-DP-Optimizations/04-knuth-optimization.md) |
| Knuth, layered | $k$-partition DP | QI $\Rightarrow\mathrm{opt}_{t-1}[i]\le\mathrm{opt}_t[i]\le\mathrm{opt}_t[i+1]$ (fill $t\uparrow$, $i\downarrow$) | $O(n(n+k))$ | [07/04](../07-DP-Optimizations/04-knuth-optimization.md) |
| Aliens / WQS | best value $f(k)$ with exactly $k$ uses | $f$ convex in $k$ (min) / concave (max) | $O(T_{\text{inner}}\log R)$ | [07/06](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) |
| slope trick | $dp_i(x)$ built from $\lvert x-a\rvert$, $(x-a)^+$, prefix/suffix/window minima | every function convex piecewise linear | $O(n\log n)$ | [07/07](../07-DP-Optimizations/07-slope-trick.md) |
| matrix power | $v_n=v_0T^n$ | transition independent of the step; semiring must distribute | $O(m^3\log n)$ | [07/08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |

Matrix chain, polygon triangulation and burst balloons have a cost that depends on $k$, so Knuth's bound does **not** apply to them ([07/04](../07-DP-Optimizations/04-knuth-optimization.md)).

### 7.3 Formulas inside the optimisations

| Formula | Meaning | Src |
|---|---|---|
| QI: $C(a,c)+C(b,d)\le C(a,d)+C(b,c)$ for $a\le b\le c\le d$ ("crossing $\le$ nested"); local form $C(a,c)+C(a+1,c+1)\le C(a,c+1)+C(a+1,c)$ implies it | check by brute force on small inputs | [07/03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md) |
| QI families: $h(P_i-P_j)$ with $h$ convex and $P$ non-decreasing; $\sum_{j<p<q\le i}w_{pq}$ with $w\ge0$; $k$-median cost $\sum c_t\lvert t-m\rvert$ | | [07/03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md) |
| reverse QI (maximisation only): distinct count of a segment, segment maximum; minimising group max by D&C is wrong (e.g. $[6,7,2,7]$, $k=2$) | | [07/03](../07-DP-Optimizations/03-divide-and-conquer-optimization.md) |
| QI + monotone $C\Rightarrow dp$ satisfies QI (Yao) $\Rightarrow\mathrm{opt}[i][j-1]\le\mathrm{opt}[i][j]\le\mathrm{opt}[i+1][j]$ | Knuth's bound | [07/04](../07-DP-Optimizations/04-knuth-optimization.md) |
| $\sum_i\big(\mathrm{opt}[i+1][i+d]-\mathrm{opt}[i][i+d-1]+1\big)\le2n$ per length $d$; D&C: $\le n+\#\text{nodes}$ candidates per level | telescoping costs | [07/04](../07-DP-Optimizations/04-knuth-optimization.md) |
| $(s_i-s_j)^2=s_i^2-2s_js_i+s_j^2$: line $m_j=-2s_j$, $b_j=dp_j+s_j^2$ | the usual CHT source | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| intersection $x_{12}=\frac{b_2-b_1}{m_1-m_2}$; $\ell_2$ useless (min hull, $m_1>m_2>m_3$) iff $(b_3-b_1)(m_1-m_2)\le(b_2-b_1)(m_1-m_3)$; last integer with $\ell_1\le\ell_2$: $\lfloor\frac{b_2-b_1}{m_1-m_2}\rfloor$ | products need 128 bits | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| $\max_j(m_jx+b_j)=-\min_j(-m_jx-b_j)$ | max hull from min hull | [07/02](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) |
| $\max_y(f(y)-c\lvert x-y\rvert)=\max\big(\max_{y\le x}(f(y)+cy)-cx,\ \max_{y\ge x}(f(y)-cy)+cx\big)$, $c\ge0$ | two sweeps | [07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| bounded knapsack: $nd[r+qw]=qv+\max_{q-c\le p\le q}(dp[r+pw]-pv)$; count: $nd[x]=nd[x-w]+dp[x]-dp[x-(c+1)w]$ | per residue class, $O(W)$ per item | [07/01](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md) |
| Aliens: $g(\lambda)=\min_kf(k)+\lambda k$; $k$ optimal iff $-\Delta_{k+1}\le\lambda\le-\Delta_k$ ($\Delta_k=f(k)-f(k-1)$); answer $f(k)=g(\lambda^*)-\lambda^*k$ | use $k$, not the DP's count; break ties toward fewer uses | [07/06](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) |
| $\lambda<\lambda'\Rightarrow\arg\min(\lambda')\le\arg\min(\lambda)$; convex $f$: $f(k)=\max_\lambda(g(\lambda)-\lambda k)$ | monotonicity; duality | [07/06](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) |
| slope trick: $f(x)=\min f+\sum_{l\in L}(l-x)^++\sum_{r\in R}(x-r)^+$, $\max L\le\min R$; minimisers $[\max L,\min R]$ | two heaps | [07/07](../07-DP-Optimizations/07-slope-trick.md) |
| $f\mathrel{+}=(x-a)^+$: $\min f\mathrel{+}=(\max L-a)^+$, push $a$ to $L$, move $\max L$ to $R$ (mirror for $(a-x)^+$); prefix min: clear $R$; window min: lazy shifts | $O(\log n)$ each | [07/07](../07-DP-Optimizations/07-slope-trick.md) |

### 7.4 Subset transforms and convolutions

| Formula | Meaning | Src |
|---|---|---|
| zeta $\hat a[m]=\sum_{s\subseteq m}a[s]$; Möbius $a[m]=\sum_{s\subseteq m}(-1)^{\lvert m\setminus s\rvert}\hat a[s]$; superset versions by complement | $n$ axis-wise prefix sums, $O(n2^n)$ | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| "exactly $m$" from "at least": $\sum_{s\supseteq m}(-1)^{\lvert s\setminus m\rvert}\text{atLeast}[s]$ | superset Möbius = IE | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| OR: $\zeta(f*_\lor g)=\zeta f\cdot\zeta g$; AND: superset zeta; XOR: $\widehat{f*_\oplus g}=\hat f\hat g$ with WHT $(u,v)\mapsto(u+v,u-v)$, inverse $/2^n$ | multiply only in the transformed domain | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| subset convolution $h[S]=\sum_{T\subseteq S}f[T]g[S\setminus T]$ via ranked zeta | $O(n^22^n)$ | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| non-empty subsets with AND $=0$: $\sum_m(-1)^{\lvert m\rvert}(2^{c[m]}-1)$, $c$ = superset sums of counts; pairs with $a_i\mathbin\&a_j=0$: $\sum_i\zeta(\text{cnt})[\lnot a_i]$ | | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |
| divisor-lattice zeta $F[x]=\sum_{d\mid x}a[d]$: per prime $p$, $a[px]\mathrel{+}=a[x]$ for $x$ ascending | $O(V\log\log V)$ | [07/05](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md) |

---

## 8. Linear algebra, recurrences, determinants

| Formula | Meaning | Src |
|---|---|---|
| $a_n=\sum_{i=1}^dc_ia_{n-i}$: companion matrix (first row $c_1..c_d$, ones below the diagonal), $s_n=M^{n-d+1}s_{d-1}$ | $O(d^3\log n)$; Kitamasa $x^n\bmod$ char. poly: $O(d^2\log n)$ | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $(A^k)_{uv}$ = number of walks of length $k$; over $(\min,+)$: cheapest walk with exactly $k$ edges | semiring powers | [07/08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |
| $\begin{pmatrix}A&I\\0&I\end{pmatrix}^k=\begin{pmatrix}A^k&\sum_{i<k}A^i\\0&I\end{pmatrix}$ | geometric series without division | [07/08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |
| $u^TM^nv$ ($M$ is $k\times k$) satisfies a linear recurrence of order $\le k$; Berlekamp–Massey finds it from $2L$ terms (prime modulus), $O(N^2)$ | Cayley–Hamilton | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) |
| multiplicative recurrences: exponents mod $p-1$ ($g^e\equiv g^{e\bmod(p-1)}$, $p\nmid g$) | | [15/01](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) |
| $Ax=b$ over $\mathbb F_q$: $q^{m-\operatorname{rank}A}$ solutions if $\operatorname{rank}A=\operatorname{rank}[A\mid b]$, else none | Rouché–Capelli | [15/02](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) |
| $\det=(-1)^{\#\text{swaps}}\prod\text{pivots}$; $[A\mid I]\to[I\mid A^{-1}]$, exists iff $\det\ne0$; composite modulus: Euclid on rows | $O(n^3)$; $O(n^3\log M)$ worst | [15/02](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) |
| XOR basis of $S$ with rank $r\le B$: $2^r$ representable values, each by $2^{\lvert S\rvert-r}$ subsets; non-empty subsets with XOR 0: $2^{\lvert S\rvert-r}-1$ | | [15/02](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) |
| max XOR: $v\leftarrow\max(v,v\oplus b_i)$ from the top bit; $k$-th smallest from the reduced basis (exists iff $k<2^r$) | | [15/02](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) |
| XOR of $s$–$t$ walks $=d(t)\oplus\operatorname{span}(\text{cycle XORs})$ | cycle space | [09/09](../09-Graphs/09-bipartite-graphs-and-cycles.md) |
| **Kirchhoff**: undirected multigraph, $L=D-A$ with $A_{uv}$ = number of $u$–$v$ edges; every cofactor (delete row and column $r$) equals the number of spanning trees | remove self-loops first; a disconnected graph gives 0; compute mod a prime by elimination | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| weighted: $\det L^{(w)}_{\hat r\hat r}=\sum_T\prod_{e\in T}w_e$; $\tau=\frac1n\prod_{i\ge2}\lambda_i(L)$ | | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| 🧊 Tutte: in-degree Laplacian ($L_{vv}=\text{indeg}$, $L_{uv}=-\#(u\to v)$) minor at $r$ counts out-arborescences rooted at $r$; use out-degrees for in-trees | directed | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| 🧊 BEST: connected Eulerian digraph has $t_w\prod_v(\deg^+v-1)!$ Euler circuits, $t_w$ = arborescences toward any fixed $w$ | | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| LGV: in a DAG, $\det[e(a_i,b_j)]=\sum_{\text{vertex-disjoint }(P_i:a_i\to b_{\sigma(i)})}\operatorname{sign}\sigma$; when only $\sigma=\mathrm{id}$ is possible it counts the systems; two paths: $e_{11}e_{22}-e_{12}e_{21}$ | non-intersecting paths | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| expected hitting times $E_v=1+\sum_up_{vu}E_u$: Gaussian elimination; tridiagonal (Thomas): $c'_j=\frac{c_j}{b_j-a_jc'_{j-1}}$, $d'_j=\frac{d_j-a_jd'_{j-1}}{b_j-a_jc'_{j-1}}$, $x_j=d'_j-c'_jx_{j+1}$ | $O(n^3)$ / $O(n)$, stable if diagonally dominant | [15/06](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) |
| entries $<p\approx10^9$: one product $<10^{18}$; `(a*b + c*d) % p` is safe, long sums are not | | [07/08](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |

---

## 9. Polynomials, FFT/NTT, generating functions, interpolation

| Formula | Meaning | Src |
|---|---|---|
| $c_k=\sum_{i+j=k}a_ib_j$, $\deg C=\deg A+\deg B$; transform length $N\ge\deg A+\deg B+1$, a power of two | convolution | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| $\omega_N^{N/2}=-1$, $\omega_N^2=\omega_{N/2}$; $A(x)=E(x^2)+xO(x^2)$, $A(\omega^{k+N/2})=E-\omega^kO$ | halving lemma, butterfly; $T(N)=2T(N/2)+O(N)$ | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| $\sum_{k<N}\omega^{tk}=N[N\mid t]$; $F^{-1}=\frac1N\bar F$ | inverse DFT | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| NTT: $\omega_N=g^{(p-1)/N}$, $\omega_N^{-1}=\omega_N^{p-2}$, $N^{-1}=N^{p-2}$; needs $N\mid p-1$ | $998244353$: $N\le2^{23}$, $g=3$ | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| `double` FFT is safe while true results are $\lesssim10^{14}$; larger: split, or three NTT primes + Garner | | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| wildcard matching at shift $i$: $\sum_jP_jT_{i+j}(P_j-T_{i+j})^2=0$ (wildcard $=0$) | three convolutions | [15/03](../15-Advanced-Math/03-fft-and-ntt.md) |
| $\frac1{1-cx}=\sum c^nx^n$; $\frac1{(1-x)^k}=\sum\binom{n+k-1}{k-1}x^n$; $\frac{1-x^{c+1}}{1-x}$ = at most $c$ copies | ordinary GFs | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| Fibonacci $\frac x{1-x-x^2}$; Catalan $\frac{1-\sqrt{1-4x}}{2x}$; partitions $\prod_{k\ge1}\frac1{1-x^k}$ | | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| Euler: $\prod_{k\ge1}(1-x^k)=\sum_{j\in\mathbb Z}(-1)^jx^{j(3j-1)/2}$; $\prod(1+x^k)=\prod\frac1{1-x^{2k-1}}$ | pentagonal theorem; distinct = odd parts | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| EGF product $\hat A\hat B\leftrightarrow\sum_k\binom nka_kb_{n-k}$; sets of connected labelled structures $e^{\hat C}$; Bell $e^{e^x-1}$; $S(\cdot,k)$: $\frac{(e^x-1)^k}{k!}$; permutations $\frac1{1-x}$ | exponential GFs | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| Newton: inverse $B\leftarrow B(2-AB)$; $\ln A=\int A'A^{-1}$; $\exp$: $B\leftarrow B(1-\ln B+A)$; sqrt $B\leftarrow\frac12(B+A/B)$ | $O(n\log n)$ each | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| product of $m$ polynomials of total degree $N$ by D&C | $O(N\log N\log m)$ | [15/04](../15-Advanced-Math/04-polynomials-and-generating-functions.md) |
| Lagrange $P(x)=\sum_iy_i\prod_{j\ne i}\frac{x-x_j}{x_i-x_j}$; for $x_i=0..n$: $\prod_{j\ne i}(i-j)=i!\,(n-i)!\,(-1)^{n-i}$ | $O(n^2)$ / $O(n)$ per point | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) |
| $\Delta m^{\underline d}=d\,m^{\underline{d-1}}$; $\deg\Delta S=\deg S-1$; $\Delta^{p+1}f\equiv0$ for $\deg f=p$ | finite differences; polynomial range adds | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md), [02/01](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) |
| $\binom{p-1}k\equiv(-1)^k\pmod p$; $1-(x-i)^{p-1}\equiv[x\equiv i]\pmod p$ | Fermat-indicator interpolation | [15/05](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md) |

---

## 10. Graphs, flows and matching

### 10.1 Structure and counting

| Fact | Meaning | Src |
|---|---|---|
| $\sum_v\deg v=2m$ (so #odd-degree vertices is even); directed $\sum\deg^+=\sum\deg^-=m$ | handshake | [09/01](../09-Graphs/01-graph-representation-bfs-dfs.md) |
| simple graph $m\le\binom n2$; forest $m=n-c$; a cycle exists $\iff m>n-c$ | | [09/09](../09-Graphs/09-bipartite-graphs-and-cycles.md) |
| cycle space has dimension $m-n+c$; number of even-degree edge subsets $=2^{m-n+c}$ | cyclomatic number | [09/08](../09-Graphs/08-euler-paths-and-circuits.md) |
| BFS: $\lvert d(u)-d(v)\rvert\le1$ on every undirected edge; an edge inside a layer closes an odd cycle | | [09/01](../09-Graphs/01-graph-representation-bfs-dfs.md) |
| bipartite $\iff$ no odd cycle $\iff$ 2-colourable; $2^c$ proper 2-colourings; $m\le ab\le\lfloor n^2/4\rfloor$ | | [09/09](../09-Graphs/09-bipartite-graphs-and-cycles.md) |
| Mantel: triangle-free $\Rightarrow m\le\lfloor n^2/4\rfloor$; girth $\ge2k+1\Rightarrow m=O(n^{1+1/k})$ | extremal bounds | [09/09](../09-Graphs/09-bipartite-graphs-and-cycles.md) |
| planar: $V-E+F=1+C$ ($=2$ if connected); $E\le3V-6$, triangle-free (e.g. bipartite) $E\le2V-4$ ($V\ge3$) | Euler's formula | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |
| connected cactus: #cycles $=m-n+1$, $m\le\lfloor3(n-1)/2\rfloor$ | | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |
| $G$ disconnected $\Rightarrow\bar G$ connected; $\bar G$ given by $m$ missing edges with $k$ components $\Rightarrow\binom k2\le m$ | complement BFS $O(n+m)$ | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |
| functional graph: each component is one cycle with in-trees; $x_i=x_j$ ($i<j$) iff $i\ge\mu$ and $\lambda\mid j-i$; $\mu+\lambda\le n$ | $\rho$ shape | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |
| random mapping: expected tail and cycle $\approx\sqrt{\pi n/8}$ each, $\rho$ length $\approx\sqrt{\pi n/2}$ | why Pollard rho is $O(n^{1/4})$ | [09/10](../09-Graphs/10-functional-graphs-and-special-graphs.md) |

### 10.2 Paths, MST, DAGs, SCCs, connectivity

| Fact | Meaning | Src |
|---|---|---|
| at optimum $d(v)\le d(u)+w(u,v)$; edge on some shortest path iff equality | shortest-path DAG | [09/02](../09-Graphs/02-shortest-paths.md) |
| Bellman–Ford round $k$: $d[v]\le$ best walk with $\le k$ edges; a relaxation in round $n$ ⇒ reachable negative cycle | $O(nm)$ | [09/02](../09-Graphs/02-shortest-paths.md) |
| reweighting $w'=w+h(u)-h(v)$ keeps shortest paths, $\operatorname{dist}=\operatorname{dist}'-h(s)+h(t)$ | Johnson, min-cost-flow potentials | [09/02](../09-Graphs/02-shortest-paths.md) |
| $x_v-x_u\le w$ ⇒ edge $u\to v$ of weight $w$; feasible iff no negative cycle | difference constraints | [09/02](../09-Graphs/02-shortest-paths.md) |
| Floyd: $k$ outermost; $d[i][i]<0$ ⇒ negative cycle; min undirected cycle $\min_{i<j<k}d_{k-1}[i][j]+w(j,k)+w(k,i)$ | $O(n^3)$ | [09/02](../09-Graphs/02-shortest-paths.md) |
| 0-1 BFS: deque values non-decreasing with spread $\le1$; Dijkstra needs $w\ge0$ | | [09/01](../09-Graphs/01-graph-representation-bfs-dfs.md) |
| cut property: a lightest edge across a cut is in some MST; cycle property: a strictly heaviest cycle edge is in no MST; distinct weights ⇒ unique MST | | [09/03](../09-Graphs/03-minimum-spanning-trees.md) |
| all MSTs share the sorted weight multiset; forced edge $\text{MST}(e)=W-\text{pathmax}_T(u,v)+w(e)$ | second-best MST | [09/03](../09-Graphs/03-minimum-spanning-trees.md) |
| bottleneck path value $=\text{pathmax}_T(u,v)=$ weight of $\operatorname{LCA}(u,v)$ in the Kruskal tree | | [09/03](../09-Graphs/03-minimum-spanning-trees.md) |
| topological order exists $\iff$ no directed cycle; it is unique $\iff$ consecutive vertices are adjacent | Kahn queue size 1 throughout | [09/04](../09-Graphs/04-topological-sort-and-dag-dp.md) |
| condensation is a DAG; adding $\max(s,t)$ edges makes it strongly connected ($k\ge2$ SCCs, $s$ sources, $t$ sinks) | Eswaran–Tarjan | [09/05](../09-Graphs/05-scc-and-condensation.md) |
| 2-SAT: satisfiable $\iff$ no $x$ with $x,\neg x$ in one SCC; set $x$ true iff $\text{comp}(x)$ comes after $\text{comp}(\neg x)$ in topological order; "exactly one of $\ge3$" is not 2-CNF | | [09/07](../09-Graphs/07-two-sat.md) |
| bridge $(p,v)\iff\text{low}[v]>\text{tin}[p]$; non-root cut vertex $\iff$ some child has $\text{low}\ge\text{tin}[p]$; root iff $\ge2$ children | low-link | [09/06](../09-Graphs/06-bridges-articulation-points-and-bcc.md) |
| bridges form a forest ($\le n-1$); block-cut tree has $n+B$ nodes; bridge-tree with $L$ leaves needs $\lceil L/2\rceil$ edges to become 2-edge-connected | | [09/06](../09-Graphs/06-bridges-articulation-points-and-bcc.md) |
| Whitney $\kappa\le\lambda\le\delta$; Robbins: a strongly connected orientation exists $\iff$ connected and bridgeless | | [09/06](../09-Graphs/06-bridges-articulation-points-and-bcc.md) |

### 10.3 Euler tours

| Graph | Circuit iff | Trail iff | Src |
|---|---|---|---|
| undirected | all degrees even, edges connected | exactly 0 or 2 odd vertices (the ends), edges connected | [09/08](../09-Graphs/08-euler-paths-and-circuits.md) |
| directed | $\text{in}=\text{out}$ everywhere, edges weakly connected | one vertex $\text{out}-\text{in}=1$, one $\text{in}-\text{out}=1$, rest balanced | [09/08](../09-Graphs/08-euler-paths-and-circuits.md) |

Minimum trails covering every edge once: $\max(1,k)$ per component with $2k$ odd vertices (directed: $\max(1,D)$, $D=\sum\max(0,\text{out}-\text{in})$).
de Bruijn $B(k,n)$: cyclic length $k^n$ (linear $k^n+n-1$), graph on $k^{n-1}$ vertices; number of sequences $\frac{(k!)^{k^{n-1}}}{k^n}$, binary $2^{2^{n-1}-n}$ (BEST).
Chinese postman: total weight + min-weight perfect matching of odd vertices under shortest-path distances. Source: [09/08](../09-Graphs/08-euler-paths-and-circuits.md).

### 10.4 Flows and cuts

| Statement | Meaning | Src |
|---|---|---|
| $c_f(u,v)=c(u,v)-f(u,v)+f(v,u)$; $\lvert f\rvert=f(S\to T)-f(T\to S)\le c(S,T)$ | residual capacity; weak duality | [12/01](../12-Flows-and-Matching/01-max-flow-dinic.md) |
| max flow = min cut; integer capacities ⇒ an integral max flow exists | | [12/01](../12-Flows-and-Matching/01-max-flow-dinic.md) |
| any flow = at most $E$ path and cycle flows; Edmonds–Karp $\le VE/2$ augmentations; Dinic $\le V-1$ phases | | [12/01](../12-Flows-and-Matching/01-max-flow-dinic.md) |
| Dinic $O(V^2E)$; unit capacities $O(E\min(\sqrt E,V^{2/3}))$; unit network (matching) $O(E\sqrt V)$ | | [12/01](../12-Flows-and-Matching/01-max-flow-dinic.md) |
| Menger: max edge-disjoint $s$–$t$ paths = min edge cut; internally vertex-disjoint = min vertex separator ($s,t$ non-adjacent) | | [12/02](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |
| max-weight closure $=\sum_{p_i>0}p_i-\text{mincut}$ | project selection | [12/02](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |
| pair cost representable by a cut iff $\theta(S,T)+\theta(T,S)\ge\theta(S,S)+\theta(T,T)$ | submodularity | [12/02](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |
| lower bounds: excess $\text{ex}(v)=\sum_{\text{in}}l-\sum_{\text{out}}l$; feasible iff the $S^*\to T^*$ max flow saturates $\sum_{\text{ex}>0}\text{ex}$; Hoffman: circulation exists iff $\sum_{\text{into }X}l\le\sum_{\text{out of }X}c$ for all $X$ | | [12/02](../12-Flows-and-Matching/02-min-cut-and-flow-modeling.md) |
| reduced cost $w_\pi(u,v)=w+\pi(u)-\pi(v)$ ($w_\pi(\text{cycle})=w(\text{cycle})$); $\pi'=\pi+d_\pi$ keeps $w_\pi\ge0$; min cost iff no negative residual cycle | min-cost flow | [12/04](../12-Flows-and-Matching/04-min-cost-flow.md) |
| successive path costs are non-decreasing, so $\text{cost}(F)$ is convex; convex edge cost $g$ → unit edges of cost $g(k)-g(k-1)$ ($k^2$: $2k-1$) | | [12/04](../12-Flows-and-Matching/04-min-cost-flow.md) |
| assignment LP: dual $\max\sum u_i+\sum v_j$, $u_i+v_j\le c_{ij}$; complementary slackness $x_{ij}=1\Rightarrow c_{ij}=u_i+v_j$ | Hungarian, $O(n^2m)$ | [12/05](../12-Flows-and-Matching/05-hungarian-algorithm.md) |

### 10.5 Matching theorems ($\nu$ matching, $\tau$ vertex cover, $\alpha$ independent set, $\rho$ edge cover)

| Theorem | Statement | Src |
|---|---|---|
| Berge | $M$ is maximum $\iff$ no augmenting path | [12/03](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md) |
| König (bipartite) | $\nu=\tau$; so $\alpha=n-\nu$ and $\rho=n-\nu$ (no isolated vertices) | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| Gallai (any graph) | $\alpha+\tau=n$; $\nu+\rho=n$ (no isolated vertices) | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| Hall | $L$-saturating matching $\iff\lvert N(X)\rvert\ge\lvert X\rvert$ for all $X\subseteq L$; deficiency $\nu=\lvert L\rvert-\max_X(\lvert X\rvert-\lvert N(X)\rvert)$ | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| regular bipartite | $k$-regular ⇒ perfect matching; edges split into $k$ perfect matchings; 🧊 $\chi'=\Delta$ for bipartite graphs | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| Dilworth / Mirsky | min chain cover = max antichain $=n-\nu(G_<)$; longest chain = min antichain partition | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| DAG path cover | vertex-disjoint: $n-\nu$ of the split graph; paths may share vertices: same on the transitive closure | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |
| Hopcroft–Karp gap | shortest augmenting path with $\ell$ vertices ⇒ $\lvert M^*\rvert-\lvert M\rvert\le V/\ell$ | [12/03](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md) |
| 🔴 Tutte–Berge | $\nu=\min_U\frac12\big(n+\lvert U\rvert-\text{odd}(G-U)\big)$ | [12/06](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md) |

---

## 11. Trees

| Formula | Meaning | Src |
|---|---|---|
| $n-1$ edges, $\sum\deg=2n-2$; leaves $=2+\sum_v\max(0,\deg v-2)$ | | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| $\sum_v\text{sz}(v)=\sum_v(\text{dep}(v)+1)$; $\sum_{u<v}d(u,v)=\sum_{e=(p,c)}w_e\,\text{sz}(c)(n-\text{sz}(c))$ | | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| $\mathrm{ecc}(s)=\max(d(s,a),d(s,b))$ for a diameter $(a,b)$ ($w\ge0$); $D=\max_t(h_1(t)+h_2(t))$ (any weights) | two BFS / DP | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| radius $\lceil D/2\rceil$; one centre if $D$ even, two adjacent if odd | unweighted | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| centroid: $\max(n-\text{sz}(v),\max_c\text{sz}(c))\le\lfloor n/2\rfloor$; at most 2 (adjacent); minimises $\sum_ud(v,u)$ | | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| subtree $=[\text{tin}(v),\text{tin}(v)+\text{sz}(v))$; $u$ ancestor of $v\iff\text{tin}(u)\le\text{tin}(v)<\text{tin}(u)+\text{sz}(u)$ | Euler tour | [10/01](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) |
| $d(u,v)=D(u)+D(v)-2D(\ell)$; path sum $S(u)+S(v)-2S(\ell)+a_\ell$ ($\ell=\operatorname{lca}$) | root-path inclusion–exclusion | [10/02](../10-Trees/02-lca-and-binary-lifting.md) |
| path add on vertices: $c_u\mathrel{+}=x$, $c_v\mathrel{+}=x$, $c_\ell\mathrel{-}=x$, $c_{p(\ell)}\mathrel{-}=x$; on edges: $c_\ell\mathrel{-}=2x$; then subtree sums | difference array on a tree | [10/02](../10-Trees/02-lca-and-binary-lifting.md) |
| $x$ on path $u$–$v$ $\iff d(u,x)+d(x,v)=d(u,v)$; $\operatorname{lca}(S)=\operatorname{lca}(\arg\min\text{tin},\arg\max\text{tin})$ | | [10/02](../10-Trees/02-lca-and-binary-lifting.md) |
| binary lifting $L=\lfloor\log_2n\rfloor+1$ levels; Euler tour of length $2n-1$ + RMQ gives $O(1)$ LCA | | [10/02](../10-Trees/02-lca-and-binary-lifting.md) |
| light edge $(p,c)$: $\text{sz}(p)\ge2\,\text{sz}(c)+1$; $\le\lfloor\log_2n\rfloor$ light edges on a root path; a path splits into $\le2\lfloor\log_2n\rfloor+1$ chain pieces | HLD path query $O(\log^2n)$ | [10/04](../10-Trees/04-heavy-light-decomposition.md) |
| centroid tree depth $\le\lfloor\log_2n\rfloor+1$; $T(m)=O(m)+\sum T(m_i)$, $m_i\le m/2$ ⇒ $O(n\log n)$; $d(u,v)=d(u,w)+d(w,v)$ for $w=\operatorname{lca}_C(u,v)$ | | [10/05](../10-Trees/05-centroid-decomposition.md) |
| virtual tree $V'=K\cup\lbrace\operatorname{lca}(x_t,x_{t+1})\rbrace$ ($\text{tin}$-sorted), $\lvert V'\rvert\le2k-1$; Steiner weight $\frac12\sum_td(x_t,x_{t+1\bmod k})$ | | [10/06](../10-Trees/06-virtual-trees.md) |

---

## 12. Strings

| Formula | Meaning | Src |
|---|---|---|
| $h_{i+1}=h_iB+\text{val}(s_i)$, $H(l,r)=h_r-h_lB^{r-l}$; $H(st)=H(s)B^{\lvert t\rvert}+H(t)$ | polynomial hash (values $\ne0$, random $B$) | [11/01](../11-Strings/01-string-hashing.md) |
| one comparison collides w.p. $\le\frac{L-1}p$; $Q$ comparisons $\le\frac{Q(L-1)}p$; $m$ stored hashes: $\approx\frac{m^2}{2p}$, 50% at $m\approx1.18\sqrt p$ ($3.7\cdot10^4$ for $10^9+7$) | use $2^{61}-1$ or two moduli | [11/01](../11-Strings/01-string-hashing.md) |
| $\pi[i]\le\pi[i-1]+1$; borders of $s[0..i]$: $\pi[i],\pi[\pi[i]-1],\dots$ | prefix function, $O(n)$ | [11/02](../11-Strings/02-prefix-function-kmp.md) |
| $q$ is a period $\iff$ $s$ has a border of length $n-q$; smallest period $n-\pi[n-1]$; $s=u^k$ ($k\ge2$) $\iff\pi[n-1]>0$ and $(n-\pi[n-1])\mid n$ | | [11/02](../11-Strings/02-prefix-function-kmp.md) |
| Fine–Wilf: periods $p,q$ with $p+q-\gcd(p,q)\le n$ ⇒ $\gcd(p,q)$ is a period (tight: "aba") | periodicity lemma | [11/02](../11-Strings/02-prefix-function-kmp.md) |
| $q$ is a period $\iff q+z[q]=n$; a border of length $b$ exists $\iff z[n-b]=b$; matching: $z_{p\#t}[\lvert p\rvert+1+j]=\lvert p\rvert$ | Z-function | [11/03](../11-Strings/03-z-function.md) |
| palindromic substrings $=\sum d_1+\sum d_2$; longest $\max(2d_1-1,2d_2)$; distinct palindromes $\le n$ | Manacher; only the longest palindromic suffix can be new | [11/04](../11-Strings/04-manacher-and-palindromes.md) |
| trie $\le1+\sum\lvert s_i\rvert$ nodes; binary trie $\le1+nB$ | | [11/05](../11-Strings/05-trie-and-binary-trie.md) |
| Aho–Corasick $\le m+1$ states; patterns ending at one position $<\sqrt{2m}$, so $\text{occ}\le n\sqrt{2m}$ | distinct lengths sum to $\le m$ | [11/06](../11-Strings/06-aho-corasick.md) |
| Kasai: $\text{lcp}[\text{rank}[i+1]]\ge\text{lcp}[\text{rank}[i]]-1$; $\mathrm{LCP}(\mathrm{SA}[a],\mathrm{SA}[b])=\min_{a<t\le b}\text{lcp}[t]$ | $O(n)$; RMQ | [11/07](../11-Strings/07-suffix-array-and-lcp.md) |
| distinct substrings $\frac{n(n+1)}2-\sum\text{lcp}$; of length $L$: $\#\lbrace n-\mathrm{SA}[i]\ge L\rbrace-\#\lbrace\text{lcp}[i]\ge L\rbrace$; longest repeat $\max\text{lcp}$ | | [11/07](../11-Strings/07-suffix-array-and-lcp.md) |
| $\sum_{i<j}\mathrm{LCP}(i,j)$ = sum of subarray minima of lcp; $\sum_p\binom{\text{occ}(p)+1}2=\frac{n(n+1)}2+\sum_{i<j}\mathrm{LCP}$ | | [11/07](../11-Strings/07-suffix-array-and-lcp.md) |
| SAM state $v$ holds $\text{len}(v)-\text{len}(\text{link}(v))$ strings; distinct substrings $\sum_{v\ne0}(\text{len}-\text{len}(\text{link}))$; $\text{cnt}$ summed up the link tree | | [11/08](../11-Strings/08-suffix-automaton.md) |
| SAM $\le2n-1$ states ($n\ge2$), $\le3n-4$ transitions ($n\ge3$); extremes `abb…b` and `abb…bc` | memory $\approx2n\sigma$ ints | [11/08](../11-Strings/08-suffix-automaton.md) |
| eertree $\le n+2$ nodes; palindromes ending at $i$ $=\text{dep}(\text{last}_i)$; series links give $O(\log n)$ groups | | [11/09](../11-Strings/09-palindromic-tree-eertree.md) |

---

## 13. Game theory (normal play unless stated)

| Result | Statement | Src |
|---|---|---|
| labelling | $\text{win}(v)\iff\exists$ move to a losing position; $O(V+E)$ | [13/01](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md) |
| Bash (take $1..k$) | P $\iff n\equiv0\pmod{k+1}$; misère: $n\equiv1$ | [13/01](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md) |
| subtraction set $S$, $s=\max S$ | win/lose sequence eventually periodic, period $\le2^s$ | [13/01](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md) |
| Nim | P $\iff\bigoplus a_i=0$; from $s\ne0$ move $a_i\to a_i\oplus s$ on a pile with the top bit of $s$ | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| Sprague–Grundy | $g(v)=\operatorname{mex}\lbrace g(u)\rbrace$, P $\iff g=0$; $g(G+H)=g(G)\oplus g(H)$; $g\le\text{outdeg}$, $g\le\sqrt{2m}$ on a DAG | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| subtraction games | take $1..k$: $g=n\bmod(k+1)$; take $L..R$: $g=\lfloor(n\bmod(L+R))/L\rfloor$; take $1..\lfloor n/2\rfloor$: $g(2m)=m$, $g(2m+1)=g(m)$ | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| never remove the same amount twice from a pile | $g(s)=\max\lbrace k:k(k+1)/2\le s\rbrace$ | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| Lasker's Nim (take, or split a pile in two) | $g=n$ for $n\equiv1,2$; $n+1$ for $n\equiv3$; $n-1$ for $n\equiv0\pmod4$ | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| Kayles | Grundy values periodic with period 12 from $n=71$ | [13/02](../13-Game-Theory/02-nim-and-sprague-grundy.md) |
| misère Nim | all piles $\le1$: P iff the number of ones is odd; otherwise P iff XOR $=0$ | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| staircase Nim (step 0 is the floor) | P $\iff$ XOR of odd-numbered steps $=0$ | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| Moore's Nim$_k$ (up to $k$ piles per move) | P $\iff$ every bit column count $\equiv0\pmod{k+1}$ | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| Wythoff | P $=(\lfloor k\varphi\rfloor,\lfloor k\varphi^2\rfloor)$, $b_k=a_k+k$; exactly $\lfloor k\varphi\rfloor=\lfloor(k+\lfloor\sqrt{5k^2}\rfloor)/2\rfloor$ | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| Euclid game ($a\ge b>0$, subtract a multiple of the smaller) | P $\iff b<a<\varphi b$ | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| Green Hackenbush | stalk $n$; tree $g(v)=\bigoplus_c(g(c)+1)$; cycles fuse to loops (length mod 2) | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| 🔴 SJ theorem (anti-SG) | first player wins iff (XOR $\ne0$ and some $g>1$) or (XOR $=0$ and all $g\le1$) | [13/03](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) |
| small results | divisor game ($n\to n-d$): P iff $n$ odd; Chomp: first wins unless $1\times1$; symmetric position + mirrored replies ⇒ mover loses | [13/01](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md) |
| negamax | $V(s)=\max_m(\text{gain}(m)-V(s_m))$; first player's total $=\frac{T+V(s_0)}2$; deque game $D[l][r]=\max(a_l-D[l+1][r],a_r-D[l][r-1])$ | [13/04](../13-Game-Theory/04-minimax-and-game-dp.md) |

$\varphi=\frac{1+\sqrt5}2\approx1.6180339887$, $\varphi^2=\varphi+1$, $\frac1\varphi+\frac1{\varphi^2}=1$.

---

## 14. Geometry

| Formula | Meaning | Src |
|---|---|---|
| $a\cdot b=a_xb_x+a_yb_y=\lvert a\rvert\lvert b\rvert\cos\theta$; $a\times b=a_xb_y-a_yb_x=\lvert a\rvert\lvert b\rvert\sin\theta$; $(a\cdot b)^2+(a\times b)^2=\lvert a\rvert^2\lvert b\rvert^2$ | dot, cross, Lagrange identity | [14/01](../14-Geometry/01-vectors-dot-cross-and-precision.md) |
| $\operatorname{orient}(A,B,C)=\operatorname{sgn}((B-A)\times(C-A))$ ($+$ = left turn); triangle area $\frac12\lvert(B-A)\times(C-A)\rvert$ | exact in 64 bits for $\lvert\text{coord}\rvert\le10^9$ | [14/01](../14-Geometry/01-vectors-dot-cross-and-precision.md) |
| angle $a\to b$: $\operatorname{atan2}(a\times b,a\cdot b)$; rotation $(x\cos\theta-y\sin\theta,\ x\sin\theta+y\cos\theta)$; $\operatorname{perp}(x,y)=(-y,x)$ | never `acos` | [14/01](../14-Geometry/01-vectors-dot-cross-and-precision.md) |
| projection on $AB$: $A+\frac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2}(B-A)$; reflection $2\,\text{proj}-P$; distance to line $\frac{\lvert(B-A)\times(P-A)\rvert}{\lvert B-A\rvert}$ | | [14/01](../14-Geometry/01-vectors-dot-cross-and-precision.md) |
| lines $A+td$, $C+se$: $t=\frac{(C-A)\times e}{d\times e}$; parallel iff $d\times e=0$ | intersection | [14/02](../14-Geometry/02-lines-segments-and-intersections.md) |
| $P\in[AB]\iff(B-A)\times(P-A)=0\wedge(A-P)\cdot(B-P)\le0$; closest point $t^*=\operatorname{clamp}\big(\frac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2},0,1\big)$ | | [14/02](../14-Geometry/02-lines-segments-and-intersections.md) |
| lattice points on segment $AB$: $\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)+1$ | | [14/02](../14-Geometry/02-lines-segments-and-intersections.md) |
| shoelace $2A=\sum_i(x_iy_{i+1}-x_{i+1}y_i)=\sum_i(x_i-x_{i+1})(y_i+y_{i+1})$ (CCW positive) | | [14/03](../14-Geometry/03-polygons-area-pick-point-in-polygon.md) |
| Pick: $A=I+\frac B2-1$, $B=\sum\gcd(\lvert\Delta x_i\rvert,\lvert\Delta y_i\rvert)$, $I=\frac{2A-B+2}2$; with $h$ holes $A=I+\frac B2-1+h$ | simple lattice polygon | [14/03](../14-Geometry/03-polygons-area-pick-point-in-polygon.md) |
| centroid $\frac1{6A}\sum(p_i+p_{i+1})(p_i\times p_{i+1})$; interior angles sum $(n-2)\pi$; regular $n$-gon area $\frac n2R^2\sin\frac{2\pi}n$, side $2R\sin\frac\pi n$ | | [14/03](../14-Geometry/03-polygons-area-pick-point-in-polygon.md) |
| hull needs $\Omega(n\log n)$; lattice hull in a $C\times C$ box has $O(C^{2/3})$ vertices; Minkowski sum $\le n+m$ edges, perimeters add, $h_{P\oplus Q}=h_P+h_Q$ | | [14/04](../14-Geometry/04-convex-hull-and-rotating-calipers.md) |
| $\lvert a\rvert+\lvert b\rvert=\max(\lvert a+b\rvert,\lvert a-b\rvert)$: $d_1(p,q)=d_\infty(Rp,Rq)$, $R(x,y)=(x+y,x-y)$; $d_\infty=\frac12d_1\circ R$ | Manhattan ↔ Chebyshev | [14/05](../14-Geometry/05-sweep-closest-pair-and-half-plane.md) |
| farthest Manhattan pair $\max(u_{\max}-u_{\min},v_{\max}-v_{\min})$; $\sum_{i<j}\lvert a_i-a_j\rvert=\sum_ka_{(k)}(2k-n-1)$ (1-based, sorted) | | [14/05](../14-Geometry/05-sweep-closest-pair-and-half-plane.md) |
| closest pair: a $2\delta\times\delta$ box holds $\le8$ points; randomised grid: point $i$ shrinks $d$ w.p. $\le\frac2i$ | $O(n\log n)$ / expected $O(n)$ | [14/05](../14-Geometry/05-sweep-closest-pair-and-half-plane.md) |
| circle ∩ circle: $a=\frac{d^2+r_1^2-r_2^2}{2d}$, $h=\sqrt{r_1^2-a^2}$; power $\lvert p-c\rvert^2-r^2$; tangent length $\sqrt{\lvert p-c\rvert^2-r^2}$ | | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| $R=\frac{abc}{4K}$, $r_{\text{in}}=\frac{2K}{a+b+c}$; $16K^2=((r_1+r_2)^2-d^2)(d^2-(r_1-r_2)^2)$ | radii; Heron in exact pairs | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| circumcentre (relative to $A$, $a=B-A$, $b=C-A$): $\frac{(b_y\lvert a\rvert^2-a_y\lvert b\rvert^2,\ a_x\lvert b\rvert^2-b_x\lvert a\rvert^2)}{2(a\times b)}$ | | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| circular segment $\frac{r^2}2(\theta-\sin\theta)$; inscribed angle = half the central angle; Welzl: point $i$ on the MEC boundary w.p. $\le\frac3i$ | | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| regions cut by $n$ lines $1+n+\binom n2$; by chords between $n$ circle points $1+\binom n2+\binom n4$ | general position | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| 3D: $[a,b,c]=a\cdot(b\times c)$, tetrahedron volume $\frac{\lvert[a,b,c]\rvert}6$ | | [14/06](../14-Geometry/06-circles-and-advanced-geometry.md) |
| magnitudes for $\lvert\text{coord}\rvert\le C$: cross of differences $\le4C^2$, squared distance $\le8C^2$, degree-4 predicates $\sim C^4$; `double` exact below $2^{53}$ | choose `long long` / `__int128` | [14/01](../14-Geometry/01-vectors-dot-cross-and-precision.md) |

---

## 15. Randomised algorithms and hashing

| Formula | Meaning | Src |
|---|---|---|
| one-sided error $p$ → $p^k$ after $k$ runs; $(1-f)^k\le e^{-fk}$, so $k=\lceil\ln(1/\varepsilon)/f\rceil$ samples | amplification | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| union bound: $q$ events of probability $\le p$ fail together w.p. $\le qp$ | | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| birthday: $k$ values in $M$ slots collide w.p. $\approx1-e^{-k^2/2M}$; expected colliding pairs $\binom k2/M$ | | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| Schwartz–Zippel: $\Pr[P(x)=0]\le\deg P/\lvert S\rvert$ for non-zero $P$; Freivalds: $\Pr[ABx=Cx\mid AB\ne C]\le\frac1{\lvert S\rvert}$ | polynomial identity testing | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| XOR hash of a multiset's odd-count elements: collision $2^{-64}$; sum hash mod $2^{64}$: $\le2^{\nu_2(\Delta_u)-64}$ | set / parity hashing | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| colour coding: a fixed $k$-set is colourful w.p. $\frac{k!}{k^k}\ge e^{-k}$ | | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| a value with frequency $>1/k$ is missed by $ck$ random samples w.p. $<e^{-c}$ | majority-style sampling | [16/04](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) |
| treap: $P(x_j\text{ ancestor of }x_i)=\frac1{\lvert i-j\rvert+1}$, expected depth $<2\ln n$; random quicksort $\approx2n\ln n$ comparisons | | [08/09](../08-Data-Structures/09-treaps-and-implicit-treaps.md) |
| hash table with load $\alpha$: $1+\alpha$ expected probes; never key `unordered_map` / `HashMap` on raw adversarial input | splitmix64 with a random seed | [01/02](../01-Foundations/02-cpp-stl-and-java-collections.md) |

---

## 16. First terms (sanity checks for brute forces)

| Sequence | $n=0,1,2,\dots$ |
|---|---|
| $n!$ | 1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800 |
| Fibonacci $F_n$ | 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 |
| Catalan $C_n$ | 1, 1, 2, 5, 14, 42, 132, 429, 1430, 4862, 16796 |
| Bell $B_n$ | 1, 1, 2, 5, 15, 52, 203, 877, 4140, 21147, 115975 |
| derangements $D_n$ | 1, 0, 1, 2, 9, 44, 265, 1854, 14833, 133496 |
| partitions $p(n)$ | 1, 1, 2, 3, 5, 7, 11, 15, 22, 30, 42 |
| labelled trees $n^{n-2}$ ($n\ge1$) | 1, 1, 3, 16, 125, 1296, 16807 |
| binary necklaces ($n\ge1$) | 2, 3, 4, 6, 8, 14, 20, 36, 60, 108 |
| binary Lyndon words ($n\ge1$) | 2, 1, 2, 3, 6, 9, 18, 30, 56, 99 |
| $3\times2n$ domino tilings | 1, 3, 11, 41, 153, 571 |
| $\pi(10^k)$, $k\ge1$ | 4, 25, 168, 1229, 9592, 78498, 664579, 5761455, 50847534 |

---

## 17. Verification notes

Every row above comes from the linked topic file. While assembling this sheet, the following were re-checked by brute force or exact
arithmetic on small cases (scratch scripts, not part of the kit):

- **Sums and bits:** $\sum i^k$ for $k\le4$, geometric sums, $H_n$ and $\sum\lfloor n/d\rfloor$ asymptotics, Stirling, the interval-loop count, XOR of $0..n$, the sum/XOR/AND/OR identities, per-bit pair sums, the bit-count formula, $3^n$ submask steps, Gray code and its inverse, Gosper's hack, max XOR in $[l,r]$, the adjacent-minimum-XOR lemma.
- **Number theory:** Fibonacci gcd and addition, $\gcd(a^m-1,a^n-1)$, Lamé, Bézout coefficient bounds, Frobenius, linear inverses, $d,\sigma,\sigma_2$, product of divisors, every $\varphi$/$\mu$ identity in §4.5, coprime-pair and gcd-sum formulas, the $\operatorname{lcm}$ sum, Fermat, Euler, generalised Euler (all $a$, $m<150$), Wilson, $2^{\omega(m)}$ square roots of 1, primitive-root existence and count, order of $a^k$, Euler's criterion, $(\frac{-1}p)$, $(\frac2p)$, reciprocity, $x^k\equiv a$ solvability, Carmichael numbers, Miller–Rabin $\lbrace2,7,61\rbrace$ below $10^6$, primality and primitive roots of every listed prime, floor blocks and nested floors, `floor_sum`, Legendre, Kummer, both LTE forms, Du's sieve and Mertens recurrences, the hyperbola identity, residue counting, Pisano $\le6m$ for $m<1500$, the max-$d(n)$ table (exhaustive search over exponent vectors), $\pi(10^3..10^8)$ by sieve, primorial counts, 64-bit landmarks, lazy-reduction counts.
- **Combinatorics and probability:** every binomial identity in §5.1 and Lucas; stars and bars variants; derangements; surjections; Stirling, Bell (and triangle), Lah; Catalan forms, prefix-balanced, height-$h$ walks, ballot, Fuss–Catalan, Narayana; partitions and the pentagonal recurrence; twelvefold-way cells; Fibonacci identities and Zeckendorf; necklaces (both forms), bracelets, Lyndon words, fixed-content necklaces, cycle colourings, grid ($C_4$ and $D_4$) and cube counts; coupon collector (equal and unequal), random-permutation statistics, dice maximum, gambler's ruin, uniform order statistics, birthday; all contribution formulas in §5.12.
- **DP, linear algebra, graphs, strings, games, geometry:** $2\times n$, $3\times n$ and $8\times8$ domino tilings against Kasteleyn's product, Delannoy, binary splitting, Erdős–Szekeres tightness; Kirchhoff on random multigraphs with self-loops, $K_n$, $K_{a,b}$, $C_n$; Prüfer degree counts and the forest formula; BEST on random Eulerian digraphs and de Bruijn counts; LGV on grids; König and Dilworth; Eulerian-subgraph count; GF(2) solution counts and XOR-basis counts; block-matrix geometric series; walk counts; Bell EGF; Lagrange denominators and $\binom{p-1}k$; smallest period, Z-period test, Fine–Wilf (and its tightness), distinct substrings via LCP, distinct palindromes $\le n$, SAM size bounds and extremal strings; Lasker's Nim, half-removal, $L..R$ subtraction, Kayles period, misère Nim, Moore's Nim$_2$, staircase Nim, Wythoff (and the exact floor formula to $2\cdot10^4$), Euclid game, Bash; Pick on random lattice polygons, lattice points on segments, Manhattan ↔ Chebyshev, circle intersection, paired Heron, circumcentre, region counts.

Not re-checked here (standard results, as derived in the linked files): the Master theorem, prime-gap records beyond $10^8$, $\pi(10^9)$,
the 12-base Miller–Rabin guarantee for all of $[0,2^{64})$, Mantel, the Moore bound, Menger, Hall, Tutte–Berge, Robbins, Eswaran–Tarjan,
the QI/Knuth/D&C theorems, Aliens duality, the SJ theorem, the Grundy formula for "never remove the same amount twice", and the
complexity bounds of Dinic, Hopcroft–Karp and Mo's algorithm.
