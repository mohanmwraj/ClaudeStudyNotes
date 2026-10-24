# Graphs: BFS, DFS, Topological Sort and Union-Find

> **Band:** 🟢 1200 – 🔵 1800 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [trees](07-trees-and-bst.md), [stacks and queues](04-stacks-and-monotonic-stacks.md)
> **You can say you know this when:** you can model a grid, a word puzzle or a dependency list as a graph within a minute, pick BFS vs DFS vs union-find by what is being asked, and write each one iteratively without visited-set bugs.

Graph questions in interviews are rarely about exotic algorithms. They test whether you can **see the graph** (cells, words, courses, accounts, states of a lock are nodes; adjacency, one-letter edits, prerequisites, shared emails, wheel turns are edges) and then apply one of four tools correctly: BFS, DFS, topological sort, union-find. Weighted shortest paths and MSTs are in [advanced graphs](12-advanced-graphs.md).

## 1. First principles — why this works

### 1.1 Traversal = expanding a frontier while remembering what you have seen

Every traversal keeps a set of discovered nodes and a container of nodes whose neighbours have not been examined yet. The container's discipline decides the order:

- **Queue (BFS):** nodes come out in order of distance from the source. With unit edge weights, the first time a node is discovered is along a shortest path. Proof: by induction the queue always holds nodes at distance $d$ followed by nodes at distance $d+1$, never anything else.
- **Stack / recursion (DFS):** go deep first. Distances mean nothing, but DFS gives entry/exit times, which detect cycles in directed graphs and give a topological order (reverse post-order).

Both visit each node once and each edge once or twice: $O(V + E)$. The single most important implementation rule: **mark a node visited when you push it, not when you pop it.** Otherwise a node can sit in the queue many times and BFS degrades towards $O(E \cdot \text{copies})$.

### 1.2 Multi-source BFS

"Distance from the nearest gate / rotten orange / zero" is a BFS started from **all sources at once** (distance 0 for each). It is equivalent to adding a virtual super-source connected to every source by an edge of weight 0. One BFS gives every cell its distance to the nearest source in $O(V + E)$, instead of one BFS per source.

### 1.3 Topological order exists iff there is no directed cycle

Kahn's algorithm: repeatedly remove a node with in-degree 0 (it has no unmet prerequisite) and decrement its successors' in-degrees. If all $V$ nodes get removed, the removal order is topological. If some remain, every remaining node has in-degree $\ge 1$ within the remainder, and walking backwards along incoming edges inside a finite set must repeat a node, so there is a cycle. DFS gives the same answer: a back edge (to a node that is "on the stack", colour grey) means a cycle, and reverse post-order is a topological order.

### 1.4 Union-find answers "are these connected?" under edge insertions

Disjoint-set union keeps a forest where each tree is one component, identified by its root. `find` walks to the root, `union` links two roots. With **path compression** (point nodes at the root while walking) and **union by size/rank**, any sequence of $m$ operations costs $O(m \, \alpha(n))$, where $\alpha$ is the inverse Ackermann function ($\le 4$ for any practical $n$). Use it when edges arrive over time and you only need connectivity: counting components, detecting the edge that closes a cycle, grouping accounts by shared emails. It cannot delete edges, and it does not give paths.

## 2. Definitions, formulas and complexities

| Fact | Value / rule |
|---|---|
| adjacency list memory | $O(V + E)$; adjacency matrix $O(V^2)$ (only for dense graphs or $V \le$ a few thousand) |
| BFS / DFS | $O(V + E)$; a grid has $V = RC$, $E \le 4RC$ |
| tree | connected, $V - 1$ edges, no cycle (any two of these imply the third) |
| components after adding edges | $V - \#\{\text{successful unions}\}$ |
| undirected cycle | a union whose endpoints already share a root, or a DFS edge to a visited non-parent |
| directed cycle | Kahn leaves nodes unremoved, or DFS meets a grey node |
| bipartite | 2-colourable ⇔ no odd cycle; BFS colouring checks it in $O(V+E)$ |
| DSU with both heuristics | $O(\alpha(n))$ amortised per operation |
| implicit graphs (lock states, words) | $V$ = number of states; generate neighbours on the fly |

## 3. Reusable templates (C++ and Java)

BFS shortest distances in an unweighted graph, Kahn's topological sort, and DSU:

