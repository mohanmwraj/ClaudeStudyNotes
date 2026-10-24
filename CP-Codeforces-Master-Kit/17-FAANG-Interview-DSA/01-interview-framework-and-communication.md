# The Coding Interview: Framework and Communication

> **Band:** all · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** in a 45-minute mock you clarify, propose a brute force, improve it, code it cleanly, test it by hand and state its complexity, while talking the whole time, and you finish with at least five minutes left for follow-ups.

A coding interview is not a contest. The interviewer is judging **how you get to a solution and whether they would want to work with you on code**, not only whether the code passes. A strong competitive programmer can fail an interview by silently typing a correct, cryptic solution, and a weaker programmer can pass by reasoning out loud to a clean, tested $O(n \log n)$ answer. This file gives the framework, the phrases to use, and what interviewers look for. Behavioural interviews are out of scope for this kit; prepare them separately with the STAR format and your own stories.

## 1. First principles — why the framework works

### 1.1 The interviewer can only grade what they observe

Your thinking is invisible unless you say it. Every step of the framework below produces **evidence** for one of the signals interviewers are commonly asked to assess. The usual four, as described in most public interview guides (practices vary by company, so treat this as the common shape, not an official rubric):

| Signal | What produces the evidence |
|---|---|
| Problem solving | clarifying questions, a brute force, a reasoned improvement, trade-offs |
| Coding | clean, idiomatic, correct code with sensible names and structure |
| Verification | hand-tracing an example, edge cases, fixing your own bugs before being told |
| Communication | narrating the plan, responding to hints, explaining complexity |

A silent correct solution provides evidence for only one of the four.

### 1.2 Brute force first is not wasted time

Saying the brute force (in one or two sentences, usually without coding it) does three things. It proves you understood the problem, it gives you a baseline complexity to beat, and the *waste* in the brute force is usually the hint to the optimal solution. Every pattern file in this folder starts its first-principles section with that waste ("for a fixed $j$ we only ask whether $T - a_j$ appeared before"). That is the move to rehearse.

### 1.3 Constraints tell you the target complexity

| $n$ up to | Typical target | Typical technique |
|---|---|---|
| 10–12 | $O(n!)$, $O(2^n \cdot n)$ | backtracking |
| 20–25 | $O(2^n)$ | bitmask DP, meet in the middle |
| 100–500 | $O(n^3)$ | interval DP, Floyd–Warshall |
| $10^3$–$5 \cdot 10^3$ | $O(n^2)$ | 2D DP, all pairs |
| $10^5$–$10^6$ | $O(n \log n)$ or $O(n)$ | sorting, heaps, binary search, two pointers, hashing |
| $10^9$+ (a value, not a size) | $O(\log V)$ or $O(\sqrt{V})$ | binary search on the answer, math |

Ask for the constraints if they are not given ("How large can $n$ be? Can values be negative? Can the input be empty?"). The answer often names the algorithm.

## 2. The framework (seven steps, 45 minutes)

| Step | What you do | Time (45-min slot) | Say something like |
|---|---|---|---|
| 1. Clarify | restate the problem, ask about input size, value ranges, duplicates, empty input, output format, in-place vs new structure | 2–4 min | "So I return the indices, not the values, and exactly one answer exists — is that right?" |
| 2. Examples | work one small example by hand, and one edge case | 2–3 min | "For `[2,7,11,15]`, target 9, the answer is `[0,1]`. What should happen for an empty array?" |
| 3. Brute force | state it and its complexity; usually don't code it | 1–2 min | "The straightforward way checks every pair: $O(n^2)$ time, $O(1)$ space." |
| 4. Optimise | find the waste, pick a pattern, state the new complexity, get buy-in | 5–10 min | "The repeated work is searching for the complement. A hash map makes that $O(1)$, so $O(n)$ overall. Shall I code that?" |
| 5. Code | write clean code, narrating the structure, not every keystroke | 10–15 min | "First the map from value to index, then one pass…" |
| 6. Test | trace your example through the code, then edge cases; fix bugs you find | 3–5 min | "Let me run `[3,3]`, target 6: at index 1 the complement 3 is already in the map, so we return `[0,1]`." |
| 7. Complexity and follow-ups | state time and space precisely; discuss variants | 2–5 min | "$O(n)$ time and $O(n)$ space. If the array were sorted I'd use two pointers for $O(1)$ space." |

