# Interactive problems

> **Band:** 🔵–🟠 1300–2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [ternary search](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md), [fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you never get "Idleness limit exceeded" (you flush every query in C++ and Java), you can derive the minimum number of queries from an information-theoretic bound and design a strategy that meets the budget against an adaptive judge, and you test every interactive solution against your own local judge before submitting.

## 1. First principles — why this works

In an interactive problem there is no input file. Your program talks to a **judge program (interactor)** through two
pipes: what you print goes to the interactor's input, and what it prints arrives on your input. The hidden object (a
number, an array, a graph) lives inside the interactor; you learn about it only through queries, and you are limited
by a **query budget**.

### The protocol, mechanically

1. Read the initial data (often $n$, sometimes $t$ test cases).
2. Print a query in the exact format (`? 5`, `? 1 7`), **flush**, then read the response.
3. Repeat; finally print the answer (`! 42`), flush, and move to the next test case or exit.

**Flushing** is the single most important detail. Output is buffered; if you do not flush, the query sits in your
buffer, the interactor waits for it, you wait for the answer, and the verdict is *Idleness limit exceeded*.
In C++, `cout << ... << endl` flushes (that is the one place `endl` is right), as does `cout << flush` or
`fflush(stdout)` after `printf`. In Java, call `out.flush()` after every query on your `PrintWriter`.
(`ios::sync_with_stdio(false); cin.tie(nullptr);` is still fine — `cin.tie(nullptr)` just means *you* must flush.)

**Reading −1.** Codeforces interactors answer −1 when a query is invalid or the budget is exceeded. Exit immediately
on −1: continuing makes you read garbage and the verdict becomes a confusing "Wrong answer" or "Idleness" instead of the
real cause.

### Information theory: how many queries do you need?

If the hidden object is one of $N$ possibilities and each answer has at most $k$ distinct values, then $q$ queries can
distinguish at most $k^q$ cases. Therefore every correct strategy needs
$$q \ge \lceil \log_k N \rceil$$
in the worst case. Against an **adaptive** interactor this bound is exact as a lower bound: the judge can always answer
so that the larger part of the remaining consistent possibilities survives (the *adversary argument*). Yes/no queries
give $k = 2$: finding one of $n$ positions needs $\lceil \log_2 n \rceil$ queries, and binary search achieves it.

Read the budget as a hint about the intended strategy:

| Budget | Typical meaning |
|---|---|
| $\lceil \log_2 n \rceil$ (e.g. 17 for $10^5$, 20 for $10^6$, 30 for $10^9$) | every query must halve the candidates — exact binary search |
| $\approx 2\log_2 n$ | two binary searches, or two probes per halving step (local minimum) |
| $\log_2 n + c$ | a few setup queries, then a binary search (Example 4) |
| $n - 1$, $n$, $n + c$ | one query per element, maybe plus a binary search |
| $\lceil 3n/2 \rceil$ | pairwise tournament: min and max together |
| $2$ or $3$ queries of size 100 | design queries that each reveal a block of bits (Example 5) |

### Strategies that recur