```cpp
vector<int> bfsDistances(const vector<vector<int>>& adj, int src) {
    vector<int> dist(adj.size(), -1);
    queue<int> q;
    dist[src] = 0;                                   // mark when pushing
    q.push(src);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int v : adj[u])
            if (dist[v] == -1) { dist[v] = dist[u] + 1; q.push(v); }
    }
    return dist;
}

vector<int> topoOrder(int n, const vector<vector<int>>& adj) {   // empty if there is a cycle
    vector<int> indeg(n, 0), order;
    for (int u = 0; u < n; ++u) for (int v : adj[u]) indeg[v]++;
    queue<int> q;
    for (int u = 0; u < n; ++u) if (indeg[u] == 0) q.push(u);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        order.push_back(u);
        for (int v : adj[u]) if (--indeg[v] == 0) q.push(v);
    }
    if ((int)order.size() < n) order.clear();        // leftover nodes lie on or behind a cycle
    return order;
}

struct DSU {
    vector<int> parent, sz;
    explicit DSU(int n) : parent(n), sz(n, 1) { iota(parent.begin(), parent.end(), 0); }
    int find(int x) {
        while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; }   // path halving
        return x;
    }
    bool unite(int a, int b) {                       // false if already connected
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);               // union by size
        parent[b] = a;
        sz[a] += sz[b];
        return true;
    }
};
```

```java
static int[] bfsDistances(List<List<Integer>> adj, int src) {
    int[] dist = new int[adj.size()];
    Arrays.fill(dist, -1);
    ArrayDeque<Integer> q = new ArrayDeque<>();
    dist[src] = 0;
    q.add(src);
    while (!q.isEmpty()) {
        int u = q.poll();
        for (int v : adj.get(u))
            if (dist[v] == -1) { dist[v] = dist[u] + 1; q.add(v); }
    }
    return dist;
}

static int[] topoOrder(int n, List<List<Integer>> adj) {
    int[] indeg = new int[n], order = new int[n];
    for (int u = 0; u < n; u++) for (int v : adj.get(u)) indeg[v]++;
    ArrayDeque<Integer> q = new ArrayDeque<>();
    for (int u = 0; u < n; u++) if (indeg[u] == 0) q.add(u);
    int k = 0;
    while (!q.isEmpty()) {
        int u = q.poll();
        order[k++] = u;
        for (int v : adj.get(u)) if (--indeg[v] == 0) q.add(v);
    }
    return k == n ? order : new int[0];
}

static class DSU {
    final int[] parent, sz;
    DSU(int n) {
        parent = new int[n];
        sz = new int[n];
        for (int i = 0; i < n; i++) { parent[i] = i; sz[i] = 1; }
    }
    int find(int x) {
        while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; }
        return x;
    }
    boolean unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        parent[b] = a;
        sz[a] += sz[b];
        return true;
    }
}
```

Grid neighbours without four copies of the same `if`:

```cpp
void gridNeighbours(int R, int C, int r, int c, vector<pair<int, int>>& out) {
    static const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
    out.clear();
    for (int d = 0; d < 4; ++d) {
        int nr = r + dr[d], nc = c + dc[d];
        if (nr >= 0 && nr < R && nc >= 0 && nc < C) out.push_back({nr, nc});
    }
}
```

