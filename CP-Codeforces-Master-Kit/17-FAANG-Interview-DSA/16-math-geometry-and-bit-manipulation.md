# Math, Geometry and Bit Manipulation

> **Band:** 🟢 ≤ 1400 · **Priority:** ⚡ · **FAANG:** medium · **Prerequisites:** [bit manipulation (CP)](../01-Foundations/03-bit-manipulation.md), [integer overflow and precision](../01-Foundations/06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you can derive XOR and carry tricks from the truth tables, handle `INT_MIN` and overflow without guessing, rotate or spiral a matrix in place with clear boundaries, and implement fast exponentiation iteratively.

Interview math is shallow but **precise**: overflow, negative numbers, two's complement and off-by-one boundaries are what get tested. This file groups the three families the fetched lists file together (NeetCode calls them "Math & Geometry" and "Bit Manipulation"): bit tricks, integer arithmetic, and matrix/geometry manipulation.

## 1. First principles — why this works

### 1.1 XOR is addition without carries

Bitwise, $a \oplus b$ is addition modulo 2, so XOR is associative and commutative, $x \oplus x = 0$, and $x \oplus 0 = x$. XOR-ing a whole array therefore cancels every value that appears an even number of times. That is Single Number, and Missing Number (XOR all indices and values). Full addition is XOR plus carries: $a + b = (a \oplus b) + 2(a \mathbin{\&} b)$, because the carry out of each position is exactly the AND of the two bits. Repeating that identity until the carry is zero adds two integers without `+` (Sum of Two Integers). It terminates within 32 iterations because the carry moves left one bit per round.

### 1.2 Two's complement

A $w$-bit signed integer represents $-2^{w-1} \dots 2^{w-1} - 1$, and $-x = \lnot x + 1$. Consequences you must know:

- `x & -x` isolates the lowest set bit; `x & (x - 1)` clears it (Kernighan's popcount loop runs once per set bit).
- $|\texttt{INT\_MIN}| = 2^{31}$ is not representable, so `-INT_MIN` and `abs(INT_MIN)` overflow. Convert to 64-bit first (Pow with $n = -2^{31}$, Divide Two Integers).
- Right shift of a negative number is arithmetic in Java (`>>`) and implementation-defined before C++20 (arithmetic since C++20). Java's `>>>` is the logical shift.
- In C++, left-shifting a negative value was undefined before C++20, so do carry arithmetic on `unsigned`.

### 1.3 Fast exponentiation

$x^n = (x^{\lfloor n/2 \rfloor})^2 \cdot x^{n \bmod 2}$, so $O(\log n)$ multiplications suffice. Iteratively: scan the bits of $n$, squaring the base each step and multiplying it into the result when the bit is set. With a modulus this is modular exponentiation. It is the same algorithm, and also the basis of matrix exponentiation ([CP](../15-Advanced-Math/01-matrices-and-linear-recurrences.md)).

### 1.4 Matrix manipulation is index algebra

Rotating an $n \times n$ matrix 90° clockwise maps $(r, c) \to (c, n - 1 - r)$. Doing it in place is easiest as two involutions: **transpose** ($(r, c) \leftrightarrow (c, r)$), then **reverse each row** ($c \to n - 1 - c$). Their composition is $(r, c) \to (c, r) \to (c, n - 1 - r)$, as required. Spiral order is four boundary walks (top row, right column, bottom row, left column) that shrink the boundaries after each walk. The `if` checks before the last two walks handle single remaining rows or columns.

### 1.5 Geometry with integers

Use integer arithmetic whenever possible. The cross product $(b - a) \times (c - a) = (b_x - a_x)(c_y - a_y) - (b_y - a_y)(c_x - a_x)$ is positive for a left turn, negative for a right turn and zero for collinear points. Twice a polygon's area is $\left|\sum_i x_i y_{i+1} - x_{i+1} y_i\right|$ (shoelace). A line's direction is normalised as $(dx, dy)/\gcd(|dx|, |dy|)$ with a sign convention, which is exact, unlike a floating-point slope (Max Points on a Line).

## 2. Formulas and identities

| Identity / trick | Meaning |
|---|---|
| $x \oplus x = 0$, $x \oplus 0 = x$ | pairs cancel |
| $a + b = (a \oplus b) + ((a \mathbin{\&} b) \ll 1)$ | add without `+` |
| `x & (x - 1)` | clear the lowest set bit; `x > 0 && (x & (x-1)) == 0` ⇔ power of two |
| `x & -x` | lowest set bit |
| `bits[i] = bits[i >> 1] + (i & 1)` | popcount of $0..n$ in $O(n)$ (Counting Bits) |
| `for (s = m; s; s = (s - 1) & m)` | iterate all non-empty submasks of `m` |
| $\sum_{i=0}^{n} i = n(n+1)/2$ | missing number by sum (watch overflow; XOR avoids it) |
| $\gcd(a, b) = \gcd(b, a \bmod b)$ | Euclid, $O(\log \min)$ |
| $\operatorname{lcm}(a, b) = a / \gcd(a,b) \cdot b$ | divide first to avoid overflow |
| trailing zeros of $n!$ | $\sum_{k \ge 1} \lfloor n / 5^k \rfloor$ |
| $x^n$ by squaring | $O(\log n)$ multiplications |
| rotate 90° clockwise | transpose, then reverse every row; counter-clockwise: reverse rows, then transpose |
| cross product sign | orientation of $(a, b, c)$ |
| shoelace | $2A = \left|\sum x_i y_{i+1} - x_{i+1} y_i\right|$ |
| reverse a 32-bit integer | check `res > INT_MAX / 10` (or the last digit) **before** multiplying |

## 3. Reusable templates (C++ and Java)

Bit helpers, integer helpers and the orientation test:

```cpp
int popcount32(unsigned x) {                       // Kernighan: one iteration per set bit
    int c = 0;
    while (x) { x &= x - 1; ++c; }
    return c;
}

vector<int> countBits(int n) {                     // LC 338
    vector<int> bits(n + 1, 0);
    for (int i = 1; i <= n; ++i) bits[i] = bits[i >> 1] + (i & 1);
    return bits;
}

uint32_t reverseBits(uint32_t x) {                 // LC 190
    uint32_t r = 0;
    for (int i = 0; i < 32; ++i) { r = (r << 1) | (x & 1); x >>= 1; }
    return r;
}

long long modPow(long long base, long long e, long long mod) {
    long long result = 1 % mod;
    base %= mod;
    if (base < 0) base += mod;
    while (e > 0) {
        if (e & 1) result = result * base % mod;   // this bit of e is set
        base = base * base % mod;
        e >>= 1;
    }
    return result;
}

int reverseInteger(int x) {                        // LC 7: 0 on 32-bit overflow
    int res = 0;
    while (x != 0) {
        int d = x % 10;                            // C++ and Java: sign follows x
        if (res > INT_MAX / 10 || (res == INT_MAX / 10 && d > 7)) return 0;
        if (res < INT_MIN / 10 || (res == INT_MIN / 10 && d < -8)) return 0;
        res = res * 10 + d;
        x /= 10;
    }
    return res;
}

long long cross(long long ax, long long ay, long long bx, long long by, long long cx, long long cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);   // > 0 left turn, < 0 right turn, 0 collinear
}
```

```java
static int popcount32(int x) {
    int c = 0;
    while (x != 0) { x &= x - 1; c++; }               // works for negative x too (two's complement)
    return c;
}

static int[] countBits(int n) {
    int[] bits = new int[n + 1];
    for (int i = 1; i <= n; i++) bits[i] = bits[i >> 1] + (i & 1);
    return bits;
}

static int reverseBits(int x) {                       // treat x as unsigned 32 bits
    int r = 0;
    for (int i = 0; i < 32; i++) { r = (r << 1) | (x & 1); x >>>= 1; }
    return r;
}

static long modPow(long base, long e, long mod) {
    long result = 1 % mod;
    base %= mod;
    if (base < 0) base += mod;
    while (e > 0) {
        if ((e & 1) == 1) result = result * base % mod;
        base = base * base % mod;
        e >>= 1;
    }
    return result;
}

static int reverseInteger(int x) {
    int res = 0;
    while (x != 0) {
        int d = x % 10;
        if (res > Integer.MAX_VALUE / 10 || (res == Integer.MAX_VALUE / 10 && d > 7)) return 0;
        if (res < Integer.MIN_VALUE / 10 || (res == Integer.MIN_VALUE / 10 && d < -8)) return 0;
        res = res * 10 + d;
        x /= 10;
    }
    return res;
}

static long cross(long ax, long ay, long bx, long by, long cx, long cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "every element appears twice except one", "missing number", $O(1)$ space | XOR |
| "appears three times except one" | count each bit mod 3 (or the two-variable state machine) |
| "without using + / − / * / /" | XOR + carry; shifts and subtraction by doubling |
| "count set bits", "power of two", "Hamming distance" | `x & (x-1)`, `popcount` |
| subsets of a small set | bitmasks ([backtracking](10-backtracking.md)) |
| "reverse digits", "palindrome number", "string to integer" | digit loop with overflow checks before the multiply |
| "power", "modular exponent", "last digits of a huge power" | fast exponentiation |
| matrix "rotate", "spiral", "set zeroes in place", "game of life in place" | index algebra; encode two states in one cell, or use the first row/column as markers |
| "points on a line", "squares", "rectangles" | integer vectors, gcd-normalised directions, hash maps of points |
| big numbers as strings (add / multiply) | schoolbook digit arithmetic, result length $\le n + m$ |

## 5. Worked examples

### Example 1 — Single Number · Easy

- **Source:** [LC 136 · Single Number](https://leetcode.com/problems/single-number/) — Easy · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Easy (≈ 800 CF, est.)
- **Problem:** every element appears exactly twice except one. Find it in $O(n)$ time and $O(1)$ extra space. $n \le 3 \cdot 10^4$, values in $[-3 \cdot 10^4, 3 \cdot 10^4]$.
- **Thinking from first principles:** a hash set gives $O(n)$ space, and sorting gives $O(n \log n)$ time. To use $O(1)$ space we need an operation under which pairs vanish and order does not matter: XOR (§1.1). The XOR of all elements groups into pairs $x \oplus x = 0$ and leaves the single value. Negative numbers are no problem, since XOR works on the two's-complement bits.

<details><summary>Solution</summary>

Fold the array with `^`. $O(n)$ time, $O(1)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int singleNumber(vector<int>& nums) {
        int acc = 0;
        for (int x : nums) acc ^= x;              // pairs cancel: x ^ x = 0
        return acc;
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().singleNumber(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int singleNumber(int[] nums) {
        int acc = 0;
        for (int x : nums) acc ^= x;
        return acc;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().singleNumber(a));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
3
2 2 1
out:
1
-->
<!-- test
in:
5
4 1 2 1 2
out:
4
-->
<!-- test
in:
1
-30000
out:
-30000
-->

### Example 2 — Sum of Two Integers · Medium

- **Source:** [LC 371 · Sum of Two Integers](https://leetcode.com/problems/sum-of-two-integers/) — Medium · `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** return $a + b$ for $a, b \in [-1000, 1000]$ without using `+` or `-`.
- **Thinking from first principles:** look at one bit position of $a + b$. The result bit is $a_i \oplus b_i$ (plus an incoming carry), and the carry out is $a_i \wedge b_i$. So $a + b = (a \oplus b) + ((a \mathbin{\&} b) \ll 1)$, which is again a sum, of a "partial sum" and a carry word. Iterate: set $a \leftarrow a \oplus b$ and $b \leftarrow (a \mathbin{\&} b) \ll 1$ (computed from the old values) until $b = 0$. Each round the carry's lowest set bit moves left by at least one, so at most 32 rounds. With negative numbers, two's complement makes the same bit rules give the right answer modulo $2^{32}$, but C++ must do the shift on `unsigned` to avoid undefined behaviour.

<details><summary>Solution</summary>

Loop until there is no carry. $O(32)$ time. In Java `int` arithmetic wraps by definition, so no cast is needed.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int getSum(int a, int b) {
        unsigned x = a, y = b;                    // unsigned: shifts and wraparound are well defined
        while (y != 0) {
            unsigned carry = (x & y) << 1;        // positions where both bits are 1 carry left
            x ^= y;                               // sum without carries
            y = carry;
        }
        return (int)x;
    }
};

int main() {
    int a, b;
    cin >> a >> b;
    cout << Solution().getSum(a, b) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int getSum(int a, int b) {
        while (b != 0) {
            int carry = (a & b) << 1;
            a ^= b;
            b = carry;
        }
        return a;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int a = in.nextInt(), b = in.nextInt();
        System.out.println(new Solution().getSum(a, b));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
1 2
out:
3
-->
<!-- test
in:
2 3
out:
5
-->
<!-- test
in:
-1000 1
out:
-999
-->
<!-- test
in:
-7 -8
out:
-15
-->
<!-- test
in:
1000 -1000
out:
0
-->

### Example 3 — Rotate Image · Medium

- **Source:** [LC 48 · Rotate Image](https://leetcode.com/problems/rotate-image/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** rotate an $n \times n$ matrix ($n \le 20$) 90° clockwise **in place**.
- **Thinking from first principles:** the target mapping is $(r, c) \to (c, n-1-r)$. Copying into a new matrix is trivial but not in place. Two ways to do it in place: rotate four cells at a time around each "ring" (fiddly indices), or decompose the rotation into two simple in-place operations. Transposing swaps across the main diagonal, and reversing each row mirrors left–right. Their composition is exactly the rotation (§1.4), and each one is a sequence of swaps.

<details><summary>Solution</summary>

Transpose the upper triangle ($c > r$ only, or every pair would be swapped twice), then reverse every row. $O(n^2)$ time, $O(1)$ extra space. The driver prints the rotated matrix row by row.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    void rotate(vector<vector<int>>& m) {
        int n = m.size();
        for (int r = 0; r < n; ++r)
            for (int c = r + 1; c < n; ++c) swap(m[r][c], m[c][r]);   // transpose
        for (auto& row : m) reverse(row.begin(), row.end());          // mirror left-right
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> m(n, vector<int>(n));
    for (auto& row : m) for (int& x : row) cin >> x;
    Solution().rotate(m);
    for (auto& row : m)
        for (int c = 0; c < n; ++c) cout << row[c] << (c + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public void rotate(int[][] m) {
        int n = m.length;
        for (int r = 0; r < n; r++)
            for (int c = r + 1; c < n; c++) { int t = m[r][c]; m[r][c] = m[c][r]; m[c][r] = t; }
        for (int[] row : m)
            for (int i = 0, j = n - 1; i < j; i++, j--) { int t = row[i]; row[i] = row[j]; row[j] = t; }
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] m = new int[n][n];
        for (int r = 0; r < n; r++) for (int c = 0; c < n; c++) m[r][c] = in.nextInt();
        new Solution().rotate(m);
        StringBuilder sb = new StringBuilder();
        for (int[] row : m)
            for (int c = 0; c < n; c++) sb.append(row[c]).append(c + 1 < n ? ' ' : '\n');
        System.out.print(sb);
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
3
1 2 3
4 5 6
7 8 9
out:
7 4 1
8 5 2
9 6 3
-->
<!-- test
in:
1
5
out:
5
-->
<!-- test
in:
2
1 2
3 4
out:
3 1
4 2
-->

### Example 4 — Spiral Matrix · Medium

- **Source:** [LC 54 · Spiral Matrix](https://leetcode.com/problems/spiral-matrix/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** return the elements of an $m \times n$ matrix ($m, n \le 10$) in clockwise spiral order.
- **Thinking from first principles:** simulating with a direction vector and a visited matrix works ($O(mn)$ extra space). Cleaner: keep four boundaries `top, bottom, left, right` of the unvisited rectangle. Walk the top row left to right, then `top++`. Walk the right column, then `right--`. Then, **only if a row remains**, walk the bottom row right to left and `bottom--`. **Only if a column remains**, walk the left column upwards and `left++`. The two guards prevent re-reading the same middle row or column when the rectangle has shrunk to a single line.

<details><summary>Solution</summary>

Each element is output exactly once. $O(mn)$ time, $O(1)$ extra space. The driver prints the order on one line.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> spiralOrder(vector<vector<int>>& g) {
        vector<int> out;
        int top = 0, bottom = (int)g.size() - 1, left = 0, right = (int)g[0].size() - 1;
        while (top <= bottom && left <= right) {
            for (int c = left; c <= right; ++c) out.push_back(g[top][c]);
            ++top;
            for (int r = top; r <= bottom; ++r) out.push_back(g[r][right]);
            --right;
            if (top <= bottom) {                               // a bottom row still exists
                for (int c = right; c >= left; --c) out.push_back(g[bottom][c]);
                --bottom;
            }
            if (left <= right) {                               // a left column still exists
                for (int r = bottom; r >= top; --r) out.push_back(g[r][left]);
                ++left;
            }
        }
        return out;
    }
};

int main() {
    int m, n;
    cin >> m >> n;
    vector<vector<int>> g(m, vector<int>(n));
    for (auto& row : g) for (int& x : row) cin >> x;
    vector<int> res = Solution().spiralOrder(g);
    for (size_t i = 0; i < res.size(); ++i) cout << res[i] << (i + 1 < res.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<Integer> spiralOrder(int[][] g) {
        List<Integer> out = new ArrayList<>();
        int top = 0, bottom = g.length - 1, left = 0, right = g[0].length - 1;
        while (top <= bottom && left <= right) {
            for (int c = left; c <= right; c++) out.add(g[top][c]);
            top++;
            for (int r = top; r <= bottom; r++) out.add(g[r][right]);
            right--;
            if (top <= bottom) {
                for (int c = right; c >= left; c--) out.add(g[bottom][c]);
                bottom--;
            }
            if (left <= right) {
                for (int r = bottom; r >= top; r--) out.add(g[r][left]);
                left++;
            }
        }
        return out;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int m = in.nextInt(), n = in.nextInt();
        int[][] g = new int[m][n];
        for (int r = 0; r < m; r++) for (int c = 0; c < n; c++) g[r][c] = in.nextInt();
        List<Integer> res = new Solution().spiralOrder(g);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < res.size(); i++) sb.append(res.get(i)).append(i + 1 < res.size() ? ' ' : '\n');
        System.out.print(sb);
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
3 3
1 2 3
4 5 6
7 8 9
out:
1 2 3 6 9 8 7 4 5
-->
<!-- test
in:
3 4
1 2 3 4
5 6 7 8
9 10 11 12
out:
1 2 3 4 8 12 11 10 9 5 6 7
-->
<!-- test
in:
1 3
1 2 3
out:
1 2 3
-->
<!-- test
in:
3 1
1
2
3
out:
1 2 3
-->

### Example 5 — Pow(x, n) · Medium

- **Source:** [LC 50 · Pow(x, n)](https://leetcode.com/problems/powx-n/) — Medium · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** compute $x^n$ for a double $x$ ($|x| < 100$) and a 32-bit integer $n$ (possibly negative, possibly $-2^{31}$). The result is within $[-10^4, 10^4]$.
- **Thinking from first principles:** multiplying $n$ times is $O(n)$, about $2 \cdot 10^9$ steps. Halve the exponent instead (§1.3): $O(\log n)$. Negative exponents: $x^{-n} = (1/x)^n$. The trap is $n = -2^{31}$, where `-n` overflows a 32-bit `int`. Convert $n$ to 64-bit **before** negating. Iterative binary exponentiation avoids recursion and handles every bit of the exponent uniformly.

<details><summary>Solution</summary>

`e = |n|` as a 64-bit integer, `base = x` (or `1/x` when $n < 0$); multiply `result` by `base` for each set bit while squaring `base`. $O(\log |n|)$ time. The driver prints five decimals.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    double myPow(double x, int n) {
        long long e = n;                          // widen before negating: -INT_MIN overflows int
        if (e < 0) { x = 1 / x; e = -e; }
        double result = 1.0;
        while (e > 0) {
            if (e & 1) result *= x;               // this bit contributes x^(2^k)
            x *= x;
            e >>= 1;
        }
        return result;
    }
};

int main() {
    double x;
    int n;
    cin >> x >> n;
    cout << fixed << setprecision(5) << Solution().myPow(x, n) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public double myPow(double x, int n) {
        long e = n;
        if (e < 0) { x = 1 / x; e = -e; }
        double result = 1.0;
        while (e > 0) {
            if ((e & 1) == 1) result *= x;
            x *= x;
            e >>= 1;
        }
        return result;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        double x = Double.parseDouble(st.nextToken());
        int n = Integer.parseInt(st.nextToken());
        System.out.printf(Locale.US, "%.5f%n", new Solution().myPow(x, n));
    }
}
```

</details>

<!-- test
in:
2.00000 10
out:
1024.00000
-->
<!-- test
in:
2.10000 3
out:
9.26100
-->
<!-- test
in:
2.00000 -2
out:
0.25000
-->
<!-- test
in:
1.00000 -2147483648
out:
1.00000
-->
<!-- test
in:
-1.00000 2147483647
out:
-1.00000
-->

## 6. Pitfalls and things to remember

1. **`INT_MIN` breaks `abs` and negation.** Widen to 64-bit first (`long long e = n; e = -e;`).
2. **Overflow checks happen before the operation:** `if (res > INT_MAX / 10 …)` before `res * 10 + d`. After the fact, the damage is done (and is undefined behaviour in C++).
3. **`%` on negatives:** in C++ and Java, `-7 % 10 == -7`. Normalise with `((x % m) + m) % m` when you need a non-negative residue.
4. **Shifts:** `1 << 31` is `INT_MIN` in Java and undefined behaviour in C++ before C++20. Use `1u << 31` or `1LL << k`. In Java use `>>>` for unsigned right shift, and `1L << k` for $k \ge 31$.
5. **Operator precedence:** `x & 1 == 0` parses as `x & (1 == 0)` in C++ and fails to compile in Java. Always parenthesise bit operations.
6. **Unsigned problems in Java** (Reverse Bits, Number of 1 Bits): the input `int` holds unsigned bits. Use `>>>` and `Integer.bitCount`, and compare with `Integer.toUnsignedString` when printing.
7. **Floating-point:** compare with an epsilon; never use doubles for slopes in Max Points on a Line (use a reduced `(dy, dx)` pair with a sign convention).
8. **Spiral boundaries:** missing the `top <= bottom` / `left <= right` guards duplicates the middle row or column of non-square matrices.
9. **In-place matrix tricks:** Set Matrix Zeroes uses the first row and column as marker arrays. Remember whether the first row/column itself must be zeroed, using two flags, before overwriting them.
10. **Sum formulas overflow:** $n(n+1)/2$ for $n = 10^5$ fits in `int`, but $10^9$ does not. XOR-based answers avoid the issue.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Single Number → "every other element appears three times" | count each of the 32 bits mod 3, or the `ones/twos` state machine ([LC 137 · Single Number II](https://leetcode.com/problems/single-number-ii/) — Medium) |
| → "two elements appear once" | XOR everything to get $a \oplus b$, split the array by its lowest set bit, XOR each half ([LC 260 · Single Number III](https://leetcode.com/problems/single-number-iii/) — Medium) |
| Sum of two integers → "subtract / multiply / divide without operators" | $a - b = a + (\lnot b + 1)$; multiply by shift-and-add; divide by subtracting shifted divisors ([LC 29 · Divide Two Integers](https://leetcode.com/problems/divide-two-integers/) — Medium) |
| Rotate → "counter-clockwise" / "180°" | reverse rows then transpose / reverse rows and columns |
| → "non-square matrix" | in place is not possible in general; allocate an $n \times m$ result |
| Spiral → "generate a spiral matrix" | the same four walks writing $1, 2, 3, \dots$ ([LC 59 · Spiral Matrix II](https://leetcode.com/problems/spiral-matrix-ii/) — Medium) |
| Pow → "modulo $10^9 + 7$" | the same loop with `% MOD` after each multiplication, 64-bit intermediates |
| → "recursive or iterative?" | both are $O(\log n)$; iterative avoids stack frames and the negative-exponent recursion trap |
| "Count primes below $n$" | sieve of Eratosthenes, $O(n \log \log n)$ ([LC 204 · Count Primes](https://leetcode.com/problems/count-primes/) — Medium) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Easy** (13)

- [ ] [LC 9 · Palindrome Number](https://leetcode.com/problems/palindrome-number/) — Easy · `G169` `TI150`
- [ ] [LC 13 · Roman to Integer](https://leetcode.com/problems/roman-to-integer/) — Easy · `G169` `NC250` `TI150`
- [ ] [LC 66 · Plus One](https://leetcode.com/problems/plus-one/) — Easy · `NC150` `TI150`
- [ ] [LC 67 · Add Binary](https://leetcode.com/problems/add-binary/) — Easy · `G75` `NC250` `TI150`
- [ ] [LC 136 · Single Number](https://leetcode.com/problems/single-number/) — Easy · `G169` `NC150` `TI150`
- [ ] [LC 168 · Excel Sheet Column Title](https://leetcode.com/problems/excel-sheet-column-title/) — Easy · `NC250`
- [ ] [LC 190 · Reverse Bits](https://leetcode.com/problems/reverse-bits/) — Easy · `G169` `B75` `NC150` `TI150`
- [ ] [LC 191 · Number of 1 Bits](https://leetcode.com/problems/number-of-1-bits/) — Easy · `G169` `B75` `NC150` `TI150`
- [ ] [LC 202 · Happy Number](https://leetcode.com/problems/happy-number/) — Easy · `NC150` `TI150`
- [ ] [LC 268 · Missing Number](https://leetcode.com/problems/missing-number/) — Easy · `G169` `B75` `NC150`
- [ ] [LC 338 · Counting Bits](https://leetcode.com/problems/counting-bits/) — Easy · `G169` `B75` `NC150`
- [ ] [LC 867 · Transpose Matrix](https://leetcode.com/problems/transpose-matrix/) — Easy · `NC250`
- [ ] [LC 1071 · Greatest Common Divisor of Strings](https://leetcode.com/problems/greatest-common-divisor-of-strings/) — Easy · `NC250`

**Medium** (14)

- [ ] [LC 7 · Reverse Integer](https://leetcode.com/problems/reverse-integer/) — Medium · `G169` `NC150`
- [ ] [LC 12 · Integer to Roman](https://leetcode.com/problems/integer-to-roman/) — Medium · `TI150`
- [ ] [LC 43 · Multiply Strings](https://leetcode.com/problems/multiply-strings/) — Medium · `NC150`
- [ ] [LC 48 · Rotate Image](https://leetcode.com/problems/rotate-image/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 50 · Pow(x, n)](https://leetcode.com/problems/powx-n/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 54 · Spiral Matrix](https://leetcode.com/problems/spiral-matrix/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 73 · Set Matrix Zeroes](https://leetcode.com/problems/set-matrix-zeroes/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 137 · Single Number II](https://leetcode.com/problems/single-number-ii/) — Medium · `TI150`
- [ ] [LC 172 · Factorial Trailing Zeroes](https://leetcode.com/problems/factorial-trailing-zeroes/) — Medium · `TI150`
- [ ] [LC 201 · Bitwise AND of Numbers Range](https://leetcode.com/problems/bitwise-and-of-numbers-range/) — Medium · `NC250` `TI150`
- [ ] [LC 289 · Game of Life](https://leetcode.com/problems/game-of-life/) — Medium · `TI150`
- [ ] [LC 371 · Sum of Two Integers](https://leetcode.com/problems/sum-of-two-integers/) — Medium · `B75` `NC150`
- [ ] [LC 2013 · Detect Squares](https://leetcode.com/problems/detect-squares/) — Medium · `NC150`
- [ ] [LC 3133 · Minimum Array End](https://leetcode.com/problems/minimum-array-end/) — Medium · `NC250`

**Hard** (1)

- [ ] [LC 149 · Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/) — Hard · `TI150`

**Beyond the lists:**

- [ ] [LC 231 · Power of Two](https://leetcode.com/problems/power-of-two/) — Easy — `x > 0 && (x & (x-1)) == 0`
- [ ] [LC 461 · Hamming Distance](https://leetcode.com/problems/hamming-distance/) — Easy — popcount of XOR
- [ ] [LC 1232 · Check If It Is a Straight Line](https://leetcode.com/problems/check-if-it-is-a-straight-line/) — Easy — cross products
- [ ] [LC 812 · Largest Triangle Area](https://leetcode.com/problems/largest-triangle-area/) — Easy — shoelace over triples
- [ ] [LC 260 · Single Number III](https://leetcode.com/problems/single-number-iii/) — Medium — split by the lowest set bit
- [ ] [LC 29 · Divide Two Integers](https://leetcode.com/problems/divide-two-integers/) — Medium — doubling subtraction, `INT_MIN` cases
- [ ] [LC 204 · Count Primes](https://leetcode.com/problems/count-primes/) — Medium — sieve
- [ ] [LC 223 · Rectangle Area](https://leetcode.com/problems/rectangle-area/) — Medium — inclusion–exclusion of overlap
- [ ] [LC 593 · Valid Square](https://leetcode.com/problems/valid-square/) — Medium — six squared distances
- [ ] [LC 59 · Spiral Matrix II](https://leetcode.com/problems/spiral-matrix-ii/) — Medium — the same boundary walk, writing

## 9. CP counterpart

- [Bit manipulation (CP)](../01-Foundations/03-bit-manipulation.md): submask enumeration, `__builtin_*` intrinsics, XOR tricks at scale.
- [Integer overflow, precision and fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md): the overflow and floating-point rules used here.
- [Modular arithmetic and inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) and [divisibility, gcd and extended Euclid](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md): fast power, gcd, inverses.
- [Vectors, dot/cross and precision](../14-Geometry/01-vectors-dot-cross-and-precision.md): orientation tests and exact geometry.
- [Gaussian elimination and XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md): the IGM-depth generalisation of "XOR of a subset".

Interview math rarely goes beyond this file. Number theory beyond gcd and fast power, combinatorics with modular inverses, and computational geometry beyond cross products are CP-only in practice.

## 10. Self-check

1. Why does XOR-ing all elements find the single number, and why do negative numbers not matter?
2. Derive $a + b = (a \oplus b) + ((a \mathbin{\&} b) \ll 1)$ and explain why the loop terminates.
3. What does `x & (x - 1)` do, and how does it give an $O(\text{popcount})$ loop?
4. Why is rotate = transpose + reverse rows? What is counter-clockwise?
5. Which two guards does the spiral walk need, and what breaks without them?
6. Why must Pow convert $n$ to 64-bit before negating?
7. How do you reverse a 32-bit integer and detect overflow without 64-bit arithmetic?
8. What is the sign convention for normalising a line direction $(dx, dy)$?

<details><summary>Answers</summary>

1. XOR is associative and commutative with $x \oplus x = 0$, so every pair cancels regardless of order. It acts on the bit patterns, so negative values in two's complement cancel the same way.
2. Per bit, the sum bit is the XOR and the carry out is the AND, shifted to the next position. Each iteration, the carry's lowest set bit moves strictly left (or the carry becomes 0), so after at most 32 iterations the carry is 0.
3. It clears the lowest set bit: subtracting 1 flips that bit and all the zeros below it. Looping `while (x) x &= x - 1` runs once per set bit.
4. Transpose maps $(r, c) \to (c, r)$ and reversing rows maps $(r, c) \to (r, n-1-c)$; composed, $(r, c) \to (c, n-1-r)$, the clockwise rotation. Counter-clockwise: transpose then reverse columns (equivalently reverse rows then transpose).
5. `if (top <= bottom)` before the bottom row and `if (left <= right)` before the left column. Without them, a single remaining row or column is printed twice.
6. $-(-2^{31}) = 2^{31}$ does not fit in a signed 32-bit integer, so negation overflows.
7. Pop digits with `% 10` and `/ 10`. Before `res = res * 10 + d`, check `res > INT_MAX / 10 || (res == INT_MAX / 10 && d > 7)` and the symmetric negative condition.
8. Divide by $g = \gcd(|dx|, |dy|)$, then make the pair canonical, e.g. require $dx > 0$, or $dx = 0$ and $dy > 0$, by negating both if needed.

</details>