- **Binary search on a monotone predicate of the hidden data** (prefix sums, "is the answer $\ge m$?", "does the
  segment $[l, r]$ contain it?"). Keep an explicit invariant (`lo` always false, `hi` always true, or "the target is in
  $[lo, hi]$").
- **Local extremum with point queries:** keep an interval whose border values guarantee a local minimum inside; probe two
  adjacent values in the middle to decide which half keeps the guarantee (Example 3).
- **Bits by design:** choose queries whose answers isolate different bit ranges of the hidden value (Example 5).
- **Divisibility / membership tests:** ask a small set of carefully chosen questions that separate the classes
  (Example 2).
- **Adaptive judges:** your strategy must work for *every* answer sequence consistent with some hidden data. Randomised
  strategies help only against non-adaptive judges; when the statement says the interactor is adaptive, think worst case.

### Testing: a local judge is not optional

Interactive bugs (off-by-one in the budget, a missing flush, a wrong query format) are invisible in the samples. Two
complementary tools:

1. **In-process simulation.** Write the strategy against an abstract `ask()` and implement `ask()` twice: once with real
   I/O, once with a local judge that holds the hidden data and counts queries (§3.2). The simulated version reads the
   hidden data from stdin, so you can stress-test it against thousands of random hidden objects. All worked examples
   below are tested this way.
2. **A real local interactor** connected to your unmodified solution through pipes (§3.3). This catches protocol bugs
   (flushing, formats, reading −1) that the in-process version cannot.

## 2. Formulas, definitions and identities

| Quantity | Value | Why |
|---|---|---|
| queries to find one of $n$ items with yes/no answers | $\lceil \log_2 n \rceil$ | $2^q \ge n$; binary search achieves it |
| with $k$-ary answers | $\lceil \log_k n \rceil$ | $k^q \ge n$ |
| $\lceil \log_2 n \rceil$ for $n = 10^3, 10^5, 2\cdot 10^5, 10^6, 10^9, 10^{18}$ | $10, 17, 18, 20, 30, 60$ | $2^{10} = 1024$, $2^{17} = 131072$, $2^{18} = 262144$, $2^{20} \approx 1.05 \cdot 10^6$, $2^{30} \approx 1.07 \cdot 10^9$, $2^{60} \approx 1.15 \cdot 10^{18}$ |
| comparisons to find the maximum of $n$ | $n - 1$ | every non-maximum must lose once |
| comparisons to find min and max | $\lceil 3n/2 \rceil - 2$ | compare in pairs, then the winners for max and the losers for min |
| comparisons for the second largest | $n + \lceil \log_2 n \rceil - 2$ | tournament; the runner-up lost to the champion |
| local minimum of a length-$n$ array with point queries | $\le 2 \lceil \log_2 n \rceil$ | two probes per halving step |
| bits revealed by a query whose answer is a $b$-bit number | at most $b$ | the answer has $2^b$ values |

**Binary search invariant (first true).** For a predicate $P$ false on $[1, x)$ and true on $[x, n]$, keep $lo$ with
$P(lo)$ false (or $lo = 0$) and $hi$ with $P(hi)$ true (or $hi = n$). Query $mid = \lfloor (lo + hi)/2 \rfloor$ and move the
endpoint with the same truth value. Each query halves $hi - lo$, so $\lceil \log_2 n \rceil$ queries reach $hi - lo = 1$ and
$x = hi$. The same invariant in detail: [binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md).

**Local minimum invariant.** With $a_0 = a_{n+1} = +\infty$, keep $[lo, hi]$ with $a_{lo-1} > a_{lo}$ and $a_{hi} < a_{hi+1}$.
Then the minimum of $a_{lo..hi}$ is a local minimum of the whole array. For $mid$ in $[lo, hi)$: if $a_{mid} < a_{mid+1}$ set
$hi = mid$, else $lo = mid + 1$; both keep the invariant.

## 3. Implementation (C++ and Java)

### 3.1 Query helpers with flushing and −1 handling

```cpp
// One integer query; the judge answers one integer (or -1 on error).
long long ask(long long i) {
    cout << "? " << i << endl;                 // endl = '\n' + flush: required in interactive problems
    long long r;
    if (!(cin >> r) || r == -1) exit(0);       // judge reported an error or closed the pipe: stop at once
    return r;
}
void answer(long long x) { cout << "! " << x << endl; }
```

```java
static final BufferedReader BR = new BufferedReader(new InputStreamReader(System.in));
static final PrintWriter OUT = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
static StringTokenizer tok;
static String token() throws IOException {
    while (tok == null || !tok.hasMoreTokens()) {
        String line = BR.readLine();
        if (line == null) System.exit(0);       // judge closed the pipe
        tok = new StringTokenizer(line);
    }
    return tok.nextToken();
}
static long ask(long i) throws IOException {
    OUT.println("? " + i);
    OUT.flush();                                // forgetting this is "Idleness limit exceeded"
    long r = Long.parseLong(token());
    if (r == -1) System.exit(0);
    return r;
}
static void answer(long x) { OUT.println("! " + x); OUT.flush(); }
```

`BufferedReader.readLine` returns as soon as one line is available, which is what an interactive program needs. A
`DataInputStream` byte reader also works (a read returns whatever bytes are available), but line-based reading makes
the protocol easier to follow.

### 3.2 Strategy/judge separation (one strategy, two judges)

```cpp
struct Judge {                                     // the strategy only sees this interface
    virtual long long ask(long long i) = 0;
    virtual ~Judge() = default;
};
struct RealJudge : Judge {                         // talks to the interactor
    long long ask(long long i) override {
        cout << "? " << i << endl;
        long long r; if (!(cin >> r) || r == -1) exit(0);
        return r;
    }
};
struct LocalJudge : Judge {                        // holds the hidden array, counts and validates queries
    vector<long long> a; int queries = 0, budget;
    LocalJudge(vector<long long> v, int b) : a(std::move(v)), budget(b) {}
    long long ask(long long i) override {
        if (++queries > budget || i < 1 || i > (long long)a.size()) { cerr << "budget/index violation\n"; exit(1); }
        return a[i - 1];
    }
};
// Example strategy: first index whose value is >= target in a hidden non-decreasing array (n+1 if none).
long long firstAtLeast(Judge& J, long long n, long long target) {
    long long lo = 0, hi = n + 1;                  // invariant: a[lo] < target (or lo = 0), a[hi] >= target (or hi = n+1)
    while (hi - lo > 1) {
        long long mid = lo + (hi - lo) / 2;
        (J.ask(mid) >= target ? hi : lo) = mid;
    }
    return hi;
}
```

```java
interface Judge { long ask(long i); }
static class LocalJudge implements Judge {
    final long[] a; final int budget; int queries = 0;
    LocalJudge(long[] a, int budget) { this.a = a; this.budget = budget; }
    public long ask(long i) {
        if (++queries > budget || i < 1 || i > a.length) throw new IllegalStateException("budget/index violation");
        return a[(int) i - 1];
    }
}
static long firstAtLeast(Judge j, long n, long target) {
    long lo = 0, hi = n + 1;
    while (hi - lo > 1) {
        long mid = lo + (hi - lo) / 2;
        if (j.ask(mid) >= target) hi = mid; else lo = mid;
    }
    return hi;
}
```

### 3.3 A real local interactor and a pipe runner

A local interactor is a normal program: it reads the hidden data from a file, then reads queries from stdin and writes
answers to stdout (flushing), and exits with code 0 only if the final answer is correct within the budget. This one is
for "guess $x \in [1, n]$; a query `? y` is answered `<` if $x < y$ and `>=` otherwise".

```cpp
#include <bits/stdc++.h>
using namespace std;
// usage: interactor hidden.txt   (hidden.txt contains: n x budget)
int main(int argc, char** argv) {
    if (argc < 2) { cerr << "usage: interactor hidden.txt\n"; return 2; }
    ifstream hidden(argv[1]);
    long long n, x; int budget;
    hidden >> n >> x >> budget;
    cout << n << endl;
    int used = 0; string op; long long y;
    while (cin >> op >> y) {
        if (op == "?") {
            if (++used > budget || y < 1 || y > n) { cout << -1 << endl; return 1; }
            cout << (x < y ? "<" : ">=") << endl;
        } else if (op == "!") {
            cerr << "queries used: " << used << '\n';
            return y == x ? 0 : 1;
        } else return 1;                               // malformed output from the solution
    }
    return 1;                                          // solution exited without an answer
}
```

```java
import java.io.*;
import java.util.*;

public class Main {                                    // the same interactor in Java: java Main hidden.txt
    public static void main(String[] args) throws IOException {
        if (args.length < 1) { System.err.println("usage: java Main hidden.txt"); System.exit(2); }
        Scanner hidden = new Scanner(new File(args[0]));
        long n = hidden.nextLong(), x = hidden.nextLong(); int budget = hidden.nextInt();
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(System.out);
        out.println(n); out.flush();
        int used = 0; String line;
        while ((line = br.readLine()) != null) {
            StringTokenizer st = new StringTokenizer(line);
            if (!st.hasMoreTokens()) continue;
            String op = st.nextToken(); long y = Long.parseLong(st.nextToken());
            if (op.equals("?")) {
                if (++used > budget || y < 1 || y > n) { out.println(-1); out.flush(); System.exit(1); }
                out.println(x < y ? "<" : ">="); out.flush();
            } else if (op.equals("!")) {
                System.err.println("queries used: " + used);
                System.exit(y == x ? 0 : 1);
            } else System.exit(1);
        }
        System.exit(1);
    }
}
```

The runner wires the two processes together and echoes the conversation to the console (it works on Windows, where
shell tricks with named pipes do not):

```python
# run_interactive.py   usage: python run_interactive.py "<solution command>" "<interactor command>"
import os, shlex, subprocess, sys, threading

def command(s):                             # Windows: keep the command line as is (backslashes, quoted paths)
    return s if os.name == "nt" else shlex.split(s)

sol = subprocess.Popen(command(sys.argv[1]), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
try:
    judge = subprocess.Popen(command(sys.argv[2]), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
except OSError:
    sol.kill()                              # never leave the solution blocked on input forever
    raise

def pump(src, dst, tag):                    # copy one direction line by line, logging it to stderr
    for line in iter(src.readline, b""):
        sys.stderr.write(f"{tag} {line.decode().rstrip()}\n")
        try:
            dst.write(line); dst.flush()
        except (BrokenPipeError, OSError):
            break
    try:
        dst.close()
    except OSError:
        pass

threads = [threading.Thread(target=pump, args=(sol.stdout, judge.stdin, "sol  >")),
           threading.Thread(target=pump, args=(judge.stdout, sol.stdin, "judge>"))]
for t in threads: t.start()
rs, rj = sol.wait(), judge.wait()
for t in threads: t.join()
print(f"solution exit {rs}, interactor exit {rj} ({'ACCEPTED' if rj == 0 else 'REJECTED'})")
```

Run it as `python run_interactive.py "sol.exe" "interactor.exe hidden.txt"` (or with `java -cp . Main` for Java
programs, or `python interactor.py hidden.txt` for a quick Python judge). Two Windows-specific traps: (1) link local
C++ binaries with `-static` — a different `libstdc++-6.dll` earlier on `PATH` (for example the one shipped with Git) can
crash a dynamically linked program in ways that look like bugs in your code; (2) a command whose executable path
contains spaces must be quoted, otherwise the interactor never starts and the solution waits for input forever (the
runner kills the solution in that case).

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "This is an interactive problem", a query format like `? …` and an answer format `! …` | protocol checklist: flush, read −1, budget, multiple test cases |
| budget $= \lceil\log_2 n\rceil$ or close | exact binary search on a monotone predicate |
| budget $\approx 2\log_2 n$ with point queries | local extremum / two probes per step |
| "the interactor is adaptive" | worst-case strategy; adversary argument for the lower bound |
| the answer to a query is a number with many bits | design queries to extract many bits at once |
| queries return "position of the second maximum" / comparisons | tournament reasoning, binary search on the side of the maximum |
| "at most $n + 30$ queries" | linear scan of something plus a binary search |

**Commonly confused with:** ordinary binary search problems — the reasoning is the same, but in an interactive
problem every evaluation of the predicate costs a query, so caching repeated probes and counting them precisely matters.

## 5. Worked examples (graded)

Each example shows the real interactive program (compiled, not run by the harness), followed by a **local simulation**
subsection: the same strategy against an in-process judge that reads the hidden data from stdin and prints the answer
and the number of queries used. The real programs were also run against local interactors through the pipe runner.

### Example 1 — Interview  ·  ★ 1300

- **Source:** [CF 1807E · Interview](https://codeforces.com/problemset/problem/1807/E) — 1300
- **Difficulty:** 1300
- **Problem:** $t$ test cases; $n \le 2\cdot 10^5$ piles with known sizes $a_1..a_n$. Every stone weighs 1 except one stone of
  weight 2 hidden in some pile. A query names a set of piles and returns their total weight; at most 30 queries per test.
  Find the pile with the heavy stone. Query format: `? k i1 … ik`; answer `! i`.
- **Thinking from first principles:** the weight of a set of piles is its stone count, plus one if it contains the
  special pile. So "is the special pile among piles $1..m$?" is a yes/no question we can ask, and it is monotone in $m$.
  Binary search on prefixes (or on any halves): $\lceil \log_2 (2\cdot 10^5) \rceil = 18 \le 30$. Prefix sums of $a$ give the
  expected light weight of each queried range.

<details><summary>Solution</summary>

Maintain $[lo, hi]$ containing the special pile; query the piles $lo..mid$; if the weight exceeds their stone count the
pile is in $[lo, mid]$, else in $[mid+1, hi]$. $\lceil \log_2 n \rceil$ queries per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<long long> pre(n + 1, 0);
        for (int i = 1; i <= n; i++) { long long a; cin >> a; pre[i] = pre[i - 1] + a; }
        int lo = 1, hi = n;                              // invariant: the special pile is in [lo, hi]
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            cout << "? " << mid - lo + 1;
            for (int i = lo; i <= mid; i++) cout << ' ' << i;
            cout << endl;                                // flush
            long long w; cin >> w;
            if (w == -1) return 0;
            if (w > pre[mid] - pre[lo - 1]) hi = mid; else lo = mid + 1;
        }
        cout << "! " << lo << endl;
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
    static StringTokenizer tok;
    static long next() throws IOException {
        while (tok == null || !tok.hasMoreTokens()) {
            String line = br.readLine();
            if (line == null) System.exit(0);
            tok = new StringTokenizer(line);
        }
        return Long.parseLong(tok.nextToken());
    }
    public static void main(String[] args) throws IOException {
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = (int) next();
        while (t-- > 0) {
            int n = (int) next();
            long[] pre = new long[n + 1];
            for (int i = 1; i <= n; i++) pre[i] = pre[i - 1] + next();
            int lo = 1, hi = n;
            while (lo < hi) {
                int mid = (lo + hi) / 2;
                StringBuilder sb = new StringBuilder("? ").append(mid - lo + 1);
                for (int i = lo; i <= mid; i++) sb.append(' ').append(i);
                out.println(sb); out.flush();
                long w = next();
                if (w == -1) System.exit(0);
                if (w > pre[mid] - pre[lo - 1]) hi = mid; else lo = mid + 1;
            }
            out.println("! " + lo); out.flush();
        }
    }
}
```

</details>

#### Example 1 — local simulation (tested)

Input: $t$, then for each test $n$, the sizes, and the index of the special pile. Output per test: the found pile and
the number of queries.

<details><summary>Simulated judge</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<long long> pre(n + 1, 0);
        for (int i = 1; i <= n; i++) { long long a; cin >> a; pre[i] = pre[i - 1] + a; }
        int special; cin >> special;
        int queries = 0;
        auto weight = [&](int l, int r) {               // the judge: total weight of piles l..r
            ++queries;
            return pre[r] - pre[l - 1] + (l <= special && special <= r ? 1 : 0);
        };
        int lo = 1, hi = n;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (weight(lo, mid) > pre[mid] - pre[lo - 1]) hi = mid; else lo = mid + 1;
        }
        cout << lo << ' ' << queries << '\n';
    }
}
```