```java
static final int[][] DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
static List<int[]> gridNeighbours(int R, int C, int r, int c) {
    List<int[]> out = new ArrayList<>(4);
    for (int[] d : DIRS) {
        int nr = r + d[0], nc = c + d[1];
        if (nr >= 0 && nr < R && nc >= 0 && nc < C) out.add(new int[]{nr, nc});
    }
    return out;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "number of islands / regions / provinces / connected components" | DFS/BFS flood fill, or DSU |
| "shortest number of steps / moves / transformations", unit cost | BFS (on an implicit graph if needed) |
| "nearest X from every cell", "spread simultaneously" | multi-source BFS |
| "prerequisites", "order of tasks", "build order", "can all be finished?" | topological sort (Kahn) / cycle detection |
| "edges added over time, connected?", "redundant edge", "merge accounts" | union-find |
| "is it a valid tree?" | $E = V - 1$ and connected (DSU with no failed union) |
| "regions not connected to the border", "surrounded" | flood fill **from the border** first, then everything unreached is enclosed |
| "can water reach both oceans" | reverse the direction: BFS uphill from each ocean, intersect |
| "copy a graph" | traversal + hash map old → new |
| "two groups with no conflicting pair" | bipartite check (BFS 2-colouring) |
| weights, "cheapest", "within $k$ stops" | not plain BFS: Dijkstra / Bellman–Ford ([file 12](12-advanced-graphs.md)) |

## 5. Worked examples

### Example 1 — Number of Islands · Medium

- **Source:** [LC 200 · Number of Islands](https://leetcode.com/problems/number-of-islands/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** an $R \times C$ grid ($\le 300 \times 300$) of `'1'` land and `'0'` water. Count the islands (4-directionally connected groups of land).
- **Thinking from first principles:** an island is a connected component of the graph whose nodes are land cells and whose edges join adjacent land cells. Scan the grid. Each time an unvisited land cell appears, it starts a new component, so count it and flood-fill the whole component so its other cells are not counted again. Recursive DFS is shortest to write, but a $300 \times 300$ all-land grid makes the recursion $9 \cdot 10^4$ deep, which can overflow the Java stack. An explicit BFS queue avoids that. Marking land as water when it is discovered serves as the visited set.

<details><summary>Solution</summary>

Each cell is enqueued at most once (it is sunk when enqueued): $O(RC)$ time, $O(\min(R, C))$ typical queue size for BFS ($O(RC)$ worst case). This mutates the input. Say so, and copy the grid if mutation is not allowed. The driver reads `R C` and the rows.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int numIslands(vector<vector<char>>& grid) {
        int R = grid.size(), C = grid[0].size(), islands = 0;
        const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
        for (int r = 0; r < R; ++r)
            for (int c = 0; c < C; ++c) {
                if (grid[r][c] != '1') continue;
                ++islands;                                   // new component found
                queue<pair<int, int>> q;
                grid[r][c] = '0';                            // sink when enqueued
                q.push({r, c});
                while (!q.empty()) {
                    auto [x, y] = q.front(); q.pop();
                    for (int d = 0; d < 4; ++d) {
                        int nx = x + dr[d], ny = y + dc[d];
                        if (nx >= 0 && nx < R && ny >= 0 && ny < C && grid[nx][ny] == '1') {
                            grid[nx][ny] = '0';
                            q.push({nx, ny});
                        }
                    }
                }
            }
        return islands;
    }
};

int main() {
    int R, C;
    cin >> R >> C;
    vector<vector<char>> g(R, vector<char>(C));
    for (int r = 0; r < R; ++r) {
        string row;
        cin >> row;
        for (int c = 0; c < C; ++c) g[r][c] = row[c];
    }
    cout << Solution().numIslands(g) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int numIslands(char[][] grid) {
        int R = grid.length, C = grid[0].length, islands = 0;
        int[] dr = {1, -1, 0, 0}, dc = {0, 0, 1, -1};
        ArrayDeque<int[]> q = new ArrayDeque<>();
        for (int r = 0; r < R; r++)
            for (int c = 0; c < C; c++) {
                if (grid[r][c] != '1') continue;
                islands++;
                grid[r][c] = '0';
                q.add(new int[]{r, c});
                while (!q.isEmpty()) {
                    int[] cell = q.poll();
                    for (int d = 0; d < 4; d++) {
                        int nx = cell[0] + dr[d], ny = cell[1] + dc[d];
                        if (nx >= 0 && nx < R && ny >= 0 && ny < C && grid[nx][ny] == '1') {
                            grid[nx][ny] = '0';
                            q.add(new int[]{nx, ny});
                        }
                    }
                }
            }
        return islands;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int R = in.nextInt(), C = in.nextInt();
        char[][] g = new char[R][];
        for (int r = 0; r < R; r++) g[r] = in.next().toCharArray();
        System.out.println(new Solution().numIslands(g));
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
4 5
11110
11010
11000
00000
out:
1
-->
<!-- test
in:
4 5
11000
11000
00100
00011
out:
3
-->
<!-- test
in:
1 1
0
out:
0
-->
<!-- test
in:
3 3
101
010
101
out:
5
-->

### Example 2 — Rotting Oranges · Medium

- **Source:** [LC 994 · Rotting Oranges](https://leetcode.com/problems/rotting-oranges/) — Medium · `G75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** a grid ($\le 10 \times 10$) of 0 (empty), 1 (fresh), 2 (rotten). Each minute, fresh oranges adjacent to rotten ones rot. Return the minutes until no fresh orange remains, or $-1$ if that never happens.
- **Thinking from first principles:** the minute an orange rots is its BFS distance to the **nearest** initially rotten orange. That is multi-source BFS: start the queue with all rotten oranges at time 0. Process the queue level by level, where each level is one minute. The answer is the number of levels in which something rotted. If any fresh orange is never reached, it is isolated, so return $-1$. Corner case: no fresh oranges at all gives 0, even with no rotten ones.

<details><summary>Solution</summary>

