# Trees and Binary Search Trees

> **Band:** 🟢 1200 – 🔵 1900 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [recursion and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [stacks](04-stacks-and-monotonic-stacks.md)
> **You can say you know this when:** for any tree question you can say what each recursive call **returns** and what it **records globally**, convert any traversal to an iterative one, and handle the BST invariant with bounds instead of comparing only to children.

Trees are the most frequent topic in the fetched lists (41 problems in this file alone, see [18](18-leetcode-master-list.md)). Almost all of them are one idea: **a tree problem is a function of the root defined in terms of the same function on the children**. Get the return type right and the code is a few lines.

## 1. First principles — why this works

### 1.1 Recursion = structural induction

A binary tree is either empty or a root with a left and a right subtree. Any function $F(\text{tree})$ that can be computed from $F(\text{left})$, $F(\text{right})$ and the root value is a post-order DFS, and its correctness is induction on the height. You only need to answer three questions:

1. **What does the call return?** Height, "is valid", a sum, a pair (best path down, best path anywhere), a node.
2. **Base case:** what is $F(\varnothing)$? It is usually 0, `true`, or `nullptr`, chosen so the combination formula needs no special case.
3. **Combine:** how does the root use the children's answers?

When the quantity you need (diameter, max path sum) is not the one the parent can use (a path going *down*), **return one thing and record the other in a variable outside the recursion**. That is the "return downward, record through" pattern of Examples 4 and 5.

### 1.2 Traversal orders and what they are for

| Order | Visit | Typical use |
|---|---|---|
| pre-order | root, left, right | copying / serialising, passing information **down** (bounds, path sums) |
| in-order | left, root, right | BSTs: produces keys in **sorted** order |
| post-order | left, right, root | combining children's results **up** (height, DP on trees) |
| level-order (BFS) | by depth | per-level answers, shortest distance in an unweighted tree, right side view |

Iterative versions replace the call stack with an explicit stack. They are worth knowing because interviewers ask for them, and because a skewed tree of $10^5$ nodes overflows the default Java/C++ stack.

### 1.3 The BST invariant is global, not local

A binary search tree requires *every* key in the left subtree to be $<$ the root and every key in the right subtree to be $>$ it. Checking only `left.val < root.val < right.val` accepts `5 → (1, 6 → (3, 7))`, where 3 sits in the right subtree of 5. Correct checks: pass down an open interval $(lo, hi)$ that each node must fall in, or verify that the in-order sequence is strictly increasing. BST operations (search, insert, floor, successor) cost $O(h)$, where $h$ is $O(\log n)$ only if the tree is balanced.

### 1.4 Lowest common ancestor by "who found what"

Return from each subtree "the node I found" ($p$, $q$, their LCA, or null). If both children report something, the current node is where the two paths split: it is the LCA. If one child reports something, pass it up. Correctness: the LCA is the unique node where $p$ and $q$ end up in different subtrees (or which is itself $p$ or $q$). In a BST you can skip the search entirely: walk down while both keys are on the same side.

## 2. Definitions, formulas and complexities

| Fact | Value | Note |
|---|---|---|
| nodes in a perfect tree of height $h$ (root depth 0) | $2^{h+1} - 1$ | |
| height of a balanced tree with $n$ nodes | $\Theta(\log n)$ | skewed: $n - 1$ |
| number of binary tree shapes with $n$ nodes | Catalan $C_n = \frac{1}{n+1}\binom{2n}{n}$ | also the number of BSTs on $n$ keys |
| edges | $n - 1$ | |
| full binary tree (0 or 2 children) | leaves = internal + 1 | |
| complete tree in an array | children of $i$: $2i+1$, $2i+2$; parent $\lfloor (i-1)/2 \rfloor$ | heaps ([file 09](09-heaps-and-top-k.md)) |
| DFS / BFS | $O(n)$ time; space $O(h)$ for DFS, $O(w)$ for BFS ($w$ = max width) | |
| BST search / insert / delete | $O(h)$ | balanced trees (`std::set`, `TreeMap`) guarantee $O(\log n)$ |
| Morris in-order traversal | $O(n)$ time, $O(1)$ space | temporarily threads right pointers |
| traversals that determine the tree uniquely | pre + in, post + in (distinct keys); pre + post only for full trees | |

## 3. Reusable templates (C++ and Java)

Iterative in-order, pre-order and post-order, plus the "return downward, record through" DFS on diameter ([LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy):

```cpp
struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

vector<int> inorderIterative(TreeNode* root) {
    vector<int> out;
    vector<TreeNode*> st;
    TreeNode* cur = root;
    while (cur || !st.empty()) {
        while (cur) { st.push_back(cur); cur = cur->left; }   // go as far left as possible
        cur = st.back(); st.pop_back();
        out.push_back(cur->val);                              // left subtree done: visit
        cur = cur->right;
    }
    return out;
}

vector<int> preorderIterative(TreeNode* root) {
    vector<int> out;
    vector<TreeNode*> st;
    if (root) st.push_back(root);
    while (!st.empty()) {
        TreeNode* n = st.back(); st.pop_back();
        out.push_back(n->val);
        if (n->right) st.push_back(n->right);                 // right first so left is popped first
        if (n->left) st.push_back(n->left);
    }
    return out;
}

vector<int> postorderIterative(TreeNode* root) {              // reverse of (root, right, left)
    vector<int> out;
    vector<TreeNode*> st;
    if (root) st.push_back(root);
    while (!st.empty()) {
        TreeNode* n = st.back(); st.pop_back();
        out.push_back(n->val);
        if (n->left) st.push_back(n->left);
        if (n->right) st.push_back(n->right);
    }
    reverse(out.begin(), out.end());
    return out;
}

int diameterOfBinaryTree(TreeNode* root) {
    int best = 0;                                             // recorded through each node
    function<int(TreeNode*)> height = [&](TreeNode* n) -> int {   // returned downward
        if (!n) return 0;
        int l = height(n->left), r = height(n->right);
        best = max(best, l + r);                              // longest path bending at n (in edges)
        return 1 + max(l, r);
    };
    height(root);
    return best;
}
```

```java
static class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

static List<Integer> inorderIterative(TreeNode root) {
    List<Integer> out = new ArrayList<>();
    Deque<TreeNode> st = new ArrayDeque<>();
    TreeNode cur = root;
    while (cur != null || !st.isEmpty()) {
        while (cur != null) { st.push(cur); cur = cur.left; }
        cur = st.pop();
        out.add(cur.val);
        cur = cur.right;
    }
    return out;
}

static List<Integer> preorderIterative(TreeNode root) {
    List<Integer> out = new ArrayList<>();
    Deque<TreeNode> st = new ArrayDeque<>();
    if (root != null) st.push(root);
    while (!st.isEmpty()) {
        TreeNode n = st.pop();
        out.add(n.val);
        if (n.right != null) st.push(n.right);
        if (n.left != null) st.push(n.left);
    }
    return out;
}

static List<Integer> postorderIterative(TreeNode root) {
    LinkedList<Integer> out = new LinkedList<>();
    Deque<TreeNode> st = new ArrayDeque<>();
    if (root != null) st.push(root);
    while (!st.isEmpty()) {
        TreeNode n = st.pop();
        out.addFirst(n.val);                                  // prepend = reverse at the end
        if (n.left != null) st.push(n.left);
        if (n.right != null) st.push(n.right);
    }
    return out;
}

static int best;
static int height(TreeNode n) {
    if (n == null) return 0;
    int l = height(n.left), r = height(n.right);
    best = Math.max(best, l + r);
    return 1 + Math.max(l, r);
}
static int diameterOfBinaryTree(TreeNode root) {
    best = 0;
    height(root);
    return best;
}
```

BST search, insert and the "walk down" LCA ([LC 235 · Lowest Common Ancestor of a Binary Search Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-search-tree/) — Medium):

```cpp
struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

TreeNode* insertIntoBST(TreeNode* root, int key) {
    if (!root) return new TreeNode(key);
    TreeNode* cur = root;
    while (true) {
        TreeNode*& next = key < cur->val ? cur->left : cur->right;
        if (!next) { next = new TreeNode(key); return root; }
        cur = next;
    }
}

TreeNode* lcaBST(TreeNode* root, int p, int q) {
    while (root) {
        if (p < root->val && q < root->val) root = root->left;        // both on the left
        else if (p > root->val && q > root->val) root = root->right;  // both on the right
        else return root;                                             // split point (or equal)
    }
    return nullptr;
}
```

```java
static class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

static TreeNode insertIntoBST(TreeNode root, int key) {
    if (root == null) return new TreeNode(key);
    TreeNode cur = root;
    while (true) {
        if (key < cur.val) {
            if (cur.left == null) { cur.left = new TreeNode(key); return root; }
            cur = cur.left;
        } else {
            if (cur.right == null) { cur.right = new TreeNode(key); return root; }
            cur = cur.right;
        }
    }
}

static TreeNode lcaBST(TreeNode root, int p, int q) {
    while (root != null) {
        if (p < root.val && q < root.val) root = root.left;
        else if (p > root.val && q > root.val) root = root.right;
        else return root;
    }
    return null;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "depth", "height", "balanced", "same / symmetric / subtree" | post-order returning a value (or a sentinel like −1 for "unbalanced") |
| "per level", "right side view", "zigzag", "average of levels", "minimum depth" | BFS with level sizes |
| "path from root", "root-to-leaf sum", "good nodes" | pre-order passing state **down** |
| "any path" (may bend), "diameter", "max path sum" | return the best *downward* path, record the best *bent* path globally |
| "number of paths with sum $k$" (downward, any start) | prefix sums on the root-to-node path + hash map with backtracking |
| "valid BST", "k-th smallest", "successor", "closest value" | in-order (sorted) or bounds passed down |
| "LCA" | who-found-what recursion; BST: walk down by value |
| "construct from traversals" | pre-order gives roots, in-order gives the split (map value → index) |
| "serialise", "encode a tree as a string" | pre-order with null markers, or BFS with nulls |
| "distance $k$ from a node", "burn the tree" | add parent pointers, then BFS as in a graph ([file 11](11-graphs.md)) |
| "rob houses on a tree", "cameras", "choose nodes with no two adjacent" | tree DP returning a pair/tuple of states |

## 5. Worked examples

All drivers read `n` and then `n` tokens of the tree in LeetCode level order, with `null` for a missing child (the same format as the LeetCode examples), e.g. `7` / `3 9 20 null null 15 7`.

### Example 1 — Binary Tree Level Order Traversal · Medium

- **Source:** [LC 102 · Binary Tree Level Order Traversal](https://leetcode.com/problems/binary-tree-level-order-traversal/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** return the node values level by level, left to right. Up to 2000 nodes.
- **Thinking from first principles:** BFS visits nodes in non-decreasing depth order, but a plain queue loses the level boundaries. Fix it by processing the queue **one level at a time**: at the start of a level the queue holds exactly that level's nodes, so record `size = q.size()` and pop exactly that many. A DFS that passes `depth` and appends to `levels[depth]` also works, and it is the answer to "can you do it recursively?".

<details><summary>Solution</summary>

Invariant: at the top of the outer loop the queue holds exactly the nodes of the next level, in left-to-right order. Time $O(n)$, space $O(w)$. The driver prints LeetCode's nested-list format.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Solution {
public:
    vector<vector<int>> levelOrder(TreeNode* root) {
        vector<vector<int>> levels;
        if (!root) return levels;
        queue<TreeNode*> q;
        q.push(root);
        while (!q.empty()) {
            int size = q.size();                      // exactly this level's nodes
            levels.emplace_back();
            for (int i = 0; i < size; ++i) {
                TreeNode* n = q.front(); q.pop();
                levels.back().push_back(n->val);
                if (n->left) q.push(n->left);
                if (n->right) q.push(n->right);
            }
        }
        return levels;
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

int main() {
    int n;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    auto levels = Solution().levelOrder(buildTree(t));
    string out = "[";
    for (size_t i = 0; i < levels.size(); ++i) {
        out += i ? ",[" : "[";
        for (size_t j = 0; j < levels[i].size(); ++j) out += (j ? "," : "") + to_string(levels[i][j]);
        out += "]";
    }
    cout << out << "]\n";
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Solution {
    public List<List<Integer>> levelOrder(TreeNode root) {
        List<List<Integer>> levels = new ArrayList<>();
        if (root == null) return levels;
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        while (!q.isEmpty()) {
            int size = q.size();
            List<Integer> level = new ArrayList<>(size);
            for (int i = 0; i < size; i++) {
                TreeNode n = q.poll();
                level.add(n.val);
                if (n.left != null) q.add(n.left);
                if (n.right != null) q.add(n.right);
            }
            levels.add(level);
        }
        return levels;
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        List<List<Integer>> levels = new Solution().levelOrder(buildTree(t));
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < levels.size(); i++) {
            sb.append(i > 0 ? ",[" : "[");
            for (int j = 0; j < levels.get(i).size(); j++) sb.append(j > 0 ? "," : "").append(levels.get(i).get(j));
            sb.append("]");
        }
        System.out.println(sb.append("]"));
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
7
3 9 20 null null 15 7
out:
[[3],[9,20],[15,7]]
-->
<!-- test
in:
1
1
out:
[[1]]
-->
<!-- test
in:
0
out:
[]
-->
<!-- test
in:
7
1 2 null 3 null 4 null
out:
[[1],[2],[3],[4]]
-->

### Example 2 — Validate Binary Search Tree · Medium

- **Source:** [LC 98 · Validate Binary Search Tree](https://leetcode.com/problems/validate-binary-search-tree/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** is the tree a valid BST with **strict** inequalities? Up to $10^4$ nodes with values anywhere in the 32-bit range.
- **Thinking from first principles:** the local check (children only) is wrong, as shown in §1.3. Each node must lie in an open interval determined by **all** its ancestors: going left tightens the upper bound to the parent's value, going right tightens the lower bound. Pass the interval down in pre-order. Since values can equal `INT_MIN`/`INT_MAX`, the initial bounds must be outside the `int` range. Use 64-bit bounds (or nullable bounds). The in-order alternative (the sequence must be strictly increasing) is equally good; mention both.

<details><summary>Solution</summary>

`valid(node, lo, hi)` checks $lo < \text{val} < hi$ and recurses with $(lo, \text{val})$ on the left and $(\text{val}, hi)$ on the right. Each node is checked once: $O(n)$ time, $O(h)$ stack.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Solution {
public:
    bool isValidBST(TreeNode* root) { return valid(root, LLONG_MIN, LLONG_MAX); }
private:
    bool valid(TreeNode* n, long long lo, long long hi) {     // n->val must be in (lo, hi)
        if (!n) return true;
        if (n->val <= lo || n->val >= hi) return false;
        return valid(n->left, lo, n->val) && valid(n->right, n->val, hi);
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

int main() {
    int n;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    cout << (Solution().isValidBST(buildTree(t)) ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Solution {
    public boolean isValidBST(TreeNode root) { return valid(root, Long.MIN_VALUE, Long.MAX_VALUE); }
    private boolean valid(TreeNode n, long lo, long hi) {
        if (n == null) return true;
        if (n.val <= lo || n.val >= hi) return false;
        return valid(n.left, lo, n.val) && valid(n.right, n.val, hi);
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        System.out.println(new Solution().isValidBST(buildTree(t)));
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
2 1 3
out:
true
-->
<!-- test
in:
7
5 1 4 null null 3 6
out:
false
-->
<!-- test
in:
7
5 1 6 null null 3 7
out:
false
-->
<!-- test
in:
2
2147483647 -2147483648
out:
true
-->
<!-- test
in:
2
1 1
out:
false
-->

### Example 3 — Lowest Common Ancestor of a Binary Tree · Medium

- **Source:** [LC 236 · Lowest Common Ancestor of a Binary Tree](https://leetcode.com/problems/lowest-common-ancestor-of-a-binary-tree/) — Medium · `G75` `B75` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** given two distinct nodes $p$ and $q$ that exist in a binary tree (not a BST) with unique values, return their lowest common ancestor (a node counts as its own ancestor). Up to $10^5$ nodes.
- **Thinking from first principles:** brute force records the root-to-$p$ and root-to-$q$ paths and returns the last common node. That is $O(n)$ time but needs path storage. The single-pass recursion asks each subtree "did you see $p$ or $q$?" and returns the node it saw. If a node gets non-null answers from both children, $p$ and $q$ split there, so it is the LCA. If the node itself is $p$ or $q$, return it immediately: either the other node is below it (so it is the LCA) or elsewhere (and the ancestor above will see both sides).

<details><summary>Solution</summary>

Return value semantics: `lca(n)` is null if neither $p$ nor $q$ is in subtree($n$). It is $p$ or $q$ if exactly one is there. It is the LCA if both are. Each node is visited once: $O(n)$ time, $O(h)$ stack. The driver reads the tree, then the values of $p$ and $q$, and prints the LCA's value.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Solution {
public:
    TreeNode* lowestCommonAncestor(TreeNode* root, TreeNode* p, TreeNode* q) {
        if (!root || root == p || root == q) return root;
        TreeNode* l = lowestCommonAncestor(root->left, p, q);
        TreeNode* r = lowestCommonAncestor(root->right, p, q);
        if (l && r) return root;                      // p and q split here
        return l ? l : r;                             // pass up whatever was found
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

TreeNode* findNode(TreeNode* r, int v) {
    if (!r || r->val == v) return r;
    TreeNode* l = findNode(r->left, v);
    return l ? l : findNode(r->right, v);
}

int main() {
    int n;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    int pv, qv;
    cin >> pv >> qv;
    TreeNode* root = buildTree(t);
    cout << Solution().lowestCommonAncestor(root, findNode(root, pv), findNode(root, qv))->val << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Solution {
    public TreeNode lowestCommonAncestor(TreeNode root, TreeNode p, TreeNode q) {
        if (root == null || root == p || root == q) return root;
        TreeNode l = lowestCommonAncestor(root.left, p, q);
        TreeNode r = lowestCommonAncestor(root.right, p, q);
        if (l != null && r != null) return root;
        return l != null ? l : r;
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    static TreeNode findNode(TreeNode r, int v) {
        if (r == null || r.val == v) return r;
        TreeNode l = findNode(r.left, v);
        return l != null ? l : findNode(r.right, v);
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        int pv = in.nextInt(), qv = in.nextInt();
        TreeNode root = buildTree(t);
        System.out.println(new Solution().lowestCommonAncestor(root, findNode(root, pv), findNode(root, qv)).val);
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
11
3 5 1 6 2 0 8 null null 7 4
5 1
out:
3
-->
<!-- test
in:
11
3 5 1 6 2 0 8 null null 7 4
5 4
out:
5
-->
<!-- test
in:
2
1 2
1 2
out:
1
-->
<!-- test
in:
11
3 5 1 6 2 0 8 null null 7 4
7 6
out:
5
-->

### Example 4 — Binary Tree Maximum Path Sum · Hard

- **Source:** [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1700 CF, est.)
- **Problem:** a path is any sequence of adjacent nodes, each used at most once, with at least one node. It does not have to pass through the root. Return the maximum path sum. Values in $[-1000, 1000]$, up to $3 \cdot 10^4$ nodes.
- **Thinking from first principles:** every path has a unique highest node where it "bends". At that node the best path is $\text{val} + \max(0, \text{down}(L)) + \max(0, \text{down}(R))$, where $\text{down}(x)$ is the best path that starts at $x$ and goes *downwards* only. The parent can extend only a downward path (a bent path would visit the parent's child twice). So **return** $\text{down}(n) = \text{val} + \max(0, \text{down}(L), \text{down}(R))$ and **record** the bent value. Clamping a child's contribution at 0 means "don't take that branch". The answer must start below $-\infty$ because a tree of all negative values still has a one-node path.

<details><summary>Solution</summary>

Post-order DFS. Correctness: the optimal path's highest node $v$ is visited, and at $v$ the recorded value is the best path bending there, because the best downward branches are independent. Time $O(n)$, space $O(h)$. Sums are at most $3 \cdot 10^7$ in absolute value, which fits in an `int`.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Solution {
public:
    int maxPathSum(TreeNode* root) {
        best = INT_MIN;
        down(root);
        return best;
    }
private:
    int best;
    int down(TreeNode* n) {                               // best path starting at n going down
        if (!n) return 0;
        int l = max(0, down(n->left));                    // a negative branch is never worth taking
        int r = max(0, down(n->right));
        best = max(best, n->val + l + r);                 // best path bending at n
        return n->val + max(l, r);
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

int main() {
    int n;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    cout << Solution().maxPathSum(buildTree(t)) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Solution {
    private int best;
    public int maxPathSum(TreeNode root) {
        best = Integer.MIN_VALUE;
        down(root);
        return best;
    }
    private int down(TreeNode n) {
        if (n == null) return 0;
        int l = Math.max(0, down(n.left)), r = Math.max(0, down(n.right));
        best = Math.max(best, n.val + l + r);
        return n.val + Math.max(l, r);
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        System.out.println(new Solution().maxPathSum(buildTree(t)));
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
out:
6
-->
<!-- test
in:
7
-10 9 20 null null 15 7
out:
42
-->
<!-- test
in:
1
-3
out:
-3
-->
<!-- test
in:
3
-2 -1 -3
out:
-1
-->
<!-- test
in:
7
5 4 8 11 null 13 4
out:
41
-->

### Example 5 — Path Sum III · Medium

- **Source:** [LC 437 · Path Sum III](https://leetcode.com/problems/path-sum-iii/) — Medium · `G169`
- **Difficulty:** LeetCode Medium (≈ 1600 CF, est.)
- **Problem:** count the downward paths (from any node to any descendant, possibly a single node) whose values sum to `targetSum`. Up to 1000 nodes, values in $[-10^9, 10^9]$.
- **Thinking from first principles:** brute force: start a DFS from every node, $O(n \cdot h)$, which is $O(n^2)$ on a skewed tree. A downward path is a contiguous segment of some **root-to-node path**, and on a root-to-node path this is exactly "count subarrays with sum $k$" from [file 02](02-arrays-hashing-and-prefix-sums.md). Keep a map of prefix sums *along the current root path*: when entering a node, add `count[prefix - target]` and then record `prefix`. When leaving, **remove** it (backtrack), so siblings never see each other's prefixes. Values up to $10^9$ over 1000 nodes need 64-bit sums.

<details><summary>Solution</summary>

Pre-order with an explicit undo. Correctness: at node $v$ the map holds exactly the prefix sums of $v$'s proper ancestors' paths plus the empty prefix, so the paths counted at $v$ are exactly the downward paths ending at $v$. Time $O(n)$ expected, space $O(h)$. The driver reads the tree and then `targetSum`.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Solution {
public:
    int pathSum(TreeNode* root, int targetSum) {
        count.clear();
        count[0] = 1;                                     // empty prefix: paths starting at the root
        return dfs(root, 0, targetSum);
    }
private:
    unordered_map<long long, int> count;                  // prefix sums on the current root path
    int dfs(TreeNode* n, long long prefix, long long target) {
        if (!n) return 0;
        prefix += n->val;
        auto it = count.find(prefix - target);
        int res = (it == count.end()) ? 0 : it->second;   // paths ending at n
        ++count[prefix];
        res += dfs(n->left, prefix, target) + dfs(n->right, prefix, target);
        --count[prefix];                                  // backtrack: leave the path
        return res;
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

int main() {
    int n, target;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    cin >> target;
    cout << Solution().pathSum(buildTree(t), target) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Solution {
    private final Map<Long, Integer> count = new HashMap<>();
    public int pathSum(TreeNode root, int targetSum) {
        count.clear();
        count.put(0L, 1);
        return dfs(root, 0L, targetSum);
    }
    private int dfs(TreeNode n, long prefix, long target) {
        if (n == null) return 0;
        prefix += n.val;
        int res = count.getOrDefault(prefix - target, 0);
        count.merge(prefix, 1, Integer::sum);
        res += dfs(n.left, prefix, target) + dfs(n.right, prefix, target);
        count.merge(prefix, -1, Integer::sum);
        return res;
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        int target = in.nextInt();
        System.out.println(new Solution().pathSum(buildTree(t), target));
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
11
10 5 -3 3 2 null 11 3 -2 null 1
8
out:
3
-->
<!-- test
in:
13
5 4 8 11 null 13 4 7 2 null null 5 1
22
out:
3
-->
<!-- test
in:
0
0
out:
0
-->
<!-- test
in:
5
1000000000 1000000000 null 1000000000 null
-1294967296
out:
0
-->
<!-- test
in:
7
0 0 0 null null 0 null
0
out:
8
-->

### Example 6 — Serialize and Deserialize Binary Tree · Hard

- **Source:** [LC 297 · Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) — Hard · `G75` `NC150`
- **Difficulty:** LeetCode Hard (≈ 1500 CF, est.)
- **Problem:** design `serialize(root) → string` and `deserialize(string) → root` so that a round trip reproduces the tree exactly. Up to $10^4$ nodes, values in $[-1000, 1000]$, duplicates allowed.
- **Thinking from first principles:** a single traversal without null markers is ambiguous (in-order `1 2` could be either shape). Recording **every null child** makes a pre-order traversal unambiguous: the reader can rebuild recursively, since each token is either a null (return) or a value (create a node, then read its left subtree, then its right subtree), consuming tokens in exactly the order the writer produced them. Format: values and `#` separated by commas, e.g. `1,2,#,#,3,4,#,#,5,#,#`. BFS with nulls (LeetCode's own format) is the other standard answer.

<details><summary>Solution</summary>

Serialise: pre-order, `#` for null. Deserialise: a cursor over the tokens and the mirror recursion. Both are $O(n)$ time and output size. Recursion depth is the tree height. For a skewed $10^4$-node tree that is fine in C++, and in Java mention the stack size or use an explicit stack. The driver prints the serialised string and then the round-tripped tree in LeetCode level order.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class Codec {
public:
    string serialize(TreeNode* root) {
        string out;
        write(root, out);
        out.pop_back();                                   // drop the trailing comma
        return out;
    }
    TreeNode* deserialize(string data) {
        stringstream ss(data);
        string tok;
        vector<string> toks;
        while (getline(ss, tok, ',')) toks.push_back(tok);
        size_t pos = 0;
        return read(toks, pos);
    }
private:
    void write(TreeNode* n, string& out) {
        if (!n) { out += "#,"; return; }
        out += to_string(n->val) + ",";
        write(n->left, out);
        write(n->right, out);
    }
    TreeNode* read(const vector<string>& toks, size_t& pos) {   // consumes tokens in pre-order
        const string& t = toks[pos++];
        if (t == "#") return nullptr;
        TreeNode* n = new TreeNode(stoi(t));
        n->left = read(toks, pos);
        n->right = read(toks, pos);
        return n;
    }
};

TreeNode* buildTree(const vector<string>& t) {
    if (t.empty() || t[0] == "null") return nullptr;
    TreeNode* root = new TreeNode(stoi(t[0]));
    queue<TreeNode*> q;
    q.push(root);
    for (size_t i = 1; !q.empty() && i < t.size(); i += 2) {
        TreeNode* cur = q.front(); q.pop();
        if (t[i] != "null") { cur->left = new TreeNode(stoi(t[i])); q.push(cur->left); }
        if (i + 1 < t.size() && t[i + 1] != "null") { cur->right = new TreeNode(stoi(t[i + 1])); q.push(cur->right); }
    }
    return root;
}

string levelOrderString(TreeNode* root) {                 // LeetCode format, trailing nulls trimmed
    vector<string> out;
    queue<TreeNode*> q;
    q.push(root);
    while (!q.empty()) {
        TreeNode* n = q.front(); q.pop();
        if (!n) { out.push_back("null"); continue; }
        out.push_back(to_string(n->val));
        q.push(n->left);
        q.push(n->right);
    }
    while (!out.empty() && out.back() == "null") out.pop_back();
    string s = "[";
    for (size_t i = 0; i < out.size(); ++i) s += (i ? "," : "") + out[i];
    return s + "]";
}

int main() {
    int n;
    cin >> n;
    vector<string> t(n);
    for (auto& s : t) cin >> s;
    Codec codec;
    string data = codec.serialize(buildTree(t));
    cout << data << '\n' << levelOrderString(codec.deserialize(data)) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

class Codec {
    public String serialize(TreeNode root) {
        StringBuilder sb = new StringBuilder();
        write(root, sb);
        sb.setLength(sb.length() - 1);
        return sb.toString();
    }
    public TreeNode deserialize(String data) {
        String[] toks = data.split(",");
        int[] pos = {0};
        return read(toks, pos);
    }
    private void write(TreeNode n, StringBuilder sb) {
        if (n == null) { sb.append("#,"); return; }
        sb.append(n.val).append(',');
        write(n.left, sb);
        write(n.right, sb);
    }
    private TreeNode read(String[] toks, int[] pos) {
        String t = toks[pos[0]++];
        if (t.equals("#")) return null;
        TreeNode n = new TreeNode(Integer.parseInt(t));
        n.left = read(toks, pos);
        n.right = read(toks, pos);
        return n;
    }
}

public class Main {
    static TreeNode buildTree(String[] t) {
        if (t.length == 0 || t[0].equals("null")) return null;
        TreeNode root = new TreeNode(Integer.parseInt(t[0]));
        Deque<TreeNode> q = new ArrayDeque<>();
        q.add(root);
        for (int i = 1; !q.isEmpty() && i < t.length; i += 2) {
            TreeNode cur = q.poll();
            if (!t[i].equals("null")) { cur.left = new TreeNode(Integer.parseInt(t[i])); q.add(cur.left); }
            if (i + 1 < t.length && !t[i + 1].equals("null")) { cur.right = new TreeNode(Integer.parseInt(t[i + 1])); q.add(cur.right); }
        }
        return root;
    }
    static String levelOrderString(TreeNode root) {
        List<String> out = new ArrayList<>();
        Deque<TreeNode> q = new LinkedList<>();               // LinkedList allows null elements
        q.add(root);
        while (!q.isEmpty()) {
            TreeNode n = q.poll();
            if (n == null) { out.add("null"); continue; }
            out.add(String.valueOf(n.val));
            q.add(n.left);
            q.add(n.right);
        }
        while (!out.isEmpty() && out.get(out.size() - 1).equals("null")) out.remove(out.size() - 1);
        return "[" + String.join(",", out) + "]";
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] t = new String[n];
        for (int i = 0; i < n; i++) t[i] = in.next();
        Codec codec = new Codec();
        String data = codec.serialize(buildTree(t));
        System.out.println(data);
        System.out.println(levelOrderString(codec.deserialize(data)));
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
7
1 2 3 null null 4 5
out:
1,2,#,#,3,4,#,#,5,#,#
[1,2,3,null,null,4,5]
-->
<!-- test
in:
0
out:
#
[]
-->
<!-- test
in:
5
-1 null -2 null -3
out:
-1,#,-2,#,-3,#,#
[-1,null,-2,null,-3]
-->

## 6. Pitfalls and things to remember

1. **Decide what the recursion returns before writing it.** Most wrong answers come from returning the global answer (bent path) where the parent needs the local one (downward path).
2. **BST validity needs bounds from all ancestors** and strict inequality. Use 64-bit or nullable bounds when node values can be `INT_MIN`/`INT_MAX`.
3. **Initialise maxima to $-\infty$, not 0,** whenever all values may be negative (max path sum, max level sum).
4. **Backtrack shared state** in pre-order DFS (path lists, prefix-sum maps, visited sets on root paths): undo the change after the children return.
5. **Recursion depth:** a skewed tree has height $n$. Java's default thread stack holds roughly $10^4$–$10^5$ frames depending on the method's locals, so for deep trees mention an iterative version or a bigger stack. C++ on LeetCode is usually fine up to $10^5$.
6. **`ArrayDeque` cannot hold `null`.** BFS that enqueues null children (for serialisation) needs `LinkedList` or must skip nulls.
7. **Level-order with nulls ≠ array heap indexing.** LeetCode's format lists children only for non-null nodes, so index $2i+1$ arithmetic does not apply to it.
8. **Node identity vs value:** LCA compares nodes, and duplicate values make value comparisons wrong.
9. **Serialisation must be self-delimiting.** Separate tokens (commas) and mark nulls. With multi-digit or negative numbers, a format without separators is ambiguous.
10. **In-order of a BST is sorted only if the BST is valid.** "k-th smallest" = in-order rank, with early exit after $k$ nodes ($O(h + k)$).

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Level order → "zigzag / right side view / bottom-up" | same BFS: reverse alternate levels, take the last of each level, reverse the result |
| "Do it with $O(1)$ extra space" (in-order) | Morris traversal: thread the in-order predecessor's right pointer to the current node, then remove the thread |
| Validate BST → "duplicates allowed on the left" | bounds become $(lo, hi]$ on the left side; state the convention |
| LCA → "nodes may not exist in the tree" | count how many of $p, q$ were found; return the LCA only if both were |
| LCA → "many queries" | binary lifting or Euler tour + sparse table: $O(n \log n)$ preprocessing, $O(\log n)$ or $O(1)$ per query ([CP: LCA](../10-Trees/02-lca-and-binary-lifting.md)) |
| LCA → "nodes have parent pointers" | it becomes the intersection of two linked lists ([file 06](06-linked-lists.md)) |
| Max path sum → "return the path itself" | store which children were taken at the best bend, then walk down |
| Path Sum III → "paths may go up and down" | that is max/count over all node pairs: rerooting or centroid decomposition (CP territory) |
| Serialise → "make it compact" / "BST only" | a BST is determined by its pre-order alone (rebuild with bounds); binary encoding of values; omit trailing nulls |
| "K-th smallest with frequent inserts/deletes" | augment nodes with subtree sizes (order-statistic tree), $O(h)$ per query |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. BST Iterator is under [design problems](17-design-problems.md).

**Easy** (14)

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

**Medium** (25)

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

**Hard** (2)

- [ ] [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard · `G169` `B75` `NC150` `TI150`
- [ ] [LC 297 · Serialize and Deserialize Binary Tree](https://leetcode.com/problems/serialize-and-deserialize-binary-tree/) — Hard · `G75` `NC150`

**Beyond the lists:**

- [ ] [LC 1302 · Deepest Leaves Sum](https://leetcode.com/problems/deepest-leaves-sum/) — Medium — BFS, keep the last level
- [ ] [LC 1123 · Lowest Common Ancestor of Deepest Leaves](https://leetcode.com/problems/lowest-common-ancestor-of-deepest-leaves/) — Medium — return (depth, node) pairs
- [ ] [LC 979 · Distribute Coins in Binary Tree](https://leetcode.com/problems/distribute-coins-in-binary-tree/) — Medium — return excess, record moves
- [ ] [LC 652 · Find Duplicate Subtrees](https://leetcode.com/problems/find-duplicate-subtrees/) — Medium — serialise subtrees as keys
- [ ] [LC 1008 · Construct Binary Search Tree from Preorder Traversal](https://leetcode.com/problems/construct-binary-search-tree-from-preorder-traversal/) — Medium — bounds, $O(n)$
- [ ] [LC 2096 · Step-By-Step Directions From a Binary Tree Node to Another](https://leetcode.com/problems/step-by-step-directions-from-a-binary-tree-node-to-another/) — Medium — paths from the root, strip the common prefix
- [ ] [LC 99 · Recover Binary Search Tree](https://leetcode.com/problems/recover-binary-search-tree/) — Medium — in-order inversions
- [ ] [LC 968 · Binary Tree Cameras](https://leetcode.com/problems/binary-tree-cameras/) — Hard — 3-state tree DP / greedy from the leaves
- [ ] [LC 987 · Vertical Order Traversal of a Binary Tree](https://leetcode.com/problems/vertical-order-traversal-of-a-binary-tree/) — Hard — (column, row, value) sort

## 9. CP counterpart

- [Tree basics, diameter, centre, Euler tour](../10-Trees/01-tree-basics-diameter-center-euler-tour.md): general (non-binary) trees as adjacency lists, two-BFS diameter, subtree ranges.
- [LCA and binary lifting](../10-Trees/02-lca-and-binary-lifting.md): many LCA queries, $k$-th ancestor, path aggregates.
- [Tree DP and rerooting](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md): the "return a tuple of states" idea at full strength (House Robber III, cameras, all-pairs path quantities).
- [Ordered sets, PBDS and heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md): balanced BSTs from the library side (`std::set`, `TreeMap`, order statistics).

What changes: CP trees come as edge lists with $n \le 2 \cdot 10^5$, so recursion depth becomes a real problem (iterative DFS or a bigger stack). Interview trees come as `TreeNode` objects, and clarity of the recursive contract is what is graded.

## 10. Self-check

1. For max path sum, what does the recursive function return, and what is recorded globally? Why can't the parent use the recorded value?
2. Give a tree that passes the "children only" BST check but is not a BST.
3. Explain why `lca(root)` returns the correct node when $p$ is an ancestor of $q$.
4. Why does Path Sum III need `--count[prefix]` after the recursive calls?
5. Why is pre-order **with** null markers enough to rebuild a tree, while pre-order alone is not?
6. Write iterative in-order from memory. What is on the stack at any moment?
7. What is the space complexity of BFS vs DFS on a perfect binary tree with $n$ nodes?
8. How do you find the k-th smallest element in a BST in $O(h + k)$?

<details><summary>Answers</summary>

1. It returns the best path that starts at the node and goes down (val + max(0, best child)). The best path bending at the node is recorded. A bent path already uses both children, so extending it to the parent would make the parent's path visit a node twice.
2. Root 5, left 1, right 6, and 6's left child 3: each parent–child pair is ordered, but 3 < 5 sits in the right subtree of 5.
3. The recursion returns $p$ as soon as it reaches $p$, without looking below. No other subtree contains $q$, so every ancestor gets one non-null answer and passes $p$ up to the root. $p$ is the correct LCA.
4. The map must contain only the prefixes of the *current* root-to-node path. Without the undo, a sibling subtree would match prefixes that are not its ancestors, which counts non-downward "paths".
5. With null markers the reader knows exactly when a subtree ends, so the recursive reader consumes tokens in the same order the writer produced them. Without them, `1 2` could be 2 as a left or a right child.
6. `while (cur || stack)`: push the whole left spine, pop, visit, move to the right child. The stack holds the ancestors whose left subtree is being processed and who have not been visited yet, i.e. a path.
7. BFS holds up to a whole level, $\approx n/2$ nodes: $O(n)$. DFS holds one root path: $O(\log n)$.
8. Iterative in-order with an early exit when the counter reaches $k$. Pushing the left spine costs $O(h)$, and then each visited node costs amortised $O(1)$.

</details>