```java
import java.util.*;

public class Main {
    static int queries;
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);               // local simulation only; not a contest template
        int t = sc.nextInt();
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int n = sc.nextInt();
            long[] pre = new long[n + 1];
            for (int i = 1; i <= n; i++) pre[i] = pre[i - 1] + sc.nextLong();
            int special = sc.nextInt();
            queries = 0;
            int lo = 1, hi = n;
            while (lo < hi) {
                int mid = (lo + hi) / 2;
                queries++;
                long w = pre[mid] - pre[lo - 1] + (lo <= special && special <= mid ? 1 : 0);
                if (w > pre[mid] - pre[lo - 1]) hi = mid; else lo = mid + 1;
            }
            sb.append(lo).append(' ').append(queries).append('\n');
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
3
5
1 2 3 4 5
3
1
7
1
8
1 1 1 1 1 1 1 1
8
out:
3 2
1 0
8 3
-->

<!-- test
in:
3
2
3 4
2
6
2 2 2 2 2 2
1
6
2 2 2 2 2 2
6
out:
2 1
1 3
6 2
-->

</details>

### Example 2 — Bear and Prime 100  ·  ★ 1400

- **Source:** [CF 679A · Bear and Prime 100](https://codeforces.com/problemset/problem/679/A) — 1400
- **Difficulty:** 1400
- **Problem:** a hidden integer $x \in [2, 100]$. A query is an integer $y \in [2, 100]$; the answer is `yes` if $y$ divides $x$,
  else `no`. With at most 20 queries, decide whether $x$ is `prime` or `composite`.
- **Thinking from first principles:** asking every candidate divisor is 99 queries. Which divisors can a composite
  $x \le 100$ have? Its smallest prime factor $p$ satisfies $p^2 \le x \le 100$, so $p \in \{2, 3, 5, 7\}$, and $x = p \cdot q$ with
  $q \le 50$. If $q$ is a prime different from $p$, both $p$ and $q$ (a prime $\le 47$) answer `yes`; if $q = p$ or $q$ has
  factor $p$, then $p^2 \in \{4, 9, 25, 49\}$ divides $x$; if $q$ has another prime factor, that one is $\le 47$ too. So query the
  15 primes up to 47 and the 4 squares: a composite gets at least two `yes`, a prime at most one. 19 queries $\le 20$.

<details><summary>Solution</summary>

Ask the 19 numbers; stop early once two `yes` answers arrived. Print `composite` iff at least two `yes`.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    const int Q[] = {2, 3, 4, 5, 7, 9, 11, 13, 17, 19, 23, 25, 29, 31, 37, 41, 43, 47, 49};
    int yes = 0;
    for (int y : Q) {
        cout << y << endl;                 // query, flushed
        string r; cin >> r;
        if (r == "yes" && ++yes >= 2) break;
    }
    cout << (yes >= 2 ? "composite" : "prime") << endl;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(System.out);
        int[] q = {2, 3, 4, 5, 7, 9, 11, 13, 17, 19, 23, 25, 29, 31, 37, 41, 43, 47, 49};
        int yes = 0;
        for (int y : q) {
            out.println(y); out.flush();
            String r = br.readLine().trim();
            if (r.equals("yes") && ++yes >= 2) break;
        }
        out.println(yes >= 2 ? "composite" : "prime");
        out.flush();
    }
}
```