Count the fresh oranges first. BFS by levels, decrementing `fresh` as oranges rot, and count a minute only when a level rots something. $O(RC)$ time and space. The driver reads `R C` and the grid as integers.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int orangesRotting(vector<vector<int>>& grid) {
        int R = grid.size(), C = grid[0].size(), fresh = 0, minutes = 0;
        queue<pair<int, int>> q;
        for (int r = 0; r < R; ++r)
            for (int c = 0; c < C; ++c) {
                if (grid[r][c] == 2) q.push({r, c});            // all sources at time 0
                else if (grid[r][c] == 1) ++fresh;
            }
        const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
        while (!q.empty() && fresh > 0) {
            int levelSize = q.size();
            for (int i = 0; i < levelSize; ++i) {               // one minute
                auto [r, c] = q.front(); q.pop();
                for (int d = 0; d < 4; ++d) {
                    int nr = r + dr[d], nc = c + dc[d];
                    if (nr >= 0 && nr < R && nc >= 0 && nc < C && grid[nr][nc] == 1) {
                        grid[nr][nc] = 2;
                        --fresh;
                        q.push({nr, nc});
                    }
                }
            }
            ++minutes;
        }
        return fresh == 0 ? minutes : -1;
    }
};

int main() {
    int R, C;
    cin >> R >> C;
    vector<vector<int>> g(R, vector<int>(C));
    for (auto& row : g) for (int& x : row) cin >> x;
    cout << Solution().orangesRotting(g) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int orangesRotting(int[][] grid) {
        int R = grid.length, C = grid[0].length, fresh = 0, minutes = 0;
        ArrayDeque<int[]> q = new ArrayDeque<>();
        for (int r = 0; r < R; r++)
            for (int c = 0; c < C; c++) {
                if (grid[r][c] == 2) q.add(new int[]{r, c});
                else if (grid[r][c] == 1) fresh++;
            }
        int[] dr = {1, -1, 0, 0}, dc = {0, 0, 1, -1};
        while (!q.isEmpty() && fresh > 0) {
            int levelSize = q.size();
            for (int i = 0; i < levelSize; i++) {
                int[] cell = q.poll();
                for (int d = 0; d < 4; d++) {
                    int nr = cell[0] + dr[d], nc = cell[1] + dc[d];
                    if (nr >= 0 && nr < R && nc >= 0 && nc < C && grid[nr][nc] == 1) {
                        grid[nr][nc] = 2;
                        fresh--;
                        q.add(new int[]{nr, nc});
                    }
                }
            }
            minutes++;
        }
        return fresh == 0 ? minutes : -1;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int R = in.nextInt(), C = in.nextInt();
        int[][] g = new int[R][C];
        for (int r = 0; r < R; r++) for (int c = 0; c < C; c++) g[r][c] = in.nextInt();
        System.out.println(new Solution().orangesRotting(g));
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
2 1 1
1 1 0
0 1 1
out:
4
-->
<!-- test
in:
3 3
2 1 1
0 1 1
1 0 1
out:
-1
-->
<!-- test
in:
1 2
0 2
out:
0
-->
<!-- test
in:
1 1
0
out:
0
-->
<!-- test
in:
1 5
2 1 1 1 2
out:
2
-->

### Example 3 — Course Schedule II · Medium

- **Source:** [LC 210 · Course Schedule II](https://leetcode.com/problems/course-schedule-ii/) — Medium · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** $n \le 2000$ courses and pairs `[a, b]` meaning "take $b$ before $a$". Return any valid order of all courses, or an empty array if impossible. ([LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium asks only whether it is possible.)
- **Thinking from first principles:** build the graph $b \to a$. A valid order is a topological order, which exists iff the graph is acyclic (§1.3). Kahn's algorithm produces it directly and detects the cycle case by a short count. DFS with three colours works too. Kahn is easier to explain, and it avoids recursion depth issues. Many orders can be valid, so the driver below *checks* the returned order instead of comparing it with a fixed one.

<details><summary>Solution</summary>

In-degree array plus a queue of courses with no remaining prerequisites. $O(V + E)$ time and space. The driver prints `valid <n>` if the order is a permutation that respects every prerequisite, `impossible` if the solution returns an empty array, and `INVALID` otherwise (so a wrong answer cannot pass).

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> findOrder(int numCourses, vector<vector<int>>& prerequisites) {
        vector<vector<int>> adj(numCourses);
        vector<int> indeg(numCourses, 0), order;
        for (auto& p : prerequisites) { adj[p[1]].push_back(p[0]); indeg[p[0]]++; }   // b -> a
        queue<int> q;
        for (int u = 0; u < numCourses; ++u) if (indeg[u] == 0) q.push(u);
        while (!q.empty()) {
            int u = q.front(); q.pop();
            order.push_back(u);
            for (int v : adj[u]) if (--indeg[v] == 0) q.push(v);   // last prerequisite met
        }
        if ((int)order.size() < numCourses) return {};             // a cycle blocks the rest
        return order;
    }
};

int main() {
    int n, m;
    cin >> n >> m;
    vector<vector<int>> pre(m, vector<int>(2));
    for (auto& p : pre) cin >> p[0] >> p[1];
    vector<int> order = Solution().findOrder(n, pre);
    if (order.empty()) { cout << "impossible\n"; return 0; }
    vector<int> pos(n, -1);
    bool ok = (int)order.size() == n;
    for (int i = 0; ok && i < n; ++i) {
        if (order[i] < 0 || order[i] >= n || pos[order[i]] != -1) ok = false;
        else pos[order[i]] = i;
    }
    for (auto& p : pre) if (ok && pos[p[1]] > pos[p[0]]) ok = false;
    cout << (ok ? "valid " + to_string(n) : string("INVALID")) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] findOrder(int numCourses, int[][] prerequisites) {
        List<List<Integer>> adj = new ArrayList<>();
        for (int i = 0; i < numCourses; i++) adj.add(new ArrayList<>());
        int[] indeg = new int[numCourses], order = new int[numCourses];
        for (int[] p : prerequisites) { adj.get(p[1]).add(p[0]); indeg[p[0]]++; }
        ArrayDeque<Integer> q = new ArrayDeque<>();
        for (int u = 0; u < numCourses; u++) if (indeg[u] == 0) q.add(u);
        int k = 0;
        while (!q.isEmpty()) {
            int u = q.poll();
            order[k++] = u;
            for (int v : adj.get(u)) if (--indeg[v] == 0) q.add(v);
        }
        return k == numCourses ? order : new int[0];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int[][] pre = new int[m][2];
        for (int i = 0; i < m; i++) { pre[i][0] = in.nextInt(); pre[i][1] = in.nextInt(); }
        int[] order = new Solution().findOrder(n, pre);
        if (order.length == 0) { System.out.println("impossible"); return; }
        int[] pos = new int[n];
        Arrays.fill(pos, -1);
        boolean ok = order.length == n;
        for (int i = 0; ok && i < n; i++) {
            if (order[i] < 0 || order[i] >= n || pos[order[i]] != -1) ok = false;
            else pos[order[i]] = i;
        }
        for (int[] p : pre) if (ok && pos[p[1]] > pos[p[0]]) ok = false;
        System.out.println(ok ? "valid " + n : "INVALID");
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
4 4
1 0
2 0
3 1
3 2
out:
valid 4
-->
<!-- test
in:
2 2
1 0
0 1
out:
impossible
-->
<!-- test
in:
1 0
out:
valid 1
-->
<!-- test
in:
3 3
0 1
1 2
2 1
out:
impossible
-->

### Example 4 — Redundant Connection · Medium

- **Source:** [LC 684 · Redundant Connection](https://leetcode.com/problems/redundant-connection/) — Medium · `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** a tree on nodes $1..n$ ($n \le 1000$) plus one extra edge, given as an edge list. Return an edge whose removal leaves a tree. If several work, return the one that appears **last** in the input.
- **Thinking from first principles:** the extra edge creates exactly one cycle, and removing any edge on that cycle yields a tree. Which of them appears last? Process the edges in input order with union-find. The first edge whose endpoints are already connected closes the cycle, and every other cycle edge appeared before it (otherwise the cycle would not be closed yet). So that edge is the last cycle edge in the input, which is exactly the required answer. DFS per edge would be $O(n^2)$. DSU is $O(n \, \alpha(n))$.

<details><summary>Solution</summary>

Return the first edge where `unite` fails. The driver reads $n$ (= number of edges) and the edges, and prints `u v`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> findRedundantConnection(vector<vector<int>>& edges) {
        int n = edges.size();
        vector<int> parent(n + 1), sz(n + 1, 1);
        iota(parent.begin(), parent.end(), 0);
        auto find = [&](int x) {
            while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; }
            return x;
        };
        for (auto& e : edges) {
            int a = find(e[0]), b = find(e[1]);
            if (a == b) return e;                     // already connected: this edge closes the cycle
            if (sz[a] < sz[b]) swap(a, b);
            parent[b] = a;
            sz[a] += sz[b];
        }
        return {};
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> edges(n, vector<int>(2));
    for (auto& e : edges) cin >> e[0] >> e[1];
    vector<int> r = Solution().findRedundantConnection(edges);
    cout << r[0] << ' ' << r[1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    private int[] parent, sz;
    private int find(int x) {
        while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; }
        return x;
    }
    public int[] findRedundantConnection(int[][] edges) {
        int n = edges.length;
        parent = new int[n + 1];
        sz = new int[n + 1];
        for (int i = 0; i <= n; i++) { parent[i] = i; sz[i] = 1; }
        for (int[] e : edges) {
            int a = find(e[0]), b = find(e[1]);
            if (a == b) return e;
            if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
            parent[b] = a;
            sz[a] += sz[b];
        }
        return new int[0];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] edges = new int[n][2];
        for (int i = 0; i < n; i++) { edges[i][0] = in.nextInt(); edges[i][1] = in.nextInt(); }
        int[] r = new Solution().findRedundantConnection(edges);
        System.out.println(r[0] + " " + r[1]);
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
1 2
1 3
2 3
out:
2 3
-->
<!-- test
in:
5
1 2
2 3
3 4
1 4
1 5
out:
1 4
-->
<!-- test
in:
4
3 4
1 2
2 4
1 3
out:
1 3
-->

### Example 5 — Clone Graph · Medium

- **Source:** [LC 133 · Clone Graph](https://leetcode.com/problems/clone-graph/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** given a node of a connected undirected graph (nodes `1..n`, $n \le 100$, each with a neighbour list), return a deep copy.
- **Thinking from first principles:** a deep copy needs a one-to-one map from original nodes to their clones, so that every original edge $u - v$ becomes clone$(u)$ – clone$(v)$ and each node is cloned exactly once even when it is reached along many edges or cycles. Traverse the graph (BFS). The first time a node is seen, create its clone and record it in the map: the map doubles as the visited set. When processing $u$, append clone$(v)$ to clone$(u)$'s neighbour list for each neighbour $v$.

<details><summary>Solution</summary>

$O(V + E)$ time and space. The driver builds the graph from `n` lines `deg v1 .. vdeg`, clones it from node 1, then prints the clone's adjacency in the same format and `deep` if no clone node is an original node.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Node {
public:
    int val;
    vector<Node*> neighbors;
    Node(int v) : val(v) {}
};

class Solution {
public:
    Node* cloneGraph(Node* node) {
        if (!node) return nullptr;
        unordered_map<Node*, Node*> copy;                 // original -> clone; also the visited set
        copy[node] = new Node(node->val);
        queue<Node*> q;
        q.push(node);
        while (!q.empty()) {
            Node* u = q.front(); q.pop();
            for (Node* v : u->neighbors) {
                if (!copy.count(v)) { copy[v] = new Node(v->val); q.push(v); }
                copy[u]->neighbors.push_back(copy[v]);    // keeps the original neighbour order
            }
        }
        return copy[node];
    }
};

int main() {
    int n;
    cin >> n;
    vector<Node*> orig(n + 1);
    for (int i = 1; i <= n; ++i) orig[i] = new Node(i);
    for (int i = 1; i <= n; ++i) {
        int d;
        cin >> d;
        for (int j = 0; j < d; ++j) { int v; cin >> v; orig[i]->neighbors.push_back(orig[v]); }
    }
    Node* c = Solution().cloneGraph(n ? orig[1] : nullptr);
    if (!c) { cout << "empty\n"; return 0; }
    map<int, Node*> byVal;                                // collect clone nodes by value
    set<Node*> originals(orig.begin() + 1, orig.end());
    bool deep = true;
    queue<Node*> q;
    q.push(c);
    byVal[c->val] = c;
    while (!q.empty()) {
        Node* u = q.front(); q.pop();
        if (originals.count(u)) deep = false;
        for (Node* v : u->neighbors) if (!byVal.count(v->val)) { byVal[v->val] = v; q.push(v); }
    }
    for (auto& [val, u] : byVal) {
        cout << u->neighbors.size();
        for (Node* v : u->neighbors) cout << ' ' << v->val;
        cout << '\n';
    }
    cout << (deep ? "deep" : "shallow") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Node {
    public int val;
    public List<Node> neighbors = new ArrayList<>();
    public Node(int v) { val = v; }
}

class Solution {
    public Node cloneGraph(Node node) {
        if (node == null) return null;
        Map<Node, Node> copy = new HashMap<>();
        copy.put(node, new Node(node.val));
        ArrayDeque<Node> q = new ArrayDeque<>();
        q.add(node);
        while (!q.isEmpty()) {
            Node u = q.poll();
            for (Node v : u.neighbors) {
                if (!copy.containsKey(v)) { copy.put(v, new Node(v.val)); q.add(v); }
                copy.get(u).neighbors.add(copy.get(v));
            }
        }
        return copy.get(node);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        Node[] orig = new Node[n + 1];
        for (int i = 1; i <= n; i++) orig[i] = new Node(i);
        for (int i = 1; i <= n; i++) {
            int d = in.nextInt();
            for (int j = 0; j < d; j++) orig[i].neighbors.add(orig[in.nextInt()]);
        }
        Node c = new Solution().cloneGraph(n > 0 ? orig[1] : null);
        if (c == null) { System.out.println("empty"); return; }
        Set<Node> originals = Collections.newSetFromMap(new IdentityHashMap<>());
        for (int i = 1; i <= n; i++) originals.add(orig[i]);
        TreeMap<Integer, Node> byVal = new TreeMap<>();
        boolean deep = true;
        ArrayDeque<Node> q = new ArrayDeque<>();
        q.add(c);
        byVal.put(c.val, c);
        while (!q.isEmpty()) {
            Node u = q.poll();
            if (originals.contains(u)) deep = false;
            for (Node v : u.neighbors) if (!byVal.containsKey(v.val)) { byVal.put(v.val, v); q.add(v); }
        }
        StringBuilder sb = new StringBuilder();
        for (Node u : byVal.values()) {
            sb.append(u.neighbors.size());
            for (Node v : u.neighbors) sb.append(' ').append(v.val);
            sb.append('\n');
        }
        sb.append(deep ? "deep" : "shallow").append('\n');
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
4
2 2 4
2 1 3
2 2 4
2 1 3
out:
2 2 4
2 1 3
2 2 4
2 1 3
deep
-->
<!-- test
in:
1
0
out:
0
deep
-->
<!-- test
in:
0
out:
empty
-->

## 6. Pitfalls and things to remember

1. **Mark visited on push.** Marking on pop lets the same node enter the queue many times. It is still correct for plain reachability but wrong for "count the levels", and slow.
2. **Recursive DFS depth on grids:** $300 \times 300$ cells means up to $9 \cdot 10^4$ frames, which overflows Java's default stack and sometimes C++ on Windows. Use BFS or an explicit stack, or say "I would increase the stack size".
3. **Directed vs undirected:** "prerequisite $[a, b]$" is the edge $b \to a$. Getting the direction backwards reverses the order and still "passes" symmetric samples.
4. **Disconnected graphs:** loop over all nodes as potential starts. Topological sort must seed *every* zero in-degree node.
5. **Undirected cycle detection with DFS:** an edge back to the parent is not a cycle. With multi-edges, track the parent edge, not the parent node.
6. **DSU without the heuristics** degrades to $O(n)$ per `find` on chains. Path compression alone is usually enough in interviews, but name union by size.
7. **0- vs 1-indexed nodes:** LeetCode mixes both (Redundant Connection is 1-indexed). Size arrays `n + 1` when in doubt.
8. **Mutating the input grid** as the visited set is a good trick. Say that you are doing it, and offer a `visited` array if the caller needs the grid intact.
9. **Hash maps keyed by node objects:** fine in C++ (pointer keys) and Java (identity `hashCode` unless overridden). Don't key by `val` if values can repeat.
10. **BFS level counting:** either store distances per node or process level by level with `size = q.size()`. Mixing the two causes off-by-one answers (Rotting Oranges returning 1 instead of 0).

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Islands → "the grid streams in row by row" / "too big for memory" | union-find on two rows at a time; components that stop touching the current row are final |
| Islands → "islands are added one cell at a time, report the count after each" | DSU on cells, +1 per new cell, −1 per successful union ([LC 305 · Number of Islands II](https://leetcode.com/problems/number-of-islands-ii/) — Hard 🔒) |
| Rotting oranges → "return the time each orange rots" | the BFS distance array itself |
| Course schedule → "minimum number of semesters" | Kahn by levels: the number of BFS layers (longest path in the DAG) |
| → "lexicographically smallest order" | Kahn with a min-heap instead of a queue |
| Redundant connection → "directed graph version" | handle "a node with two parents" and cycles separately ([LC 685 · Redundant Connection II](https://leetcode.com/problems/redundant-connection-ii/) — Hard) |
| Clone → "the graph may be disconnected / you get all nodes" | loop over all nodes, reuse the same map |
| "BFS vs DFS: which one and why?" | BFS for shortest unweighted paths and levels; DFS for cycle/topological structure and when memory per level is the concern; either for reachability |
| "Can union-find delete edges?" | no; process offline in reverse (deletions become insertions) or use DSU with rollback ([CP](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Word Ladder, Alien Dictionary and weighted problems are in [advanced graphs](12-advanced-graphs.md).

**Easy** (3)

- [ ] [LC 463 · Island Perimeter](https://leetcode.com/problems/island-perimeter/) — Easy · `NC250`
- [ ] [LC 733 · Flood Fill](https://leetcode.com/problems/flood-fill/) — Easy · `G75`
- [ ] [LC 997 · Find the Town Judge](https://leetcode.com/problems/find-the-town-judge/) — Easy · `NC250`

**Medium** (22)

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

**Beyond the lists:**

- [ ] [LC 1971 · Find if Path Exists in Graph](https://leetcode.com/problems/find-if-path-exists-in-graph/) — Easy — BFS or DSU warm-up
- [ ] [LC 547 · Number of Provinces](https://leetcode.com/problems/number-of-provinces/) — Medium — components from an adjacency matrix
- [ ] [LC 785 · Is Graph Bipartite?](https://leetcode.com/problems/is-graph-bipartite/) — Medium — BFS 2-colouring
- [ ] [LC 886 · Possible Bipartition](https://leetcode.com/problems/possible-bipartition/) — Medium — bipartite with edges as dislikes
- [ ] [LC 802 · Find Eventual Safe States](https://leetcode.com/problems/find-eventual-safe-states/) — Medium — reverse graph + Kahn
- [ ] [LC 934 · Shortest Bridge](https://leetcode.com/problems/shortest-bridge/) — Medium — flood one island, multi-source BFS to the other
- [ ] [LC 1091 · Shortest Path in Binary Matrix](https://leetcode.com/problems/shortest-path-in-binary-matrix/) — Medium — 8-direction BFS
- [ ] [LC 1254 · Number of Closed Islands](https://leetcode.com/problems/number-of-closed-islands/) — Medium — flood the border first
- [ ] [LC 1905 · Count Sub Islands](https://leetcode.com/problems/count-sub-islands/) — Medium — flood fill with a second grid check
- [ ] [LC 990 · Satisfiability of Equality Equations](https://leetcode.com/problems/satisfiability-of-equality-equations/) — Medium — DSU on letters
- [ ] [LC 2101 · Detonate the Maximum Bombs](https://leetcode.com/problems/detonate-the-maximum-bombs/) — Medium — directed reachability from each node

## 9. CP counterpart

- [Graph representation, BFS and DFS](../09-Graphs/01-graph-representation-bfs-dfs.md): adjacency in arrays (CSR), 0-1 BFS, iterative DFS with timestamps.
- [Topological sort and DAG DP](../09-Graphs/04-topological-sort-and-dag-dp.md): longest paths, counting paths, scheduling with levels.
- [DSU and variants](../08-Data-Structures/06-dsu-and-variants.md): weighted DSU (Evaluate Division is a DSU with ratios), DSU on bipartiteness, rollback.
- [Bipartite graphs and cycles](../09-Graphs/09-bipartite-graphs-and-cycles.md): odd cycles, cycle extraction.

Transfers: all of it, with $V$ up to $2 \cdot 10^5$ in CP. Interview difference: build adjacency lists with `vector<vector<int>>` / `List<List<Integer>>` and say why. CP-style edge arrays and global `vis[]` read poorly in an interview.

## 10. Self-check

1. Why does BFS give shortest paths in an unweighted graph? What breaks with weights?
2. Why must you mark visited on push in BFS?
3. How does multi-source BFS relate to a single-source BFS?
4. Prove that Kahn's algorithm leaves nodes unprocessed exactly when there is a cycle.
5. In Redundant Connection, why is the first failing union the last cycle edge in the input?
6. What is the complexity of DSU with path compression and union by size?
7. How do you check that an undirected graph is a tree?
8. In Clone Graph, why is a map from original to clone required, and what does it replace?

<details><summary>Answers</summary>

1. BFS dequeues nodes in non-decreasing distance order, so the first discovery of a node is through a predecessor at distance $d - 1$, which is optimal with unit edges. With weights, a path with more edges can be cheaper, so the first discovery may not be the cheapest (use Dijkstra).
2. Otherwise a node can be enqueued once per incoming edge before it is processed. The answers stay right for reachability, but level counts and complexity break.
3. It is a single-source BFS from a virtual node connected to every source with weight 0: all sources start at distance 0.
4. If there is no cycle, a DAG always has a node with in-degree 0 among the remaining nodes, so Kahn removes everything. If nodes remain, each has an incoming edge from another remaining node. Following incoming edges backwards in a finite set repeats a node, which is a cycle (and a cycle's nodes can never reach in-degree 0).
5. The cycle is closed only when its last edge (in input order) is processed. Before that, the cycle's other edges form a path that connects the endpoints, so `unite` fails exactly at that edge, and no earlier edge fails because the edges before it form a forest.
6. $O(\alpha(n))$ amortised per operation, which is effectively constant.
7. It has exactly $n - 1$ edges and is connected (or: no union fails while adding all edges, and there are $n - 1$ of them).
8. Every node must be cloned exactly once, and edges must point to clones, not originals. The map provides both, and it also serves as the visited set of the traversal.

</details>