Two interviews per round are common at large companies, sometimes with one shorter warm-up question followed by a harder one. If the first question takes 20 minutes, expect a second.

### 2.1 When you are stuck

1. **Re-state what you know** and what is missing: "I can do it in $O(n^2)$; I need to avoid rescanning the prefix."
2. **Try the pattern questions** from the [cheat sheet](../99-Cheat-Sheets/17-faang-interview-cheatsheet.md): sorted? → two pointers / binary search. Pairs or counts? → hash map. "Subarray"? → window or prefix sums. "All combinations"? → backtracking. "Minimum steps"? → BFS. "Optimal over choices"? → DP or greedy.
3. **Solve a smaller or special case** (sorted input, $k = 1$, no duplicates), then generalise.
4. **Ask for a hint** when you have been stuck for a few minutes. Taking a hint and running with it well is a positive signal. Silence is the worst outcome.

### 2.2 Coding style that reads well

- Function signature exactly as given. A helper for every logically separate step (`buildGraph`, `isValid`, `expandAroundCenter`).
- Names that say what they hold: `seen`, `count`, `left`, `right`, `best`, `dist`, never `a1`, `tmp2`.
- No CP macros (`#define`, `typedef ll`, `rep(i, n)`), no global arrays, no `#define int long long`. These cost points for readability even if they compile. See [CP → interview mapping](19-cp-to-interview-mapping.md).
- Guard clauses for edge cases at the top (`if (nums.empty()) return 0;`).
- Comment only the non-obvious line ("insert after lookup so an element can't pair with itself").

### 2.3 Testing by hand

Trace one normal example line by line **with the actual variable values**, then the edge cases: empty / one element, all equal, negative numbers, maximum values (overflow), duplicates, already sorted / reverse sorted, disconnected graph, cycle. Fix bugs calmly. Finding your own bug is evidence for verification, not a failure.

## 3. Worked example of the full framework (C++ and Java)

This section shows the seven steps on one problem, with both the brute force and the optimised solution as code so the progression is visible.

### Example — Best Time to Buy and Sell Stock · Easy