</details>

#### Example 2 — local simulation (tested)

Input: one or more hidden values $x$ (until end of input). Output per value: the verdict and the number of queries.

<details><summary>Simulated judge</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    const int Q[] = {2, 3, 4, 5, 7, 9, 11, 13, 17, 19, 23, 25, 29, 31, 37, 41, 43, 47, 49};
    int x;
    while (cin >> x) {
        int yes = 0, queries = 0;
        for (int y : Q) {
            ++queries;
            if (x % y == 0 && ++yes >= 2) break;     // the judge's answer is "x divisible by y"
        }
        cout << (yes >= 2 ? "composite" : "prime") << ' ' << queries << '\n';
    }
}
```

```java
import java.util.*;

public class Main {
    public static void main(String[] args) {
        int[] q = {2, 3, 4, 5, 7, 9, 11, 13, 17, 19, 23, 25, 29, 31, 37, 41, 43, 47, 49};
        Scanner sc = new Scanner(System.in);
        StringBuilder sb = new StringBuilder();
        while (sc.hasNextInt()) {
            int x = sc.nextInt(), yes = 0, queries = 0;
            for (int y : q) {
                queries++;
                if (x % y == 0 && ++yes >= 2) break;
            }
            sb.append(yes >= 2 ? "composite" : "prime").append(' ').append(queries).append('\n');
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
97
4
2
49
91
out:
prime 19
composite 3
prime 19
composite 19
composite 8
-->

<!-- test
in:
100
53
47
25
6
out:
composite 3
prime 19
prime 19
composite 12
composite 2
-->

</details>

### Example 3 — Searching Local Minimum  ·  ★ 1700

- **Source:** [CF 1479A · Searching Local Minimum](https://codeforces.com/problemset/problem/1479/A) — 1700
- **Difficulty:** 1700
- **Problem:** a hidden permutation $a_1..a_n$ ($n \le 10^5$). Query `? i` returns $a_i$; at most 100 queries. Output `! k` for any
  $k$ with $a_k < \min(a_{k-1}, a_{k+1})$, where $a_0 = a_{n+1} = +\infty$.
- **Thinking from first principles:** a local minimum always exists (the global minimum is one), but finding the global
  minimum needs $n$ queries. We need a *certificate* that survives halving. The pair of conditions "$a_{lo-1} > a_{lo}$ and
  $a_{hi} < a_{hi+1}$" is such a certificate: any interval with a descending left border and an ascending right border
  contains a local minimum (its own minimum). Probing $a_{mid}$ and $a_{mid+1}$ tells which half keeps the certificate.
  Cost: 2 probes per halving, $2 \cdot 17 = 34 \le 100$. This is ternary search's discrete cousin, without needing
  unimodality.

<details><summary>Solution</summary>

Invariant from §2; cache values so no index is queried twice. $\le 2\lceil \log_2 n\rceil$ queries.

```cpp
#include <bits/stdc++.h>
using namespace std;
int n;
map<int, int> cache;
int get(int i) {
    if (i < 1 || i > n) return INT_MAX;          // a_0 = a_{n+1} = +infinity
    auto it = cache.find(i);
    if (it != cache.end()) return it->second;
    cout << "? " << i << endl;
    int v; cin >> v;
    if (v == -1) exit(0);
    return cache[i] = v;
}
int main() {
    cin >> n;
    int lo = 1, hi = n;                           // a[lo-1] > a[lo] and a[hi] < a[hi+1]
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (get(mid) < get(mid + 1)) hi = mid; else lo = mid + 1;
    }
    cout << "! " << lo << endl;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int n;
    static Map<Integer, Integer> cache = new HashMap<>();
    static BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
    static PrintWriter out = new PrintWriter(System.out);
    static int get(int i) throws IOException {
        if (i < 1 || i > n) return Integer.MAX_VALUE;
        Integer c = cache.get(i);
        if (c != null) return c;
        out.println("? " + i); out.flush();
        int v = Integer.parseInt(br.readLine().trim());
        if (v == -1) System.exit(0);
        cache.put(i, v);
        return v;
    }
    public static void main(String[] args) throws IOException {
        n = Integer.parseInt(br.readLine().trim());
        int lo = 1, hi = n;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (get(mid) < get(mid + 1)) hi = mid; else lo = mid + 1;
        }
        out.println("! " + lo); out.flush();
    }
}
```

</details>

#### Example 3 — local simulation (tested)

Input: $n$ and the hidden permutation. Output: the reported index and the number of distinct queries.

<details><summary>Simulated judge</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<int> a(n + 2, INT_MAX);
    for (int i = 1; i <= n; i++) cin >> a[i];
    set<int> asked;
    auto get = [&](int i) { if (i >= 1 && i <= n) asked.insert(i); return a[i]; };
    int lo = 1, hi = n;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (get(mid) < get(mid + 1)) hi = mid; else lo = mid + 1;
    }
    cout << lo << ' ' << asked.size() << '\n';
}
```

```java
import java.util.*;

public class Main {
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        int n = sc.nextInt();
        int[] a = new int[n + 2];
        a[0] = a[n + 1] = Integer.MAX_VALUE;
        for (int i = 1; i <= n; i++) a[i] = sc.nextInt();
        Set<Integer> asked = new HashSet<>();
        int lo = 1, hi = n;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            asked.add(mid); asked.add(mid + 1);          // mid + 1 <= hi <= n here
            if (a[mid] < a[mid + 1]) hi = mid; else lo = mid + 1;
        }
        System.out.println(lo + " " + asked.size());
    }
}
```

<!-- test
in:
1
1
out:
1 0
-->
<!-- test
in:
5
3 2 1 4 5
out:
3 3
-->
<!-- test
in:
4
1 2 3 4
out:
1 3
-->

</details>

### Example 4 — Guessing the Greatest (hard version)  ·  ★ 1900

- **Source:** [CF 1486C2 · Guessing the Greatest (hard version)](https://codeforces.com/problemset/problem/1486/C2) — 1900
- **Difficulty:** 1900
- **Problem:** a hidden array of $n \le 10^5$ distinct numbers. Query `? l r` ($l < r$) returns the *position of the second
  maximum* of $a_l..a_r$. Find the position of the maximum with at most 20 queries.
- **Thinking from first principles:** $\lceil \log_2 10^5 \rceil = 17$, so we have 3 spare queries — a binary search plus
  a little setup. The answer to a query on the whole array, $s$, is the second maximum; the maximum $M$ is "next to" it in
  the sense that any segment containing both $s$ and $M$ returns $s$. Ask `? 1 s` to learn the side of $M$ (if $s > 1$).
  If $M$ is left of $s$: for $l \le M$ the segment $[l, s]$ contains $M$ and returns $s$; for $l > M$ it does not (then $s$
  is the segment's maximum and the answer is something else). That predicate is monotone in $l$ — binary search for the
  largest $l$ with answer $s$. Symmetric on the right. Total $\le 2 + 17 = 19$.

<details><summary>Solution</summary>

$s = $ `? 1 n`. If $s > 1$ and `? 1 s` $= s$: binary search the largest $l \in [1, s-1]$ with `? l s` $= s$. Otherwise binary search the
smallest $r \in [s+1, n]$ with `? s r` $= s$. Every query has $l < r$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int ask(int l, int r) {
    cout << "? " << l << ' ' << r << endl;
    int p; cin >> p;
    if (p == -1) exit(0);
    return p;
}
int main() {
    int n; cin >> n;
    int s = ask(1, n), ans;
    if (s > 1 && ask(1, s) == s) {                 // maximum is left of s
        int lo = 1, hi = s - 1;                    // largest l with ask(l, s) == s
        while (lo < hi) {
            int mid = (lo + hi + 1) / 2;
            if (ask(mid, s) == s) lo = mid; else hi = mid - 1;
        }
        ans = lo;
    } else {                                       // maximum is right of s
        int lo = s + 1, hi = n;                    // smallest r with ask(s, r) == s
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (ask(s, mid) == s) hi = mid; else lo = mid + 1;
        }
        ans = lo;
    }
    cout << "! " << ans << endl;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
    static PrintWriter out = new PrintWriter(System.out);
    static int ask(int l, int r) throws IOException {
        out.println("? " + l + " " + r); out.flush();
        int p = Integer.parseInt(br.readLine().trim());
        if (p == -1) System.exit(0);
        return p;
    }
    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(br.readLine().trim());
        int s = ask(1, n), ans;
        if (s > 1 && ask(1, s) == s) {
            int lo = 1, hi = s - 1;
            while (lo < hi) {
                int mid = (lo + hi + 1) / 2;
                if (ask(mid, s) == s) lo = mid; else hi = mid - 1;
            }
            ans = lo;
        } else {
            int lo = s + 1, hi = n;
            while (lo < hi) {
                int mid = (lo + hi) / 2;
                if (ask(s, mid) == s) hi = mid; else lo = mid + 1;
            }
            ans = lo;
        }
        out.println("! " + ans); out.flush();
    }
}
```

