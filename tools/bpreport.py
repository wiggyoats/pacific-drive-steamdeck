#!/usr/bin/env python3
# bpreport.py A B [N]: diff two pd_prof.txt snapshots (names come from the profiler), print ms/frame-ish table
import sys, collections
dnames = {}
def load(p):
    L = open(p).read().split("\n")
    h = L[0].split(); qpc, qf, tsc = int(h[1]), int(h[2]), int(h[4])
    d = {}
    for l in L[1:]:
        if l.strip():
            a, c, i, e, n = (l.split(" ", 4) + [""])[:5]; d[int(a, 16)] = (int(c), int(i), int(e)); dnames[int(a, 16)] = n
    return qpc, qf, tsc, d
qa, qf, ta, A = load(sys.argv[1]); qb, _, tb, B = load(sys.argv[2])
secs = (qb - qa) / qf; tps = (tb - ta) / secs
names = dnames
rows = []
for k, (c, i, e) in B.items():
    c0, i0, e0 = A.get(k, (0, 0, 0))
    rows.append((e - e0, i - i0, c - c0, names.get(k, hex(k))))
tot_excl = sum(r[0] for r in rows)
print(f"window {secs:.1f} s, TSC {tps/1e9:.3f} GHz; Blueprint exclusive time on game thread: {100*tot_excl/tps/secs:.1f}% of wall time")
N = int(sys.argv[3]) if len(sys.argv) > 3 else 40
print(f"{'excl%':>6} {'incl%':>6} {'calls/s':>8}  function")
for e, i, c, n in sorted(rows, reverse=True)[:N]:
    print(f"{100*e/tps/secs:6.2f} {100*i/tps/secs:6.2f} {c/secs:8.0f}  {n.replace('/Game/', '')}")
# group exclusive time by Blueprint class
g = collections.Counter()
for e, i, c, n in rows: g[n.split(":")[0].split(".")[-1]] += e
print("\nby Blueprint class (exclusive):")
for n, e in g.most_common(20): print(f"{100*e/tps/secs:6.2f}  {n}")
