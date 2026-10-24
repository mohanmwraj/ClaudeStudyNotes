# LeetCode Master List (Grind 75/169, Blind 75, NeetCode 150/250, Top Interview 150)

> **Band:** 🟢–🟣 (interview level) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [README](README.md), [interview framework](01-interview-framework-and-communication.md)
> **You can say you know this when:** you have solved every `G75` problem below without hints, can name the pattern of any problem in this list within a minute, and have re-solved each one at least once after a gap of a week or more.

This is every problem from five widely used interview lists, merged, de-duplicated (**335 distinct problems**), validated against the kit's LeetCode table (exact numbers, titles, slugs, difficulties, 🔒 for Premium), and filed under the pattern file of this folder that teaches it. Each line has a checkbox, so this file doubles as a progress tracker.

## 1. Sources (fetched 23 Oct 2026)

Every badge below comes from a list that was **downloaded and parsed on 23 Oct 2026**, not from memory. Lists change over time, so treat the counts as a dated snapshot.

| Badge | List | Where the data came from | Count |
|---|---|---|---|
| `G75` / `G169` | **Grind 75 / Grind 169** by Yangshun Tay (the author of Blind 75) | The Grind 75 page <https://www.techinterviewhandbook.org/grind75/> (served from <https://grind75.pages.dev> through the proxy `apps/website/functions/grind75/[[catchall]].js` in <https://github.com/yangshun/tech-interview-handbook>). Its JavaScript bundle embeds the full 169-question dataset. The "Grind 75" core was reproduced with the site's own selection rule from the same bundle: questions sorted by `priority`, taken while the budget of 8 weeks × 8 hours (the default settings) is not exceeded, where each question costs 1.96 × its listed duration. Exactly 75 questions come out. | 169 / 75 |
| `B75` | **Blind 75** | The LeetCode list `xi4ci4ig` (<https://leetcode.com/problem-list/xi4ci4ig/>), which the author links as "The Blind 75 questions as a LeetCode list" on <https://www.techinterviewhandbook.org/best-practice-questions/> (source file `apps/website/contents/best-practice-questions.md` in the same repo). Fetched through LeetCode's public GraphQL endpoint (`favoriteQuestionList`). | 76 |
| `NC150` / `NC250` | **NeetCode 150 / NeetCode 250** | The problem table embedded in the <https://neetcode.io/practice> JavaScript bundle (per-problem flags `neetcode150` and `neetcode250`). NeetCode 150 was cross-checked against `.problemSiteData.json` in <https://github.com/neetcode-gh/leetcode>: the same 150 problems. | 150 / 250 |
| `TI150` | **LeetCode Top Interview 150** | LeetCode's study plan <https://leetcode.com/studyplan/top-interview-150/>, fetched through the GraphQL query `studyPlanV2Detail(planSlug: "top-interview-150")`: 150 problems in 23 groups. | 150 |

Not used: the freeCodeCamp article by the same author (<https://www.freecodecamp.org/news/coding-interviews-for-dummies-5e048933b82b/>), from which Blind 75 was originally extracted. Its current practice lists differ from the LeetCode list (they add Math and Recursion sections and use Combination Sum IV and Serialize/Deserialize Binary Tree), so the LeetCode list is the one used for `B75`.

### Legend

- `G75` = in the Grind 75 core, and therefore also in Grind 169. `G169` = in Grind 169 but **not** in the core 75.
- `B75` = in the author's Blind 75 LeetCode list.
- `NC150` = in NeetCode 150, and therefore also in NeetCode 250. `NC250` = in NeetCode 250 but **not** in the 150.
- `TI150` = in LeetCode Top Interview 150.
- 🔒 = LeetCode Premium (from the kit's LeetCode table). Difficulty labels are LeetCode's current ones from the same table.

## 2. What the lists agree and disagree on

| Fact (from the fetched data) | Value |
|---|---|
| distinct problems across all five lists | 335 (Easy 81, Medium 205, Hard 49) |
| Premium problems among them | 13 |
| in all four "core" lists (`G75`, `B75`, `NC150`, `TI150`) | 35 |
| in at least one core list | 236 |
| in exactly one of the five lists | 130 (64 only in NeetCode 250, 37 only in Top Interview 150, 28 only in Grind 169, 1 only in Blind 75) |
| Grind 75 core by difficulty | 23 Easy, 43 Medium, 9 Hard |
| Grind 75 problems that are not in Blind 75 | 35 (e.g. LRU Cache, Trapping Rain Water, Min Stack, Rotting Oranges, Word Ladder, Time Based Key-Value Store) |
| Blind 75 problems that are not in Grind 169 | 6: House Robber II, Top K Frequent Elements, Sum of Two Integers, Serialize and Deserialize BST, Palindromic Substrings, Longest Common Subsequence |
| overlap of Blind 75 and NeetCode 150 | 74 of 76 |

**The two "Blind 75" variants.** The author's LeetCode list has **76** entries. NeetCode's own `blind75` flag marks 75 problems. The difference is three problems: the LeetCode list includes [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium and [LC 449 · Serialize and Deserialize BST](https://leetcode.com/problems/serialize-and-deserialize-bst/) — Medium, and NeetCode's flag has [LC 297 · Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) — Hard instead. This file uses the author's list for `B75`. LC 297 is in Grind 75 and NeetCode 150 anyway, so nothing is lost.

**Opinion, not data:** on his best-practice-questions page the author calls the return on investment of DP practice very low, while noting that companies like Google still ask DP questions. This kit treats DP as required, because the CP roadmap covers it in depth anyway.

## 3. Coverage summary

Counts per pattern file of this folder. A problem appears in exactly one pattern (the one whose technique the expected solution uses). Problems the lists file under "arrays" but solve with two pointers are counted under two pointers, and so on. The pattern assignment was made for this kit, starting from NeetCode's categories where available, then Top Interview 150's groups, then Grind's topics, with manual corrections.

| File | Pattern | Total | Easy | Medium | Hard | G75 | G169 | B75 | NC150 | NC250 | TI150 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| [02](02-arrays-hashing-and-prefix-sums.md) | Arrays, hashing and prefix sums | 31 | 13 | 15 | 3 | 8 | 18 | 7 | 8 | 17 | 17 |
| [03](03-two-pointers-and-sliding-window.md) | Two pointers and sliding window | 30 | 13 | 14 | 3 | 9 | 15 | 7 | 10 | 22 | 17 |
| [04](04-stacks-and-monotonic-stacks.md) | Stacks and monotonic stacks | 16 | 4 | 8 | 4 | 5 | 11 | 1 | 6 | 13 | 4 |
| [05](05-binary-search.md) | Binary search | 18 | 5 | 10 | 3 | 3 | 8 | 2 | 6 | 14 | 8 |
| [06](06-linked-lists.md) | Linked lists | 19 | 5 | 13 | 1 | 4 | 14 | 5 | 9 | 11 | 11 |
| [07](07-trees-and-bst.md) | Trees and BST | 41 | 14 | 25 | 2 | 12 | 23 | 12 | 15 | 23 | 22 |
| [08](08-tries.md) | Tries | 4 | 0 | 3 | 1 | 1 | 3 | 3 | 3 | 4 | 3 |
| [09](09-heaps-and-top-k.md) | Heaps and top-k | 15 | 2 | 9 | 4 | 4 | 7 | 3 | 8 | 12 | 5 |
| [10](10-backtracking.md) | Backtracking | 18 | 1 | 13 | 4 | 5 | 8 | 2 | 10 | 17 | 7 |
| [11](11-graphs.md) | Graphs | 25 | 3 | 22 | 0 | 8 | 14 | 6 | 12 | 19 | 8 |
| [12](12-advanced-graphs.md) | Advanced graphs | 12 | 0 | 4 | 8 | 1 | 4 | 1 | 7 | 11 | 1 |
| [13](13-dynamic-programming-1d.md) | Dynamic programming (1D) | 20 | 3 | 15 | 2 | 6 | 11 | 11 | 12 | 18 | 9 |
| [14](14-dynamic-programming-2d.md) | Dynamic programming (2D) | 20 | 0 | 14 | 6 | 2 | 4 | 2 | 12 | 17 | 7 |
| [15](15-greedy-and-intervals.md) | Greedy and intervals | 25 | 3 | 18 | 4 | 2 | 9 | 6 | 13 | 21 | 9 |
| [16](16-math-geometry-and-bit-manipulation.md) | Math, geometry and bit manipulation | 28 | 13 | 14 | 1 | 2 | 13 | 8 | 15 | 22 | 18 |
| [17](17-design-problems.md) | Design problems | 13 | 2 | 8 | 3 | 3 | 7 | 0 | 4 | 9 | 4 |
| **All** | | **335** | **81** | **205** | **49** | **75** | **169** | **76** | **150** | **250** | **150** |

The list columns count membership: the `G169` column includes the 75 core problems and the `NC250` column includes the NeetCode 150 (unlike the badges, which show only the more specific of each pair).

## 4. Grind 75 in the site's default 8-week schedule

Reproduced from the selection and scheduling code in the Grind 75 bundle (default settings: 8 weeks, 8 hours per week, all topics and difficulties, ordered by difficulty, grouped by week). Minutes are Grind's suggested time per problem. Grind's own difficulty field differs from LeetCode's current label for a few problems (for example it calls LC 235 Easy), so the order inside a week can look slightly out of step with the labels shown. Use this as the default sprint order in the [preparation plan](20-faang-preparation-plan.md).

**Week 1** (13 problems)

- [ ] [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy · 15 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 20 · Valid Parentheses](https://leetcode.com/problems/valid-parentheses/) — Easy · 20 min · pattern [04](04-stacks-and-monotonic-stacks.md)
- [ ] [LC 21 · Merge Two Sorted Lists](https://leetcode.com/problems/merge-two-sorted-lists/) — Easy · 20 min · pattern [06](06-linked-lists.md)
- [ ] [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy · 20 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 125 · Valid Palindrome](https://leetcode.com/problems/valid-palindrome/) — Easy · 15 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 226 · Invert Binary Tree](https://leetcode.com/problems/invert-binary-tree/) — Easy · 15 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 242 · Valid Anagram](https://leetcode.com/problems/valid-anagram/) — Easy · 15 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 704 · Binary Search](https://leetcode.com/problems/binary-search/) — Easy · 15 min · pattern [05](05-binary-search.md)
- [ ] [LC 733 · Flood Fill](https://leetcode.com/problems/flood-fill/) — Easy · 20 min · pattern [11](11-graphs.md)
- [ ] [LC 235 · Lowest Common Ancestor of a Binary Search Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-search-tree/) — Medium · 20 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 110 · Balanced Binary Tree](https://leetcode.com/problems/balanced-binary-tree/) — Easy · 15 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy · 20 min · pattern [06](06-linked-lists.md)
- [ ] [LC 232 · Implement Queue using Stacks](https://leetcode.com/problems/implement-queue-using-stacks/) — Easy · 20 min · pattern [04](04-stacks-and-monotonic-stacks.md)

**Week 2** (12 problems)

- [ ] [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy · 20 min · pattern [05](05-binary-search.md)
- [ ] [LC 383 · Ransom Note](https://leetcode.com/problems/ransom-note/) — Easy · 15 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy · 20 min · pattern [13](13-dynamic-programming-1d.md)
- [ ] [LC 409 · Longest Palindrome](https://leetcode.com/problems/longest-palindrome/) — Easy · 20 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 206 · Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/) — Easy · 20 min · pattern [06](06-linked-lists.md)
- [ ] [LC 169 · Majority Element](https://leetcode.com/problems/majority-element/) — Easy · 20 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 67 · Add Binary](https://leetcode.com/problems/add-binary/) — Easy · 15 min · pattern [16](16-math-geometry-and-bit-manipulation.md)
- [ ] [LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy · 30 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 876 · Middle of the Linked List](https://leetcode.com/problems/middle-of-the-linked-list/) — Easy · 20 min · pattern [06](06-linked-lists.md)
- [ ] [LC 104 · Maximum Depth of Binary Tree](https://leetcode.com/problems/maximum-depth-of-binary-tree/) — Easy · 15 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 217 · Contains Duplicate](https://leetcode.com/problems/contains-duplicate/) — Easy · 15 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 53 · Maximum Subarray](https://leetcode.com/problems/maximum-subarray/) — Medium · 20 min · pattern [13](13-dynamic-programming-1d.md)

**Week 3** (8 problems)

- [ ] [LC 57 · Insert Interval](https://leetcode.com/problems/insert-interval/) — Medium · 25 min · pattern [15](15-greedy-and-intervals.md)
- [ ] [LC 542 · 01 Matrix](https://leetcode.com/problems/01-matrix/) — Medium · 30 min · pattern [11](11-graphs.md)
- [ ] [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium · 30 min · pattern [09](09-heaps-and-top-k.md)
- [ ] [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium · 30 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium · 30 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 102 · Binary Tree Level Order Traversal](https://leetcode.com/problems/binary-tree-level-order-traversal/) — Medium · 20 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 133 · Clone Graph](https://leetcode.com/problems/clone-graph/) — Medium · 25 min · pattern [11](11-graphs.md)
- [ ] [LC 150 · Evaluate Reverse Polish Notation](https://leetcode.com/problems/evaluate-reverse-polish-notation/) — Medium · 30 min · pattern [04](04-stacks-and-monotonic-stacks.md)

**Week 4** (8 problems)

- [ ] [LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium · 30 min · pattern [11](11-graphs.md)
- [ ] [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium · 35 min · pattern [08](08-tries.md)
- [ ] [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium · 25 min · pattern [13](13-dynamic-programming-1d.md)
- [ ] [LC 238 · Product of Array Except Self](https://leetcode.com/problems/product-of-array-except-self/) — Medium · 30 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 155 · Min Stack](https://leetcode.com/problems/min-stack/) — Medium · 20 min · pattern [17](17-design-problems.md)
- [ ] [LC 98 · Validate Binary Search Tree](https://leetcode.com/problems/validate-binary-search-tree/) — Medium · 20 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 200 · Number of Islands](https://leetcode.com/problems/number-of-islands/) — Medium · 25 min · pattern [11](11-graphs.md)
- [ ] [LC 994 · Rotting Oranges](https://leetcode.com/problems/rotting-oranges/) — Medium · 30 min · pattern [11](11-graphs.md)

**Week 5** (8 problems)

- [ ] [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium · 30 min · pattern [05](05-binary-search.md)
- [ ] [LC 39 · Combination Sum](https://leetcode.com/problems/combination-sum/) — Medium · 30 min · pattern [10](10-backtracking.md)
- [ ] [LC 46 · Permutations](https://leetcode.com/problems/permutations/) — Medium · 30 min · pattern [10](10-backtracking.md)
- [ ] [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium · 30 min · pattern [15](15-greedy-and-intervals.md)
- [ ] [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium · 25 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium · 35 min · pattern [17](17-design-problems.md)
- [ ] [LC 721 · Accounts Merge](https://leetcode.com/problems/accounts-merge/) — Medium · 30 min · pattern [11](11-graphs.md)
- [ ] [LC 75 · Sort Colors](https://leetcode.com/problems/sort-colors/) — Medium · 25 min · pattern [03](03-two-pointers-and-sliding-window.md)

**Week 6** (9 problems)

- [ ] [LC 139 · Word Break](https://leetcode.com/problems/word-break/) — Medium · 30 min · pattern [13](13-dynamic-programming-1d.md)
- [ ] [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium · 30 min · pattern [14](14-dynamic-programming-2d.md)
- [ ] [LC 8 · String to Integer (atoi)](https://leetcode.com/problems/string-to-integer-atoi/) — Medium · 25 min · pattern [02](02-arrays-hashing-and-prefix-sums.md)
- [ ] [LC 54 · Spiral Matrix](https://leetcode.com/problems/spiral-matrix/) — Medium · 25 min · pattern [16](16-math-geometry-and-bit-manipulation.md)
- [ ] [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium · 30 min · pattern [10](10-backtracking.md)
- [ ] [LC 199 · Binary Tree Right Side View](https://leetcode.com/problems/binary-tree-right-side-view/) — Medium · 20 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium · 25 min · pattern [13](13-dynamic-programming-1d.md)
- [ ] [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium · 20 min · pattern [14](14-dynamic-programming-2d.md)
- [ ] [LC 105 · Construct Binary Tree from Preorder and Inorder Traversal](https://leetcode.com/problems/construct-binary-tree-from-preorder-and-inorder-traversal/) — Medium · 25 min · pattern [07](07-trees-and-bst.md)

**Week 7** (7 problems)

- [ ] [LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium · 35 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 17 · Letter Combinations of a Phone Number](https://leetcode.com/problems/letter-combinations-of-a-phone-number/) — Medium · 30 min · pattern [10](10-backtracking.md)
- [ ] [LC 79 · Word Search](https://leetcode.com/problems/word-search/) — Medium · 30 min · pattern [10](10-backtracking.md)
- [ ] [LC 438 · Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/) — Medium · 30 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium · 30 min · pattern [11](11-graphs.md)
- [ ] [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium · 35 min · pattern [09](09-heaps-and-top-k.md)
- [ ] [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium · 30 min · pattern [17](17-design-problems.md)

**Week 8** (10 problems)

- [ ] [LC 230 · Kth Smallest Element in a BST](https://leetcode.com/problems/kth-smallest-element-in-a-bst/) — Medium · 25 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard · 30 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 297 · Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) — Hard · 40 min · pattern [07](07-trees-and-bst.md)
- [ ] [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard · 35 min · pattern [03](03-two-pointers-and-sliding-window.md)
- [ ] [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard · 30 min · pattern [09](09-heaps-and-top-k.md)
- [ ] [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard · 45 min · pattern [12](12-advanced-graphs.md)
- [ ] [LC 224 · Basic Calculator](https://leetcode.com/problems/basic-calculator/) — Hard · 40 min · pattern [04](04-stacks-and-monotonic-stacks.md)
- [ ] [LC 1235 · Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/) — Hard · 45 min · pattern [13](13-dynamic-programming-1d.md)
- [ ] [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard · 30 min · pattern [09](09-heaps-and-top-k.md)
- [ ] [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard · 35 min · pattern [04](04-stacks-and-monotonic-stacks.md)

## 5. All 335 problems by pattern

Inside each pattern: Easy, then Medium, then Hard, each by problem number.

### 02 · Arrays, hashing and prefix sums (31)

Pattern file: [02-arrays-hashing-and-prefix-sums.md](02-arrays-hashing-and-prefix-sums.md)

**Easy**

- [ ] [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 14 · Longest Common Prefix](https://leetcode.com/problems/longest-common-prefix/) — Easy · `G169` `NC250` `TI150`
- [ ] [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy · `TI150`
- [ ] [LC 58 · Length of Last Word](https://leetcode.com/problems/length-of-last-word/) — Easy · `TI150`
- [ ] [LC 169 · Majority Element](https://leetcode.com/problems/majority-element/) — Easy · `G75` `NC250` `TI150`
- [ ] [LC 205 · Isomorphic Strings](https://leetcode.com/problems/isomorphic-strings/) — Easy · `TI150`
- [ ] [LC 217 · Contains Duplicate](https://leetcode.com/problems/contains-duplicate/) — Easy · `G75` `B75` `NC150`
- [ ] [LC 242 · Valid Anagram](https://leetcode.com/problems/valid-anagram/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 290 · Word Pattern](https://leetcode.com/problems/word-pattern/) — Easy · `TI150`
- [ ] [LC 383 · Ransom Note](https://leetcode.com/problems/ransom-note/) — Easy · `G75` `TI150`
- [ ] [LC 409 · Longest Palindrome](https://leetcode.com/problems/longest-palindrome/) — Easy · `G75`
- [ ] [LC 953 · Verifying an Alien Dictionary](https://leetcode.com/problems/verifying-an-alien-dictionary/) — Easy · `NC250`
- [ ] [LC 1929 · Concatenation of Array](https://leetcode.com/problems/concatenation-of-array/) — Easy · `NC250`

**Medium**

- [ ] [LC 6 · Zigzag Conversion](https://leetcode.com/problems/zigzag-conversion/) — Medium · `TI150`
- [ ] [LC 8 · String to Integer (atoi)](https://leetcode.com/problems/string-to-integer-atoi/) — Medium · `G75`
- [ ] [LC 31 · Next Permutation](https://leetcode.com/problems/next-permutation/) — Medium · `G169`
- [ ] [LC 36 · Valid Sudoku](https://leetcode.com/problems/valid-sudoku/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 128 · Longest Consecutive Sequence](https://leetcode.com/problems/longest-consecutive-sequence/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 151 · Reverse Words in a String](https://leetcode.com/problems/reverse-words-in-a-string/) — Medium · `TI150`
- [ ] [LC 229 · Majority Element II](https://leetcode.com/problems/majority-element-ii/) — Medium · `NC250`
- [ ] [LC 238 · Product of Array Except Self](https://leetcode.com/problems/product-of-array-except-self/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 271 · Encode and Decode Strings](https://leetcode.com/problems/encode-and-decode-strings/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 274 · H-Index](https://leetcode.com/problems/h-index/) — Medium · `TI150`
- [ ] [LC 304 · Range Sum Query 2D - Immutable](https://leetcode.com/problems/range-sum-query-2d-immutable/) — Medium · `NC250`
- [ ] [LC 525 · Contiguous Array](https://leetcode.com/problems/contiguous-array/) — Medium · `G169`
- [ ] [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium · `G169` `NC250`
- [ ] [LC 912 · Sort an Array](https://leetcode.com/problems/sort-an-array/) — Medium · `NC250`

**Hard**

- [ ] [LC 41 · First Missing Positive](https://leetcode.com/problems/first-missing-positive/) — Hard · `G169` `NC250`
- [ ] [LC 68 · Text Justification](https://leetcode.com/problems/text-justification/) — Hard · `TI150`
- [ ] [LC 336 · Palindrome Pairs](https://leetcode.com/problems/palindrome-pairs/) — Hard · `G169`

### 03 · Two pointers and sliding window (30)

Pattern file: [03-two-pointers-and-sliding-window.md](03-two-pointers-and-sliding-window.md)

**Easy**

- [ ] [LC 26 · Remove Duplicates from Sorted Array](https://leetcode.com/problems/remove-duplicates-from-sorted-array/) — Easy · `NC250` `TI150`
- [ ] [LC 27 · Remove Element](https://leetcode.com/problems/remove-element/) — Easy · `NC250` `TI150`
- [ ] [LC 88 · Merge Sorted Array](https://leetcode.com/problems/merge-sorted-array/) — Easy · `NC250` `TI150`
- [ ] [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 125 · Valid Palindrome](https://leetcode.com/problems/valid-palindrome/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 219 · Contains Duplicate II](https://leetcode.com/problems/contains-duplicate-ii/) — Easy · `NC250` `TI150`
- [ ] [LC 283 · Move Zeroes](https://leetcode.com/problems/move-zeroes/) — Easy · `G169`
- [ ] [LC 344 · Reverse String](https://leetcode.com/problems/reverse-string/) — Easy · `NC250`
- [ ] [LC 392 · Is Subsequence](https://leetcode.com/problems/is-subsequence/) — Easy · `TI150`
- [ ] [LC 680 · Valid Palindrome II](https://leetcode.com/problems/valid-palindrome-ii/) — Easy · `NC250`
- [ ] [LC 844 · Backspace String Compare](https://leetcode.com/problems/backspace-string-compare/) — Easy · `G169`
- [ ] [LC 977 · Squares of a Sorted Array](https://leetcode.com/problems/squares-of-a-sorted-array/) — Easy · `G169`
- [ ] [LC 1768 · Merge Strings Alternately](https://leetcode.com/problems/merge-strings-alternately/) — Easy · `NC250`

**Medium**

- [ ] [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 16 · 3Sum Closest](https://leetcode.com/problems/3sum-closest/) — Medium · `G169`
- [ ] [LC 18 · 4Sum](https://leetcode.com/problems/4sum/) — Medium · `NC250`
- [ ] [LC 75 · Sort Colors](https://leetcode.com/problems/sort-colors/) — Medium · `G75` `NC250`
- [ ] [LC 80 · Remove Duplicates from Sorted Array II](https://leetcode.com/problems/remove-duplicates-from-sorted-array-ii/) — Medium · `TI150`
- [ ] [LC 167 · Two Sum II - Input Array Is Sorted](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/) — Medium · `NC150` `TI150`
- [ ] [LC 189 · Rotate Array](https://leetcode.com/problems/rotate-array/) — Medium · `G169` `NC250` `TI150`
- [ ] [LC 209 · Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/) — Medium · `NC250` `TI150`
- [ ] [LC 424 · Longest Repeating Character Replacement](https://leetcode.com/problems/longest-repeating-character-replacement/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 438 · Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/) — Medium · `G75`
- [ ] [LC 567 · Permutation in String](https://leetcode.com/problems/permutation-in-string/) — Medium · `NC150`
- [ ] [LC 881 · Boats to Save People](https://leetcode.com/problems/boats-to-save-people/) — Medium · `NC250`

**Hard**

- [ ] [LC 30 · Substring with Concatenation of All Words](https://leetcode.com/problems/substring-with-concatenation-of-all-words/) — Hard · `TI150`
- [ ] [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard · `G75` `NC150` `TI150`
- [ ] [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard · `G75` `B75` `NC150` `TI150`

### 04 · Stacks and monotonic stacks (16)

Pattern file: [04-stacks-and-monotonic-stacks.md](04-stacks-and-monotonic-stacks.md)

**Easy**

- [ ] [LC 20 · Valid Parentheses](https://leetcode.com/problems/valid-parentheses/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 225 · Implement Stack using Queues](https://leetcode.com/problems/implement-stack-using-queues/) — Easy · `NC250`
- [ ] [LC 232 · Implement Queue using Stacks](https://leetcode.com/problems/implement-queue-using-stacks/) — Easy · `G75` `NC250`
- [ ] [LC 682 · Baseball Game](https://leetcode.com/problems/baseball-game/) — Easy · `NC250`

**Medium**

- [ ] [LC 71 · Simplify Path](https://leetcode.com/problems/simplify-path/) — Medium · `NC250` `TI150`
- [ ] [LC 150 · Evaluate Reverse Polish Notation](https://leetcode.com/problems/evaluate-reverse-polish-notation/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 227 · Basic Calculator II](https://leetcode.com/problems/basic-calculator-ii/) — Medium · `G169`
- [ ] [LC 394 · Decode String](https://leetcode.com/problems/decode-string/) — Medium · `G169` `NC250`
- [ ] [LC 735 · Asteroid Collision](https://leetcode.com/problems/asteroid-collision/) — Medium · `G169` `NC250`
- [ ] [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium · `G169` `NC150`
- [ ] [LC 853 · Car Fleet](https://leetcode.com/problems/car-fleet/) — Medium · `NC150`
- [ ] [LC 901 · Online Stock Span](https://leetcode.com/problems/online-stock-span/) — Medium · `NC250`

**Hard**

- [ ] [LC 32 · Longest Valid Parentheses](https://leetcode.com/problems/longest-valid-parentheses/) — Hard · `G169`
- [ ] [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard · `G75` `NC150`
- [ ] [LC 224 · Basic Calculator](https://leetcode.com/problems/basic-calculator/) — Hard · `G75` `TI150`
- [ ] [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard · `G169` `NC150`

### 05 · Binary search (18)

Pattern file: [05-binary-search.md](05-binary-search.md)

**Easy**

- [ ] [LC 35 · Search Insert Position](https://leetcode.com/problems/search-insert-position/) — Easy · `NC250` `TI150`
- [ ] [LC 69 · Sqrt(x)](https://leetcode.com/problems/sqrtx/) — Easy · `NC250` `TI150`
- [ ] [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy · `G75`
- [ ] [LC 374 · Guess Number Higher or Lower](https://leetcode.com/problems/guess-number-higher-or-lower/) — Easy · `NC250`
- [ ] [LC 704 · Binary Search](https://leetcode.com/problems/binary-search/) — Easy · `G75` `NC150`

**Medium**

- [ ] [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 34 · Find First and Last Position of Element in Sorted Array](https://leetcode.com/problems/find-first-and-last-position-of-element-in-sorted-array/) — Medium · `TI150`
- [ ] [LC 74 · Search a 2D Matrix](https://leetcode.com/problems/search-a-2d-matrix/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 81 · Search in Rotated Sorted Array II](https://leetcode.com/problems/search-in-rotated-sorted-array-ii/) — Medium · `NC250`
- [ ] [LC 153 · Find Minimum in Rotated Sorted Array](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium · `TI150`
- [ ] [LC 528 · Random Pick with Weight](https://leetcode.com/problems/random-pick-with-weight/) — Medium · `G169`
- [ ] [LC 658 · Find K Closest Elements](https://leetcode.com/problems/find-k-closest-elements/) — Medium · `G169` `NC250`
- [ ] [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium · `NC150`
- [ ] [LC 1011 · Capacity To Ship Packages Within D Days](https://leetcode.com/problems/capacity-to-ship-packages-within-d-days/) — Medium · `NC250`

**Hard**

- [ ] [LC 4 · Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) — Hard · `G169` `NC150` `TI150`
- [ ] [LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard · `NC250`
- [ ] [LC 1095 · Find in Mountain Array](https://leetcode.com/problems/find-in-mountain-array/) — Hard · `NC250`

### 06 · Linked lists (19)

Pattern file: [06-linked-lists.md](06-linked-lists.md)

**Easy**

- [ ] [LC 21 · Merge Two Sorted Lists](https://leetcode.com/problems/merge-two-sorted-lists/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 206 · Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/) — Easy · `G75` `B75` `NC150`
- [ ] [LC 234 · Palindrome Linked List](https://leetcode.com/problems/palindrome-linked-list/) — Easy · `G169`
- [ ] [LC 876 · Middle of the Linked List](https://leetcode.com/problems/middle-of-the-linked-list/) — Easy · `G75`

**Medium**

- [ ] [LC 2 · Add Two Numbers](https://leetcode.com/problems/add-two-numbers/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 19 · Remove Nth Node From End of List](https://leetcode.com/problems/remove-nth-node-from-end-of-list/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 24 · Swap Nodes in Pairs](https://leetcode.com/problems/swap-nodes-in-pairs/) — Medium · `G169`
- [ ] [LC 61 · Rotate List](https://leetcode.com/problems/rotate-list/) — Medium · `G169` `TI150`
- [ ] [LC 82 · Remove Duplicates from Sorted List II](https://leetcode.com/problems/remove-duplicates-from-sorted-list-ii/) — Medium · `TI150`
- [ ] [LC 86 · Partition List](https://leetcode.com/problems/partition-list/) — Medium · `TI150`
- [ ] [LC 92 · Reverse Linked List II](https://leetcode.com/problems/reverse-linked-list-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 138 · Copy List with Random Pointer](https://leetcode.com/problems/copy-list-with-random-pointer/) — Medium · `NC150` `TI150`
- [ ] [LC 143 · Reorder List](https://leetcode.com/problems/reorder-list/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 148 · Sort List](https://leetcode.com/problems/sort-list/) — Medium · `G169` `TI150`
- [ ] [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium · `G169` `NC150`
- [ ] [LC 328 · Odd Even Linked List](https://leetcode.com/problems/odd-even-linked-list/) — Medium · `G169`
- [ ] [LC 2807 · Insert Greatest Common Divisors in Linked List](https://leetcode.com/problems/insert-greatest-common-divisors-in-linked-list/) — Medium · `NC250`

**Hard**

- [ ] [LC 25 · Reverse Nodes in k-Group](https://leetcode.com/problems/reverse-nodes-in-k-group/) — Hard · `G169` `NC150` `TI150`

### 07 · Trees and BST (41)

Pattern file: [07-trees-and-bst.md](07-trees-and-bst.md)

**Easy**

- [ ] [LC 94 · Binary Tree Inorder Traversal](https://leetcode.com/problems/binary-tree-inorder-traversal/) — Easy · `NC250`
- [ ] [LC 100 · Same Tree](https://leetcode.com/problems/same-tree/) — Easy · `G169` `B75` `NC150` `TI150`
- [ ] [LC 101 · Symmetric Tree](https://leetcode.com/problems/symmetric-tree/) — Easy · `G169` `TI150`
- [ ] [LC 104 · Maximum Depth of Binary Tree](https://leetcode.com/problems/maximum-depth-of-binary-tree/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 108 · Convert Sorted Array to Binary Search Tree](https://leetcode.com/problems/convert-sorted-array-to-binary-search-tree/) — Easy · `G169` `TI150`
- [ ] [LC 110 · Balanced Binary Tree](https://leetcode.com/problems/balanced-binary-tree/) — Easy · `G75` `NC150`
- [ ] [LC 112 · Path Sum](https://leetcode.com/problems/path-sum/) — Easy · `TI150`
- [ ] [LC 144 · Binary Tree Preorder Traversal](https://leetcode.com/problems/binary-tree-preorder-traversal/) — Easy · `NC250`
- [ ] [LC 145 · Binary Tree Postorder Traversal](https://leetcode.com/problems/binary-tree-postorder-traversal/) — Easy · `NC250`
- [ ] [LC 226 · Invert Binary Tree](https://leetcode.com/problems/invert-binary-tree/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 530 · Minimum Absolute Difference in BST](https://leetcode.com/problems/minimum-absolute-difference-in-bst/) — Easy · `TI150`
- [ ] [LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy · `G75` `NC150`
- [ ] [LC 572 · Subtree of Another Tree](https://leetcode.com/problems/subtree-of-another-tree/) — Easy · `G169` `B75` `NC150`
- [ ] [LC 637 · Average of Levels in Binary Tree](https://leetcode.com/problems/average-of-levels-in-binary-tree/) — Easy · `TI150`

**Medium**

- [ ] [LC 98 · Validate Binary Search Tree](https://leetcode.com/problems/validate-binary-search-tree/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 102 · Binary Tree Level Order Traversal](https://leetcode.com/problems/binary-tree-level-order-traversal/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 103 · Binary Tree Zigzag Level Order Traversal](https://leetcode.com/problems/binary-tree-zigzag-level-order-traversal/) — Medium · `G169` `TI150`
- [ ] [LC 105 · Construct Binary Tree from Preorder and Inorder Traversal](https://leetcode.com/problems/construct-binary-tree-from-preorder-and-inorder-traversal/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 106 · Construct Binary Tree from Inorder and Postorder Traversal](https://leetcode.com/problems/construct-binary-tree-from-inorder-and-postorder-traversal/) — Medium · `TI150`
- [ ] [LC 113 · Path Sum II](https://leetcode.com/problems/path-sum-ii/) — Medium · `G169`
- [ ] [LC 114 · Flatten Binary Tree to Linked List](https://leetcode.com/problems/flatten-binary-tree-to-linked-list/) — Medium · `TI150`
- [ ] [LC 117 · Populating Next Right Pointers in Each Node II](https://leetcode.com/problems/populating-next-right-pointers-in-each-node-ii/) — Medium · `TI150`
- [ ] [LC 129 · Sum Root to Leaf Numbers](https://leetcode.com/problems/sum-root-to-leaf-numbers/) — Medium · `TI150`
- [ ] [LC 199 · Binary Tree Right Side View](https://leetcode.com/problems/binary-tree-right-side-view/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 222 · Count Complete Tree Nodes](https://leetcode.com/problems/count-complete-tree-nodes/) — Medium · `TI150`
- [ ] [LC 230 · Kth Smallest Element in a BST](https://leetcode.com/problems/kth-smallest-element-in-a-bst/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 235 · Lowest Common Ancestor of a Binary Search Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-search-tree/) — Medium · `G75` `B75` `NC150`
- [ ] [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium · `G75` `B75` `TI150`
- [ ] [LC 285 · Inorder Successor in BST](https://leetcode.com/problems/inorder-successor-in-bst/) — Medium 🔒 · `G169`
- [ ] [LC 337 · House Robber III](https://leetcode.com/problems/house-robber-iii/) — Medium · `NC250`
- [ ] [LC 427 · Construct Quad Tree](https://leetcode.com/problems/construct-quad-tree/) — Medium · `NC250` `TI150`
- [ ] [LC 437 · Path Sum III](https://leetcode.com/problems/path-sum-iii/) — Medium · `G169`
- [ ] [LC 449 · Serialize and Deserialize BST](https://leetcode.com/problems/serialize-and-deserialize-bst/) — Medium · `B75`
- [ ] [LC 450 · Delete Node in a BST](https://leetcode.com/problems/delete-node-in-a-bst/) — Medium · `NC250`
- [ ] [LC 662 · Maximum Width of Binary Tree](https://leetcode.com/problems/maximum-width-of-binary-tree/) — Medium · `G169`
- [ ] [LC 701 · Insert into a Binary Search Tree](https://leetcode.com/problems/insert-into-a-binary-search-tree/) — Medium · `NC250`
- [ ] [LC 863 · All Nodes Distance K in Binary Tree](https://leetcode.com/problems/all-nodes-distance-k-in-binary-tree/) — Medium · `G169`
- [ ] [LC 1325 · Delete Leaves With a Given Value](https://leetcode.com/problems/delete-leaves-with-a-given-value/) — Medium · `NC250`
- [ ] [LC 1448 · Count Good Nodes in Binary Tree](https://leetcode.com/problems/count-good-nodes-in-binary-tree/) — Medium · `NC150`

**Hard**

- [ ] [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard · `G169` `B75` `NC150` `TI150`
- [ ] [LC 297 · Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) — Hard · `G75` `NC150`

### 08 · Tries (4)

Pattern file: [08-tries.md](08-tries.md)

**Medium**

- [ ] [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 211 · Design Add and Search Words Data Structure](https://leetcode.com/problems/design-add-and-search-words-data-structure/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 2707 · Extra Characters in a String](https://leetcode.com/problems/extra-characters-in-a-string/) — Medium · `NC250`

**Hard**

- [ ] [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard · `G169` `B75` `NC150` `TI150`

### 09 · Heaps and top-k (15)

Pattern file: [09-heaps-and-top-k.md](09-heaps-and-top-k.md)

**Easy**

- [ ] [LC 703 · Kth Largest Element in a Stream](https://leetcode.com/problems/kth-largest-element-in-a-stream/) — Easy · `NC150`
- [ ] [LC 1046 · Last Stone Weight](https://leetcode.com/problems/last-stone-weight/) — Easy · `NC150`

**Medium**

- [ ] [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium · `B75` `NC150`
- [ ] [LC 373 · Find K Pairs with Smallest Sums](https://leetcode.com/problems/find-k-pairs-with-smallest-sums/) — Medium · `TI150`
- [ ] [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium · `G75` `NC150`
- [ ] [LC 692 · Top K Frequent Words](https://leetcode.com/problems/top-k-frequent-words/) — Medium · `G169`
- [ ] [LC 767 · Reorganize String](https://leetcode.com/problems/reorganize-string/) — Medium · `NC250`
- [ ] [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium · `G75` `NC150`
- [ ] [LC 1405 · Longest Happy String](https://leetcode.com/problems/longest-happy-string/) — Medium · `NC250`
- [ ] [LC 1834 · Single-Threaded CPU](https://leetcode.com/problems/single-threaded-cpu/) — Medium · `NC250`

**Hard**

- [ ] [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard · `G75` `B75` `NC150` `TI150`
- [ ] [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard · `G75` `B75` `NC150` `TI150`
- [ ] [LC 502 · IPO](https://leetcode.com/problems/ipo/) — Hard · `NC250` `TI150`
- [ ] [LC 632 · Smallest Range Covering Elements from K Lists](https://leetcode.com/problems/smallest-range-covering-elements-from-k-lists/) — Hard · `G169`

### 10 · Backtracking (18)

Pattern file: [10-backtracking.md](10-backtracking.md)

**Easy**

- [ ] [LC 1863 · Sum of All Subset XOR Totals](https://leetcode.com/problems/sum-of-all-subset-xor-totals/) — Easy · `NC250`

**Medium**

- [ ] [LC 17 · Letter Combinations of a Phone Number](https://leetcode.com/problems/letter-combinations-of-a-phone-number/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 22 · Generate Parentheses](https://leetcode.com/problems/generate-parentheses/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 39 · Combination Sum](https://leetcode.com/problems/combination-sum/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 40 · Combination Sum II](https://leetcode.com/problems/combination-sum-ii/) — Medium · `NC150`
- [ ] [LC 46 · Permutations](https://leetcode.com/problems/permutations/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 47 · Permutations II](https://leetcode.com/problems/permutations-ii/) — Medium · `NC250`
- [ ] [LC 77 · Combinations](https://leetcode.com/problems/combinations/) — Medium · `NC250` `TI150`
- [ ] [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium · `G75` `NC150`
- [ ] [LC 79 · Word Search](https://leetcode.com/problems/word-search/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 90 · Subsets II](https://leetcode.com/problems/subsets-ii/) — Medium · `NC150`
- [ ] [LC 131 · Palindrome Partitioning](https://leetcode.com/problems/palindrome-partitioning/) — Medium · `NC150`
- [ ] [LC 473 · Matchsticks to Square](https://leetcode.com/problems/matchsticks-to-square/) — Medium · `NC250`
- [ ] [LC 698 · Partition to K Equal Sum Subsets](https://leetcode.com/problems/partition-to-k-equal-sum-subsets/) — Medium · `NC250`

**Hard**

- [ ] [LC 37 · Sudoku Solver](https://leetcode.com/problems/sudoku-solver/) — Hard · `G169`
- [ ] [LC 51 · N-Queens](https://leetcode.com/problems/n-queens/) — Hard · `G169` `NC150`
- [ ] [LC 52 · N-Queens II](https://leetcode.com/problems/n-queens-ii/) — Hard · `NC250` `TI150`
- [ ] [LC 140 · Word Break II](https://leetcode.com/problems/word-break-ii/) — Hard · `NC250`

### 11 · Graphs (25)

Pattern file: [11-graphs.md](11-graphs.md)

**Easy**

- [ ] [LC 463 · Island Perimeter](https://leetcode.com/problems/island-perimeter/) — Easy · `NC250`
- [ ] [LC 733 · Flood Fill](https://leetcode.com/problems/flood-fill/) — Easy · `G75`
- [ ] [LC 997 · Find the Town Judge](https://leetcode.com/problems/find-the-town-judge/) — Easy · `NC250`

**Medium**

- [ ] [LC 130 · Surrounded Regions](https://leetcode.com/problems/surrounded-regions/) — Medium · `NC150` `TI150`
- [ ] [LC 133 · Clone Graph](https://leetcode.com/problems/clone-graph/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 200 · Number of Islands](https://leetcode.com/problems/number-of-islands/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 210 · Course Schedule II](https://leetcode.com/problems/course-schedule-ii/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 261 · Graph Valid Tree](https://leetcode.com/problems/graph-valid-tree/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 286 · Walls and Gates](https://leetcode.com/problems/walls-and-gates/) — Medium 🔒 · `NC150`
- [ ] [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium · `G75` `NC250`
- [ ] [LC 323 · Number of Connected Components in an Undirected Graph](https://leetcode.com/problems/number-of-connected-components-in-an-undirected-graph/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 399 · Evaluate Division](https://leetcode.com/problems/evaluate-division/) — Medium · `NC250` `TI150`
- [ ] [LC 417 · Pacific Atlantic Water Flow](https://leetcode.com/problems/pacific-atlantic-water-flow/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 433 · Minimum Genetic Mutation](https://leetcode.com/problems/minimum-genetic-mutation/) — Medium · `TI150`
- [ ] [LC 542 · 01 Matrix](https://leetcode.com/problems/01-matrix/) — Medium · `G75`
- [ ] [LC 684 · Redundant Connection](https://leetcode.com/problems/redundant-connection/) — Medium · `NC150`
- [ ] [LC 695 · Max Area of Island](https://leetcode.com/problems/max-area-of-island/) — Medium · `NC150`
- [ ] [LC 721 · Accounts Merge](https://leetcode.com/problems/accounts-merge/) — Medium · `G75` `NC250`
- [ ] [LC 752 · Open the Lock](https://leetcode.com/problems/open-the-lock/) — Medium · `NC250`
- [ ] [LC 909 · Snakes and Ladders](https://leetcode.com/problems/snakes-and-ladders/) — Medium · `TI150`
- [ ] [LC 994 · Rotting Oranges](https://leetcode.com/problems/rotting-oranges/) — Medium · `G75` `NC150`
- [ ] [LC 1197 · Minimum Knight Moves](https://leetcode.com/problems/minimum-knight-moves/) — Medium 🔒 · `G169`
- [ ] [LC 1462 · Course Schedule IV](https://leetcode.com/problems/course-schedule-iv/) — Medium · `NC250`
- [ ] [LC 1730 · Shortest Path to Get Food](https://leetcode.com/problems/shortest-path-to-get-food/) — Medium 🔒 · `G169`

### 12 · Advanced graphs (12)

Pattern file: [12-advanced-graphs.md](12-advanced-graphs.md)

**Medium**

- [ ] [LC 743 · Network Delay Time](https://leetcode.com/problems/network-delay-time/) — Medium · `NC150`
- [ ] [LC 787 · Cheapest Flights Within K Stops](https://leetcode.com/problems/cheapest-flights-within-k-stops/) — Medium · `G169` `NC150`
- [ ] [LC 1584 · Min Cost to Connect All Points](https://leetcode.com/problems/min-cost-to-connect-all-points/) — Medium · `NC150`
- [ ] [LC 1631 · Path With Minimum Effort](https://leetcode.com/problems/path-with-minimum-effort/) — Medium · `NC250`

**Hard**

- [ ] [LC 127 · Word Ladder](https://leetcode.com/problems/word-ladder/) — Hard · `G75` `NC150` `TI150`
- [ ] [LC 269 · Alien Dictionary](https://leetcode.com/problems/alien-dictionary/) — Hard 🔒 · `G169` `B75` `NC150`
- [ ] [LC 332 · Reconstruct Itinerary](https://leetcode.com/problems/reconstruct-itinerary/) — Hard · `NC150`
- [ ] [LC 778 · Swim in Rising Water](https://leetcode.com/problems/swim-in-rising-water/) — Hard · `NC150`
- [ ] [LC 815 · Bus Routes](https://leetcode.com/problems/bus-routes/) — Hard · `G169`
- [ ] [LC 1489 · Find Critical and Pseudo-Critical Edges in Minimum Spanning Tree](https://leetcode.com/problems/find-critical-and-pseudo-critical-edges-in-minimum-spanning-tree/) — Hard · `NC250`
- [ ] [LC 2392 · Build a Matrix With Conditions](https://leetcode.com/problems/build-a-matrix-with-conditions/) — Hard · `NC250`
- [ ] [LC 2709 · Greatest Common Divisor Traversal](https://leetcode.com/problems/greatest-common-divisor-traversal/) — Hard · `NC250`

### 13 · Dynamic programming (1D) (20)

Pattern file: [13-dynamic-programming-1d.md](13-dynamic-programming-1d.md)

**Easy**

- [ ] [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 746 · Min Cost Climbing Stairs](https://leetcode.com/problems/min-cost-climbing-stairs/) — Easy · `NC150`
- [ ] [LC 1137 · N-th Tribonacci Number](https://leetcode.com/problems/n-th-tribonacci-number/) — Easy · `NC250`

**Medium**

- [ ] [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 53 · Maximum Subarray](https://leetcode.com/problems/maximum-subarray/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 91 · Decode Ways](https://leetcode.com/problems/decode-ways/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 120 · Triangle](https://leetcode.com/problems/triangle/) — Medium · `TI150`
- [ ] [LC 139 · Word Break](https://leetcode.com/problems/word-break/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 152 · Maximum Product Subarray](https://leetcode.com/problems/maximum-product-subarray/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 198 · House Robber](https://leetcode.com/problems/house-robber/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 213 · House Robber II](https://leetcode.com/problems/house-robber-ii/) — Medium · `B75` `NC150`
- [ ] [LC 279 · Perfect Squares](https://leetcode.com/problems/perfect-squares/) — Medium · `NC250`
- [ ] [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 343 · Integer Break](https://leetcode.com/problems/integer-break/) — Medium · `NC250`
- [ ] [LC 377 · Combination Sum IV](https://leetcode.com/problems/combination-sum-iv/) — Medium · `G169` `NC250`
- [ ] [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium · `B75` `NC150`
- [ ] [LC 918 · Maximum Sum Circular Subarray](https://leetcode.com/problems/maximum-sum-circular-subarray/) — Medium · `NC250` `TI150`

**Hard**

- [ ] [LC 1235 · Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/) — Hard · `G75`
- [ ] [LC 1406 · Stone Game III](https://leetcode.com/problems/stone-game-iii/) — Hard · `NC250`

### 14 · Dynamic programming (2D) (20)

Pattern file: [14-dynamic-programming-2d.md](14-dynamic-programming-2d.md)

**Medium**

- [ ] [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium · `G75` `B75` `NC150`
- [ ] [LC 63 · Unique Paths II](https://leetcode.com/problems/unique-paths-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 64 · Minimum Path Sum](https://leetcode.com/problems/minimum-path-sum/) — Medium · `NC250` `TI150`
- [ ] [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium · `NC150` `TI150`
- [ ] [LC 97 · Interleaving String](https://leetcode.com/problems/interleaving-string/) — Medium · `NC150` `TI150`
- [ ] [LC 221 · Maximal Square](https://leetcode.com/problems/maximal-square/) — Medium · `G169` `TI150`
- [ ] [LC 309 · Best Time to Buy and Sell Stock with Cooldown](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-with-cooldown/) — Medium · `NC150`
- [ ] [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium · `G75` `NC150`
- [ ] [LC 494 · Target Sum](https://leetcode.com/problems/target-sum/) — Medium · `NC150`
- [ ] [LC 518 · Coin Change II](https://leetcode.com/problems/coin-change-ii/) — Medium · `NC150`
- [ ] [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium · `NC250`
- [ ] [LC 1049 · Last Stone Weight II](https://leetcode.com/problems/last-stone-weight-ii/) — Medium · `NC250`
- [ ] [LC 1140 · Stone Game II](https://leetcode.com/problems/stone-game-ii/) — Medium · `NC250`
- [ ] [LC 1143 · Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/) — Medium · `B75` `NC150`

**Hard**

- [ ] [LC 10 · Regular Expression Matching](https://leetcode.com/problems/regular-expression-matching/) — Hard · `NC150`
- [ ] [LC 115 · Distinct Subsequences](https://leetcode.com/problems/distinct-subsequences/) — Hard · `NC150`
- [ ] [LC 123 · Best Time to Buy and Sell Stock III](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iii/) — Hard · `TI150`
- [ ] [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard · `TI150`
- [ ] [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard · `NC150`
- [ ] [LC 329 · Longest Increasing Path in a Matrix](https://leetcode.com/problems/longest-increasing-path-in-a-matrix/) — Hard · `G169` `NC150`

### 15 · Greedy and intervals (25)

Pattern file: [15-greedy-and-intervals.md](15-greedy-and-intervals.md)

**Easy**

- [ ] [LC 228 · Summary Ranges](https://leetcode.com/problems/summary-ranges/) — Easy · `TI150`
- [ ] [LC 252 · Meeting Rooms](https://leetcode.com/problems/meeting-rooms/) — Easy 🔒 · `G169` `B75` `NC150`
- [ ] [LC 860 · Lemonade Change](https://leetcode.com/problems/lemonade-change/) — Easy · `NC250`

**Medium**

- [ ] [LC 45 · Jump Game II](https://leetcode.com/problems/jump-game-ii/) — Medium · `NC150` `TI150`
- [ ] [LC 55 · Jump Game](https://leetcode.com/problems/jump-game/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 57 · Insert Interval](https://leetcode.com/problems/insert-interval/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 122 · Best Time to Buy and Sell Stock II](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 179 · Largest Number](https://leetcode.com/problems/largest-number/) — Medium · `G169`
- [ ] [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 435 · Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 452 · Minimum Number of Arrows to Burst Balloons](https://leetcode.com/problems/minimum-number-of-arrows-to-burst-balloons/) — Medium · `TI150`
- [ ] [LC 649 · Dota2 Senate](https://leetcode.com/problems/dota2-senate/) — Medium · `NC250`
- [ ] [LC 678 · Valid Parenthesis String](https://leetcode.com/problems/valid-parenthesis-string/) — Medium · `NC150`
- [ ] [LC 763 · Partition Labels](https://leetcode.com/problems/partition-labels/) — Medium · `NC150`
- [ ] [LC 846 · Hand of Straights](https://leetcode.com/problems/hand-of-straights/) — Medium · `NC150`
- [ ] [LC 978 · Longest Turbulent Subarray](https://leetcode.com/problems/longest-turbulent-subarray/) — Medium · `NC250`
- [ ] [LC 1094 · Car Pooling](https://leetcode.com/problems/car-pooling/) — Medium · `NC250`
- [ ] [LC 1871 · Jump Game VII](https://leetcode.com/problems/jump-game-vii/) — Medium · `NC250`
- [ ] [LC 1899 · Merge Triplets to Form Target Triplet](https://leetcode.com/problems/merge-triplets-to-form-target-triplet/) — Medium · `NC150`

**Hard**

- [ ] [LC 135 · Candy](https://leetcode.com/problems/candy/) — Hard · `NC250` `TI150`
- [ ] [LC 759 · Employee Free Time](https://leetcode.com/problems/employee-free-time/) — Hard 🔒 · `G169`
- [ ] [LC 1851 · Minimum Interval to Include Each Query](https://leetcode.com/problems/minimum-interval-to-include-each-query/) — Hard · `NC150`
- [ ] [LC 2402 · Meeting Rooms III](https://leetcode.com/problems/meeting-rooms-iii/) — Hard · `NC250`

### 16 · Math, geometry and bit manipulation (28)

Pattern file: [16-math-geometry-and-bit-manipulation.md](16-math-geometry-and-bit-manipulation.md)

**Easy**

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

**Medium**

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

**Hard**

- [ ] [LC 149 · Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/) — Hard · `TI150`

### 17 · Design problems (13)

Pattern file: [17-design-problems.md](17-design-problems.md)

**Easy**

- [ ] [LC 705 · Design HashSet](https://leetcode.com/problems/design-hashset/) — Easy · `NC250`
- [ ] [LC 706 · Design HashMap](https://leetcode.com/problems/design-hashmap/) — Easy · `NC250`

**Medium**

- [ ] [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 155 · Min Stack](https://leetcode.com/problems/min-stack/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 173 · Binary Search Tree Iterator](https://leetcode.com/problems/binary-search-tree-iterator/) — Medium · `TI150`
- [ ] [LC 355 · Design Twitter](https://leetcode.com/problems/design-twitter/) — Medium · `NC150`
- [ ] [LC 362 · Design Hit Counter](https://leetcode.com/problems/design-hit-counter/) — Medium 🔒 · `G169`
- [ ] [LC 380 · Insert Delete GetRandom O(1)](https://leetcode.com/problems/insert-delete-getrandom-o1/) — Medium · `G169` `TI150`
- [ ] [LC 622 · Design Circular Queue](https://leetcode.com/problems/design-circular-queue/) — Medium · `NC250`
- [ ] [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium · `G75` `NC150`

**Hard**

- [ ] [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard · `NC250`
- [ ] [LC 588 · Design In-Memory File System](https://leetcode.com/problems/design-in-memory-file-system/) — Hard 🔒 · `G169`
- [ ] [LC 895 · Maximum Frequency Stack](https://leetcode.com/problems/maximum-frequency-stack/) — Hard · `G169` `NC250`

## 6. How to use this list

1. **First pass (breadth):** every `G75` problem, in the week order of §4. Time-box 25 minutes for Easy and 40 for Medium, then read a solution, close it, and re-implement from scratch the same day.
2. **Second pass (depth by pattern):** for each pattern file, the remaining `NC150` and `G169` problems of that pattern, right after reading the file's first-principles section and worked examples.
3. **Third pass (coverage):** `TI150`-only and `NC250`-only problems for the patterns you are weakest in (Top Interview 150 has many array and string implementation problems that the others skip).
4. **Review:** tick the box only after a clean re-solve at least a week later. Spaced review is scheduled in [20-faang-preparation-plan.md](20-faang-preparation-plan.md), and the per-pattern templates are in the [cheat sheet](../99-Cheat-Sheets/17-faang-interview-cheatsheet.md).