- **Source:** [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Easy (≈ 900 CF, est.)
- **Problem:** `prices[i]` is the price on day $i$ ($1 \le n \le 10^5$, $0 \le$ price $\le 10^4$). Buy once and sell once later. Return the maximum profit, or 0.

**1. Clarify.** "One transaction only? Must sell strictly after buying? Can I return 0 if the price only falls? Empty input is impossible since $n \ge 1$?" (Yes to all.)

**2. Examples.** `7 1 5 3 6 4` → buy at 1, sell at 6 → 5. `7 6 4 3 1` → 0. Edge: a single day → 0.

**3. Brute force.** "For every buy day $i$ and every later sell day $j$, compute `prices[j] - prices[i]`: $O(n^2)$ time, $O(1)$ space. With $n = 10^5$ that is $5 \cdot 10^9$ pairs, too slow."

**4. Optimise.** "For a fixed sell day $j$, the best buy day is the minimum price before $j$. The brute force recomputes that minimum for every $j$. That is the waste. Keep a running minimum instead: one pass, $O(n)$ time, $O(1)$ space." (This is the 1D DP / "best so far" pattern of [file 13](13-dynamic-programming-1d.md), and the window view of [file 03](03-two-pointers-and-sliding-window.md).)

<details><summary>Solution</summary>

**5. Code.** Both solutions are below. The driver prints the brute force and the optimised answer for comparison on small inputs, which is also how you would stress-test the optimisation offline.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int maxProfitBruteForce(const vector<int>& prices) {     // O(n^2): every (buy, sell) pair
        int best = 0;
        for (size_t i = 0; i < prices.size(); ++i)
            for (size_t j = i + 1; j < prices.size(); ++j)
                best = max(best, prices[j] - prices[i]);
        return best;
    }
    int maxProfit(vector<int>& prices) {                     // O(n): best buy so far
        int minPrice = INT_MAX, best = 0;
        for (int p : prices) {
            minPrice = min(minPrice, p);                      // cheapest day up to today
            best = max(best, p - minPrice);                   // sell today
        }
        return best;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> prices(n);
    for (int& x : prices) cin >> x;
    Solution s;
    cout << s.maxProfitBruteForce(prices) << ' ' << s.maxProfit(prices) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int maxProfitBruteForce(int[] prices) {
        int best = 0;
        for (int i = 0; i < prices.length; i++)
            for (int j = i + 1; j < prices.length; j++)
                best = Math.max(best, prices[j] - prices[i]);
        return best;
    }
    public int maxProfit(int[] prices) {
        int minPrice = Integer.MAX_VALUE, best = 0;
        for (int p : prices) {
            minPrice = Math.min(minPrice, p);
            best = Math.max(best, p - minPrice);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int n = (int) st.nval;
        int[] prices = new int[n];
        for (int i = 0; i < n; i++) { st.nextToken(); prices[i] = (int) st.nval; }
        Solution s = new Solution();
        System.out.println(s.maxProfitBruteForce(prices) + " " + s.maxProfit(prices));
    }
}
```

**6. Test.** Trace `7 1 5 3 6 4`: `minPrice` goes 7, 1, 1, 1, 1, 1 and `best` goes 0, 0, 4, 4, 5, 5, so the answer is 5. Falling prices `7 6 4 3 1`: `p - minPrice` is always 0, so 0. One day: 0.

**7. Complexity and follow-ups.** $O(n)$ time, $O(1)$ space. Follow-ups: unlimited transactions (sum every positive day-to-day difference, [LC 122 · Best Time to Buy and Sell Stock II](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-ii/) — Medium); at most $k$ transactions or a cooldown (state-machine DP, [file 14](14-dynamic-programming-2d.md)).

</details>

<!-- test
in:
6
7 1 5 3 6 4
out:
5 5
-->
<!-- test
in:
5
7 6 4 3 1
out:
0 0
-->
<!-- test
in:
1
5
out:
0 0
-->
<!-- test
in:
4
2 2 2 2
out:
0 0
-->

## 4. Communication scripts

| Moment | Script |
|---|---|
| Opening | "Let me restate it to make sure I understand: … Is the input always …?" |
| Before coding | "My plan: sort, then a two-pointer scan, $O(n \log n)$. Does that sound reasonable before I code it?" |
| Choosing between options | "A heap gives $O(n \log k)$ and works on a stream; quickselect is $O(n)$ expected but needs the whole array. I'll go with the heap unless you prefer otherwise." |
| While coding | "This helper returns the height and records the best diameter on the side." |
| When you spot a bug | "Wait, this fails for an empty list because `head->next` is null. Let me add a guard." |
| Stuck | "I have an $O(n^2)$ solution. The bottleneck is recomputing the minimum. Is there a structure I'm missing? Could I get a small hint?" |
| After a hint | "Good point. If the array is sorted, then the left pointer only moves right, so …" |
| Closing | "Time is $O(n \log n)$ for the sort; space is $O(1)$ beyond the output. Happy to discuss the streaming variant." |

## 5. Recognising interview-specific traps

| Trap | What it looks like | Better move |
|---|---|---|
| Jumping into code | typing within 30 seconds of reading | clarify, example, plan first (5 minutes is normal) |
| CP-style code | macros, one-letter names, globals | clean class code ([file 19](19-cp-to-interview-mapping.md)) |
| Over-engineering | segment tree for a problem that needs a prefix sum | the simplest structure that meets the bound |
| Silent debugging | staring at the screen | say what you are checking and why |
| Ignoring the interviewer | not reacting to hints or questions | treat it as pair programming |
| Unstated assumptions | assuming no duplicates, positive numbers | ask, or state the assumption explicitly |
| Wrong complexity | "it's $O(n)$" for nested loops over a string | count loops and the cost of library calls (hashing a string is $O(L)$) |
| Not testing | "I think it works" | trace one example and two edge cases |

## 6. Pitfalls and things to remember

1. **Time management:** if you are not coding by minute 15–20 of a 45-minute slot, simplify: code the brute force or the partial solution you have, then improve.
2. **Do not memorise solutions; memorise patterns.** Interviewers change details ("now with negatives", "now return the path") precisely to catch memorisation.
3. **Language choice:** use the language you are fastest and most precise in. Know its standard library cold: hash maps, heaps, sorting with comparators, deques, string builders.
4. **Pseudo-code is fine for a plan, not as the final answer.** Expect to write real code that would compile, in a plain editor without autocomplete.
5. **Overflow and edge cases are evidence of seniority.** Mention them even when the constraints make them harmless ("this fits in 32 bits because…").
6. **Never argue with the interviewer**; ask questions. If you believe they are mistaken, show a small example.
7. **Online assessments** (timed, automatically graded) reward CP skills more than live interviews do. Live interviews reward the framework.

## 7. Follow-up questions interviewers ask (on any problem)

| Question | What they want |
|---|---|
| "What is the time and space complexity?" | precise bounds, including library calls and recursion stack |
| "Can you do better?" | either an improvement or an argument for a lower bound (e.g. output size, reading the input) |
| "What if the input doesn't fit in memory?" | streaming, external sort, partitioning by hash, approximate structures |
| "What if this runs on many machines?" | sharding by key, map-reduce style aggregation, consistency trade-offs |
| "How would you test this?" | unit tests by category (normal, edge, large, randomised against a brute force) |
| "What if the input changes slightly (negatives, duplicates, k = 2)?" | which step of your reasoning breaks and what replaces it |

## 8. Practice

There is no problem list for this file. Practise the framework on every problem of [18-leetcode-master-list.md](18-leetcode-master-list.md), and do at least one timed mock per week as described in [20-faang-preparation-plan.md](20-faang-preparation-plan.md). Good first problems for rehearsing the full seven steps:

- [ ] [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy — brute force $O(n^2)$ → hash map $O(n)$
- [ ] [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy — the example above
- [ ] [LC 167 · Two Sum II - Input Array Is Sorted](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/) — Medium — the "sorted" follow-up as its own problem
- [ ] [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium — $O(n^3)$ → $O(n^2)$ → $O(n)$ narration
- [ ] [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium — key design trade-offs to discuss

## 9. CP counterpart

- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md): the constraint table of §1.3 in more depth.
- [First-principles problem solving](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md): the "find the waste" habit is the same one used to reach 2100 on Codeforces.
- [Contest strategy and mindset](../00-Roadmap-and-Strategy/04-contest-strategy-and-mindset.md): time management under pressure transfers directly. Silence and speed-typing do not.

## 10. Self-check

1. Name the seven steps and give a time budget for each in a 45-minute slot.
2. Which four signals do interviewers commonly assess, and which step produces evidence for each?
3. Why state the brute force even when you already know the optimal solution?
4. Given $n \le 2 \cdot 10^5$, which complexities are acceptable, and which techniques does that suggest?
5. What do you do after three minutes of being stuck?
6. What does a good hand test look like?

<details><summary>Answers</summary>

1. Clarify (2–4), examples (2–3), brute force (1–2), optimise (5–10), code (10–15), test (3–5), complexity and follow-ups (2–5).
2. Problem solving (clarify, brute force, optimise), coding (code), verification (test), communication (all steps, especially narrating plans and responding to hints).
3. It proves understanding, sets a baseline to beat, and its waste usually points to the optimisation. It also gives you a fallback if time runs out.
4. $O(n \log n)$ or $O(n)$ (about $10^6$–$10^7$ operations). Sorting, hashing, two pointers, heaps, binary search, linear DP.
5. Summarise what you have and what is missing, try the pattern questions (sorted? subarray? all combinations? minimum steps?), try a special case, and ask for a hint if nothing moves.
6. Trace one normal example through the actual code with concrete variable values, then edge cases (empty, one element, duplicates, negatives, extremes), fixing any bug found and re-tracing the fix.

</details>