</details>

#### Example 4 — local simulation (tested)

Input: $n$ and the hidden array. Output: the reported position and the number of queries. The judge answers each query
by scanning the segment (fine for testing).

<details><summary>Simulated judge</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<long long> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    int queries = 0;
    auto ask = [&](int l, int r) {                 // position of the second maximum of a[l..r]
        ++queries;
        int b1 = -1, b2 = -1;
        for (int i = l; i <= r; i++) {
            if (b1 == -1 || a[i] > a[b1]) { b2 = b1; b1 = i; }
            else if (b2 == -1 || a[i] > a[b2]) b2 = i;
        }
        return b2;
    };
    int s = ask(1, n), ans;
    if (s > 1 && ask(1, s) == s) {
        int lo = 1, hi = s - 1;
        while (lo < hi) { int mid = (lo + hi + 1) / 2; if (ask(mid, s) == s) lo = mid; else hi = mid - 1; }
        ans = lo;
    } else {
        int lo = s + 1, hi = n;
        while (lo < hi) { int mid = (lo + hi) / 2; if (ask(s, mid) == s) hi = mid; else lo = mid + 1; }
        ans = lo;
    }
    cout << ans << ' ' << queries << '\n';
}
```

```java
import java.util.*;

public class Main {
    static long[] a;
    static int queries = 0;
    static int ask(int l, int r) {
        queries++;
        int b1 = -1, b2 = -1;
        for (int i = l; i <= r; i++) {
            if (b1 == -1 || a[i] > a[b1]) { b2 = b1; b1 = i; }
            else if (b2 == -1 || a[i] > a[b2]) b2 = i;
        }
        return b2;
    }
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        int n = sc.nextInt();
        a = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = sc.nextLong();
        int s = ask(1, n), ans;
        if (s > 1 && ask(1, s) == s) {
            int lo = 1, hi = s - 1;
            while (lo < hi) { int mid = (lo + hi + 1) / 2; if (ask(mid, s) == s) lo = mid; else hi = mid - 1; }
            ans = lo;
        } else {
            int lo = s + 1, hi = n;
            while (lo < hi) { int mid = (lo + hi) / 2; if (ask(s, mid) == s) hi = mid; else lo = mid + 1; }
            ans = lo;
        }
        System.out.println(ans + " " + queries);
    }
}
```

<!-- test
in:
2
1 2
out:
2 1
-->
<!-- test
in:
5
5 1 4 2 3
out:
1 3
-->
<!-- test
in:
4
1 3 2 4
out:
4 3
-->

</details>

### Example 5 — XOR Guessing (adaptive judge)  ·  ★ 1900

- **Source:** [CF 1207E · XOR Guessing](https://codeforces.com/problemset/problem/1207/E) — 1900
- **Difficulty:** 1900
- **Problem:** a hidden $x \in [0, 2^{14})$. You make exactly two queries; each lists 100 distinct integers in $[0, 2^{14})$ (all 200
  distinct overall). For each query the judge picks *one* of your numbers $q_i$ — any one, possibly adversarially — and
  replies $q_i \oplus x$. Then print $x$.
- **Thinking from first principles:** we do not know which $q_i$ was used, so the reply is useful only in the bits
  where all our numbers agree. 100 numbers need at least 7 bits of variation ($2^7 = 128 \ge 100$); put the variation in
  the low 7 bits in query 1 (numbers $1..100$, high bits zero) and in the high 7 bits in query 2 (numbers $i \cdot 2^7$, low bits
  zero). Reply 1 then reveals the high 7 bits of $x$ exactly and reply 2 the low 7 bits — whatever index the judge chose.
  The two sets are disjoint ($< 128$ versus multiples of 128 that are $\ge 128$).

<details><summary>Solution</summary>

$x = (r_1 \mathbin{\&} \lnot 127) \mid (r_2 \mathbin{\&} 127)$. Two queries, correct against any adaptive choice.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    cout << "?";
    for (int i = 1; i <= 100; i++) cout << ' ' << i;          // high 7 bits are 0
    cout << endl;
    int r1; cin >> r1;
    if (r1 == -1) return 0;
    cout << "?";
    for (int i = 1; i <= 100; i++) cout << ' ' << (i << 7);   // low 7 bits are 0
    cout << endl;
    int r2; cin >> r2;
    if (r2 == -1) return 0;
    cout << "! " << ((r1 & ~127) | (r2 & 127)) << endl;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(System.out);
        StringBuilder q1 = new StringBuilder("?"), q2 = new StringBuilder("?");
        for (int i = 1; i <= 100; i++) { q1.append(' ').append(i); q2.append(' ').append(i << 7); }
        out.println(q1); out.flush();
        int r1 = Integer.parseInt(br.readLine().trim());
        if (r1 == -1) return;
        out.println(q2); out.flush();
        int r2 = Integer.parseInt(br.readLine().trim());
        if (r2 == -1) return;
        out.println("! " + ((r1 & ~127) | (r2 & 127))); out.flush();
    }
}
```

</details>

#### Example 5 — local simulation (tested)

Input: hidden $x$ and the (adversary's) chosen indices $i_1, i_2 \in [1, 100]$. Output: recovered $x$ and the number of queries.

<details><summary>Simulated judge</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int x, i1, i2; cin >> x >> i1 >> i2;
    vector<int> q1, q2;
    for (int i = 1; i <= 100; i++) { q1.push_back(i); q2.push_back(i << 7); }
    int r1 = q1[i1 - 1] ^ x, r2 = q2[i2 - 1] ^ x;               // judge picks any element
    cout << ((r1 & ~127) | (r2 & 127)) << ' ' << 2 << '\n';
}
```

```java
import java.util.*;

public class Main {
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        int x = sc.nextInt(), i1 = sc.nextInt(), i2 = sc.nextInt();
        int r1 = i1 ^ x, r2 = (i2 << 7) ^ x;                     // q1[i] = i, q2[i] = i << 7
        System.out.println(((r1 & ~127) | (r2 & 127)) + " " + 2);
    }
}
```

<!-- test
in:
0 1 1
out:
0 2
-->
<!-- test
in:
16383 100 100
out:
16383 2
-->
<!-- test
in:
5000 37 64
out:
5000 2
-->

</details>

All five strategies were stress-tested through their simulations on random hidden data (checking correctness and the
query budget), and the real programs were run against local interactors through the pipe runner of §3.3.

## 6. Tricks, pitfalls and things to remember

1. **Flush after every query.** C++: `endl` / `cout << flush` / `fflush(stdout)`; Java: `out.flush()`. Missing it gives
   *Idleness limit exceeded*, not WA.
2. **Exit on −1** immediately; continuing produces misleading verdicts.
3. **Count queries exactly.** Write the budget next to your loop; probes in a binary search are $\lceil \log_2 n \rceil$, not
   $\log_2 n + 1$ "roughly". Cache repeated probes (Example 3).
4. **Multiple test cases:** read the next test's $n$ only after printing the previous answer; reset caches per test.
5. **The answer line also needs a flush** — the last line of output is the classic forgotten one.
6. **Do not print debug output to stdout.** Use `cerr` / `System.err`; anything on stdout is a query to the judge.
7. **Read exactly what the judge sends** (sometimes it sends a status word after your answer, e.g. "Correct"/"-1" per test);
   unread tokens desynchronise the next test.
8. **Java:** `Scanner` is slow but rarely the bottleneck in interactive problems (few lines); still, `BufferedReader` is
   safer. Never wrap `System.in` in two different readers.
9. **Adaptive judges** defeat "random pivot" strategies only in the worst case; a deterministic halving strategy with an
   invariant is always safe.
10. **Information bound first.** If your strategy needs more queries than the budget, compute $\lceil \log_k N\rceil$: if
    the budget is close to it, every query must split the candidates evenly — look for a query with balanced answers.
11. **Test with a local judge**, including the worst-case hidden data for your strategy (e.g. the answer at either end).

## 7. Going further (toward 2400–2600+)

- **Adversary arguments as design tools:** to find an optimal strategy, imagine the judge keeping the largest consistent
  set; your query must split it evenly (CF 1365G "Secure Password" uses a code-design view of queries).
- **Interactive on trees:** centroid-based halving ("is the hidden vertex in this subtree?" in $O(\log n)$ queries),
  LCA/distance queries ([centroid decomposition](../10-Trees/05-centroid-decomposition.md)).
- **Randomised interactive strategies** against non-adaptive judges: sample to estimate a rank, then binary search
  (CF 843B "Interactive LowerBound").
- **Noisy / lying judges:** each answer may be wrong with some pattern (CF 1746E "Joking"); strategies combine repeated
  queries with ternary-style elimination.
- **Interactive games:** you play against the judge (CF 1375F); combine game theory ([game fundamentals](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md))
  with protocol handling.

## 8. Practice ladder

**≤ 1600**
- [ ] [CF 1807E · Interview](https://codeforces.com/problemset/problem/1807/E) — 1300
- [ ] [CF 679A · Bear and Prime 100](https://codeforces.com/problemset/problem/679/A) — 1400
- [ ] [CF 1167B · Lost Numbers](https://codeforces.com/problemset/problem/1167/B) — 1400
- [ ] [CF 727C · Guess the Array](https://codeforces.com/problemset/problem/727/C) — 1400
- [ ] [CF 1520F1 · Guess the K-th Zero (Easy version)](https://codeforces.com/problemset/problem/1520/F1) — 1600
- [ ] [CF 1486C1 · Guessing the Greatest (easy version)](https://codeforces.com/problemset/problem/1486/C1) — 1600
- [ ] [CF 1407C · Chocolate Bunny](https://codeforces.com/problemset/problem/1407/C) — 1600
- [ ] [CF 1698D · Fixed Point Guessing](https://codeforces.com/problemset/problem/1698/D) — 1600
- [ ] [CSES 3112 · Hidden Integer](https://cses.fi/problemset/task/3112)
- [ ] [CSES 3139 · Hidden Permutation](https://cses.fi/problemset/task/3139)

**1600–2100**
- [ ] [CF 1479A · Searching Local Minimum](https://codeforces.com/problemset/problem/1479/A) — 1700
- [ ] [CF 1146C · Tree Diameter](https://codeforces.com/problemset/problem/1146/C) — 1700
- [ ] [CF 1010B · Rocket](https://codeforces.com/problemset/problem/1010/B) — 1800
- [ ] [CF 1486C2 · Guessing the Greatest (hard version)](https://codeforces.com/problemset/problem/1486/C2) — 1900
- [ ] [CF 1207E · XOR Guessing](https://codeforces.com/problemset/problem/1207/E) — 1900
- [ ] [CF 1305D · Kuroni and the Celebration](https://codeforces.com/problemset/problem/1305/D) — 1900
- [ ] [CF 843B · Interactive LowerBound](https://codeforces.com/problemset/problem/843/B) — 2000
- [ ] [CF 1363D · Guess The Maximums](https://codeforces.com/problemset/problem/1363/D) — 2100
- [ ] [CSES 3305 · K-th Highest Score](https://cses.fi/problemset/task/3305)

**2100+**
- [ ] [CF 1039B · Subway Pursuit](https://codeforces.com/problemset/problem/1039/B) — 2100
- [ ] [CF 1520F2 · Guess the K-th Zero (Hard version)](https://codeforces.com/problemset/problem/1520/F2) — 2200
- [ ] [CF 1114E · Arithmetic Progression](https://codeforces.com/problemset/problem/1114/E) — 2200
- [ ] [CF 1174F · Ehab and the Big Finale](https://codeforces.com/problemset/problem/1174/F) — 2400
- [ ] [CF 1365G · Secure Password](https://codeforces.com/problemset/problem/1365/G) — 2800

## 9. LeetCode / FAANG cross-reference

LeetCode models interaction as an API you call (`guess(num)`, `isBadVersion(v)`, `MountainArray.get(i)`), so flushing
disappears but the query-budget reasoning stays.

- [LC 374 · Guess Number Higher or Lower](https://leetcode.com/problems/guess-number-higher-or-lower/) — Easy — binary search on the hidden number.
- [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy — first-true binary search; overflow-safe `mid`.
- [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium — the local-extremum invariant of Example 3.
- [LC 852 · Peak Index in a Mountain Array](https://leetcode.com/problems/peak-index-in-a-mountain-array/) — Medium — same, on a strictly unimodal array.
- [LC 1095 · Find in Mountain Array](https://leetcode.com/problems/find-in-mountain-array/) — Hard — peak search then two binary searches under a call budget (100 calls).
- [LC 702 · Search in a Sorted Array of Unknown Size](https://leetcode.com/problems/search-in-a-sorted-array-of-unknown-size/) — Medium 🔒 — exponential search for a bound, then binary search.
- [LC 1237 · Find Positive Integer Solution for a Given Equation](https://leetcode.com/problems/find-positive-integer-solution-for-a-given-equation/) — Medium — staircase search over a monotone hidden function.
- [LC 277 · Find the Celebrity](https://leetcode.com/problems/find-the-celebrity/) — Medium 🔒 — $n-1$ elimination queries, then verification.
- [LC 843 · Guess the Word](https://leetcode.com/problems/guess-the-word/) — Hard — choose queries that minimise the worst-case surviving set (adversary thinking).

Interactive problems themselves are rare in interviews; the transferable skill is reasoning about a call budget
against an opaque API.

## 10. Self-check

1. What verdict do you get if you forget to flush, and how do you flush in C++ and Java?
2. Why must you exit immediately after reading −1?
3. Derive a lower bound on the number of yes/no queries to identify one of $n$ items. Why is it tight against an adaptive judge?
4. State the invariant used to find a local minimum with point queries, and prove the final index is a local minimum.
5. In Guessing the Greatest, why is "segment $[l, s]$ returns $s$" monotone in $l$ when the maximum is left of $s$?
6. Why does XOR Guessing work no matter which of your 100 numbers the judge chooses?
7. How do you test an interactive solution locally? Name the two approaches and what each catches.

<details><summary>Answers</summary>

1. *Idleness limit exceeded* (both programs wait). C++: `endl`, `cout << flush`, `fflush(stdout)`; Java: `out.flush()`.
2. −1 means the judge rejected a query or the budget is exhausted; reading on desynchronises the protocol and hides the
   real error behind a misleading verdict.
3. $q$ answers have $2^q$ patterns, so $2^q \ge n$, $q \ge \lceil \log_2 n \rceil$. An adaptive judge always answers so that at least
   half of the consistent candidates survive, forcing that many queries.
4. $a_{lo-1} > a_{lo}$ and $a_{hi} < a_{hi+1}$ (with $\pm\infty$ borders). When $lo = hi$ both neighbours are larger.
5. For $l \le M$ the segment contains $M$ and $s$, and $s$ is the second largest of the whole array, hence of the segment;
   for $l > M$ the segment lacks $M$, so $s$ is its maximum and the second maximum is another position.
6. All numbers in query 1 share their high 7 bits (zero) and all numbers in query 2 share their low 7 bits (zero); XOR
   with $x$ preserves those bits of $x$ regardless of which number was chosen.
7. In-process simulation (strategy against a local `ask()`; stress-testable, catches logic and budget bugs) and a real
   local interactor connected by pipes (catches flushing, formatting and protocol bugs).

</details>
