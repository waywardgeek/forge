# Interface Redesign v2 — Implementation Plan

*For the implementing agent (expected: Claude Opus 4.6). Written
2026-07-03 by CodeRhapsody, reviewed by Bill.*

**Read first, in this order:**
1. `cr/docs/interface-redesign-v2.md` — the design. Read ALL of it.
   The Overview explains why; §13 gives you a leaning for every open
   question (try the leaning first; document departures in that doc).
2. `cr/docs/lyric-language-reference.md` — what the language does today.
3. Each `src/<pkg>/<pkg>.ly.lyric` companion file before editing that
   directory (CDD gate enforces this).
4. `cr/docs/multi-class-interface-redesign.md` §3–§4 — the surviving
   prior art (labels-as-scopes, UFCS). Its Wave 2 and 4w1-a are DEAD;
   do not implement anything from its §9 that conflicts with v2.

---

## 0. Ground rules (violating these wastes days — history proves it)

- **Two-repo protocol**: this project changes how existing source
  compiles. Land EVERYTHING in `~/projects/lyric-next` first, verify
  fixed point, then ff-merge to `~/projects/lyric`. Before starting:
  `cd ~/projects/lyric-next && git pull --ff-only`. Check both repos
  at the same HEAD before claiming anything shipped.
- **Bootstrap**: `make lyric` (build from checked-in lyric.c) →
  `make update` (regen) → `make self-test` (fixed point — SACRED).
  If a `.ly` change breaks the build, the binary is stale:
  `git checkout HEAD -- lyric.c && make clean && make -s lyric && make update`.
  New keywords / syntax the old binary can't parse ⇒ 2-pass bootstrap.
  After `make update`, `sleep 1` before rebuilding (same-second mtime
  skips rebuild and you'll debug a stale binary).
- **Test baseline**: `./test_lyric.sh` currently **94 PASS / 5 FAIL /
  99 TOTAL**. Known FAILs: `global_dict_rc.ly`, `graph.ly`, `lock.ly`,
  `optional_struct_writeback.ly`, `tree.ly`. NEVER regress a PASS.
  This plan should convert `graph.ly` and `tree.ly` to PASS by the end.
- **Testdata convention**: every `testdata/*.ly` must pass — no
  expect-fail files. Diagnostic/negative tests go in
  `/tmp/lyric_probes/*.ly`, verified manually. Write probes with
  `run_command` heredoc (`cat > /tmp/lyric_probes/x.ly << 'EOF'`),
  not write_file (CDD gate blocks /tmp). /tmp is noexec — run probe
  binaries from the repo dir.
- **Panic, don't fall back.** When a pass can't resolve something it
  should be able to resolve, panic with a message naming what was
  missing and what called it. NO `void*`, `unknown_*`, `LTyAny`,
  silent skips. Every historical multi-week bug in this codebase was
  a fallback.
- **Commit pattern**: source-only commits per substep; ONE `lyric.c`
  regen commit at the end of each phase. Author:
  `git -c user.name='CodeRhapsody' -c user.email='coderhapsody@coderhapsody.local' commit ...`
- **ASAN**: run the ASAN build on new runtime-touching tests before
  declaring a phase done.
- **When stuck or surprised**: STOP and ask Bill. Do not hack the
  compiler to accept a bad test, and do not weaken a test to match
  the compiler. Both have happened; both were expensive.
- **The vtable/fat-pointer path is MANDATORY, not an optimization
  detail** (Bill, 2026-07-05). Even though the §9 specialization
  mandate means most (currently all) call sites monomorphize to
  direct calls, the erased emission must be built for real in
  Phases 1–2. Two reasons: (a) it is the differential-testing oracle
  for the specializer; (b) it keeps the family model load-bearing —
  if fat pointers exist end-to-end, `Graph.G` must be a real type,
  the chase must produce real vtable layouts, and brands must be
  real type kinds, so a low-context session CANNOT substitute
  "generic top-level functions + hope the monomorphizer copes."
  That substitution is the v1 relapse; do not take it even as a
  temporary scaffold.
- **Anti-laziness fence — negative probes are acceptance criteria.**
  Generic functions cannot express families: if `Graph.N` is modeled
  as an ordinary type var, brands unify and these probes compile
  when they MUST NOT. At each phase end, verify the applicable
  probes still FAIL to compile with the correct diagnostic:
  (1) brand mixing — `a_side` algorithm receiving a `b_side.N`
  (Phase 3); (2) unqualified boxing when only named impls exist
  (Phase 3); (3) §6.1 rebind contradiction (Phase 4); (4) chase
  failure showing the full inferred-binding chain, not a generic
  "type mismatch" (Phase 2); (5) runtime-varying interface value in
  an unsupported position gets a clear diagnostic, never a silent
  fallback (all phases).

---

## Phase map

| Phase | Deliverable | Depends on |
|---|---|---|
| 0 | Audit + scaffolding decisions recorded | — |
| 1 | Single-param interface types: boxing, vtables, structural chase (`error` unified) | 0 |
| 2 | Multi-param erased families: `Graph.G/.N/.E`, defaults compiled once, `gen` surfaces | 1 |
| 3 | Impl ladder: anonymous impl alias bindings (incl. labeled-scope RHS), named impls + brands, coherence rules | 2 |
| 4 | `where` refinement: vtable prefixes, overrides, transitive impl binding, value params | 3 |
| 5 | Relation unification: relation ⇒ named-impl desugar, generic relation templates, hint-fit diagnostics | 3 (parallel with 4) |
| 6 | Acid tests green: `graph.ly`, `tree.ly` rewritten and PASSING; `extends` removed; docs updated | 4 + 5 |

Each phase ends with: suite ≥ baseline, `make self-test` fixed point,
one regen commit, and a short progress note appended to this file.

---

## Phase 0 — Audit and scaffolding (no behavior change)

Goal: know the terrain; make the cheap reversible decisions.

1. Inventory the June 2026 vtable prototype: find the boxed-value /
   static-vtable code paths used for `error` dispatch in
   `src/c_backend/` and `src/lowerer/` (search: `vtable`, `boxed`,
   `fat`). Record in a progress note what exists and what's dead.
2. Grep usage counts: `extends` in interfaces, `-> [N]` in interface
   surfaces, `impl ` blocks in stdlib + testdata. These size the
   Phase 6 migration.
3. Decide fat-pointer C representation and write it into
   `runtime/lyric_runtime.h` as types only (no users yet):
   `typedef struct { void* data; const void* vt; } ly_iface;`
   (SoA variant deferred to a follow-up — see design §13.4).
4. AST: add skeleton nodes (parse nothing yet): `InterfaceTypeExpr`
   (`Iface.Member`, brand-qualified `name.Member`), `ImplDecl.name`
   (optional brand), vtable-layout metadata slot on interface decls.
   Update `.ly.lyric` companions + invariants.

Exit: suite unchanged, self-test fixed point, notes committed.
Size: small (≤300 LOC). Risk: low.

## Phase 1 — Single-param interface types (unify `error`)

Goal: `Printable`-style one-param interfaces usable in type position;
`error` becomes an ordinary instance of the mechanism.

1. **Parser/AST**: `InterfaceName` in type position for single-param
   interfaces (bare name = the one family member). `Iface.T` form
   parses too.
2. **Checker**: structural satisfaction by signature match (single
   class — no chase yet). Lazy: check at boxing sites (assignment,
   arg passing, explicit `as`). `implements I` on a class = eager
   assertion using the same checker path. Diagnostic lists ALL
   unsatisfied members in one error.
3. **Lowerer/C backend**: boxing coercion emits `(ly_iface){obj, &VT}`;
   static vtable per (class, interface) emitted on demand (dedupe by
   name); interface-typed calls become indirect calls. Type switch
   (`match x { Concrete => ... }`) on interface values via vtable
   identity compare.
4. Migrate `error` onto this path; delete its special-case dispatch.
   `any` = empty-surface interface on the same rails.
5. Tests: `testdata/iface_single.ly` (boxing, calls, type switch,
   heterogeneous `[Printable]` slice); probes for: unsatisfied member
   diagnostic, `implements` assertion failure.

Exit: suite ≥ baseline (error tests still green via new path).
Size: medium (~800–1200 LOC). Risk: medium — the error migration is
the regression hazard; keep the old path deletable in one commit so
bisection is clean.

## Phase 2 — Multi-param erased families + defaults-once

Goal: `Graph.G/.N/.E` types; default methods compiled once over fat
pointers. This dissolves old 4w1-a.

1. **Parser**: `Iface.Member` type expressions for multi-param
   interfaces; `gen T` already parses.
2. **Checker — signature chase** (design §3): from the anchor binding,
   chase member signatures to bind sibling type vars; verify loop
   closure. One diagnostic showing the whole chase on failure. The
   family classifier: receiver-position params = family; others =
   value params (Phase 4 finishes value params; here they may be
   rejected with "not yet supported" — panic-style, not silent).
3. **Vtable layout**: one vtable per (class-tuple, interface,
   anonymous-impl) covering all family members' methods + field
   accessors used by default bodies. Layout metadata on the interface
   decl (slot order = declaration order; prefix space reserved for
   Phase 4).
4. **Default methods**: compile each interface default ONCE as a C
   function over `ly_iface` params. Inside default bodies: member
   calls = indirect via the receiver's vtable; `field` access =
   getter/setter slots. `gen`-returning members: yielded values box
   on yield (homogeneous vtable — reuse the boxing coercion).
5. **Call sites**: `net.count_edges()` auto-boxes the receiver when
   the anchor satisfies the interface (UFCS tier 2 — see design §8;
   resolution order: class method → interface default → free
   function; same-tier ambiguity = error).
6. Free functions over interface types (`func min_cut(g: Graph.G, ...)`)
   need nothing new — they're ordinary functions once `Graph.G` is a
   type; add a test proving it.
7. Tests: `testdata/iface_family.ly` — a small DirectedGraph over
   slice-backed classes, structural (Level 0), default BFS/count,
   free-function + UFCS call. Probes: chase-failure diagnostic,
   ambiguous UFCS.

Exit: suite ≥ baseline; family interfaces usable end-to-end at
Level 0.
Size: large (~1500–2500 LOC). Risk: HIGH — this is the heart.
Sub-risks: generator-of-boxed-values plumbing; devirtualization is
explicitly OUT of scope (correctness first; optimizer later).

## Phase 3 — The impl ladder: anonymous, named, brands, coherence

Goal: design §4 + §5 complete.

1. **Anonymous impl blocks**: alias bindings `T.member =
   Concrete.accessor` populate vtable slots (replacing structural
   lookup for those members); mixed-mode auto-derive fills the rest.
   RHS grammar per design §13.2 leaning: a name (`Concrete.member` or
   `Concrete.label.member`), exact signature match after
   substitution, near-miss = error naming both signatures. The
   labeled-scope RHS (`Net.routes.iter`, `Via.src.parent`) resolves
   through the existing Phase-3e dotted-scope machinery.
2. **Named impls**: `impl name: Iface<...> { ... }` parses; declares
   brand namespace: `name.G` etc. are distinct checker types sharing
   the runtime rep. Brand widening `name.G → Iface.G` implicit;
   cross-brand mixing = error. Boxing vs accepting rule (design
   §4.2): unqualified boxing = anonymous impl or error listing the
   named candidates; parameter positions are existential.
3. **Coherence**: one anonymous impl per (interface, tuple) —
   program-wide check at desugar; orphan rule (impl's package must
   own the interface or ≥1 participating class); named impls
   invisible unless named (this falls out of brand scoping — verify
   with a probe, don't build extra machinery).
4. Tests: `testdata/iface_impls.ly` — renamed-member impl; two named
   impls over one class triple (mini FPGA a_side/b_side); brand
   mixing probe (error); duplicate-anonymous probe (error); orphan
   probe (error).

Exit: suite ≥ baseline. Size: large (~1200–2000 LOC).
Risk: medium-high — brand types touch the checker's type-equality
core; add them as a wrapper kind (`TyBranded(brand, inner)`) with
explicit equality rules, never by name mangling.

## Phase 4 — `where` refinement + value parameters

Goal: design §6 + §2.1 complete; `extends` replaceable.

1. **Interface `where` clauses**: `interface WDG<G,N,E,W> where
   DG<G,N,E>, Numeric<W>`. Parent surface in scope for bodies and
   satisfaction chase.
2. **Vtable prefixes**: parent vtable = prefix of child vtable;
   upcast = same fat pointer, no conversion. Override: child
   re-declaration replaces the PREFIX slot.
3. **Value params**: monomorphize interface families per value-param
   binding (`WDG<f32>.G`); reuse the generic-specialization
   machinery. Method on a value param = error unless a constraint
   provides it. `Numeric<W>` built-in constraint (old plan Phase 5 —
   fold the minimum needed here; literals against concrete W do most
   of the work).
4. **Transitive impl binding** (design §6.1): impl of refined
   interface may bind parent members; three-case rule (establishes /
   must-agree / named-propagates). The must-agree check compares
   against the existing anonymous satisfaction and errors on
   contradiction.
5. Tests: `testdata/iface_refine.ly` — WeightedDirectedGraph over the
   Phase 2 graph; total_weight with W ∈ {i32, f64}; DG algorithm
   running on a WDG value through the prefix; override probe;
   rebind-contradiction probe.

Exit: suite ≥ baseline. Size: large (~1200–2000 LOC). Risk: medium.

## Phase 5 — Relation unification (parallel-safe with Phase 4)

Goal: design §7 complete; the textual injection layer dies.

1. **Desugar `relation` → named impl**: `relation Hint P:pl owns
   [C:cl]` produces the same internal ImplDecl as `impl pl_cl: Hint
   <P:pl, C:cl> owns {}` (brand = label pair). Keep the surface
   syntax and the dotted-scope access EXACTLY as today — this phase
   changes internals only; the existing relation tests are the
   regression harness.
2. **Flattened strategy stays**: field injection, monomorphized
   accessors, destructor pairs — reuse today's machinery but drive
   it from the ImplDecl, not from the bespoke RelationDecl path.
   Collapse RelationDecl post-desugar (old redesign §3.9 finally
   lands).
3. **Generic relations = partial-impl templates**: route
   `relation HashedList Dict<K,V>:d owns [DictEntry<K,V>:d]` through
   the 4w1-d partial-impl machinery with `where Hashable<K>`
   propagated from the class decl. Delete the bespoke generic-
   relation type-arg threading as it becomes dead — this is where
   the TypeArgs bug lineage dies; expect to find and remove several
   defensive patches.
4. **Hint-fit diagnostics**: bad hint (wrong arity, cross-side
   references, missing abstract member on the concrete class) = hard
   error at the `relation` line. Delete the silent skip.
5. **Hint default methods get `iter`**: add `pub func P.iter(self) ->
   gen C` defaults to ArrayList/DoublyLinked/HashedList in stdlib so
   §7.3 bindings work.
6. Tests: full existing relation suite (the real test); plus
   `testdata/relation_as_impl.ly` — relation-backed DirectedGraph
   via five alias lines (the design §7.3 example); Dict regression
   tests must stay green.

Exit: suite ≥ baseline, Dict/relation tests green, RelationDecl gone
after desugar. Size: large (~1000–1800 LOC net, likely NEGATIVE
after deletions settle). Risk: HIGH — Dict is load-bearing for the
compiler itself; bootstrap breaks here if the desugar is wrong.
Mitigation: keep each substep bootstrappable; regen + self-test after
every substep, not just at phase end.

## Phase 6 — Acid tests, `extends` removal, docs

1. Rewrite `testdata/graph.ly` and `testdata/tree.ly` against the new
   design (design §11; expect FEWER lines — that's falsifiable claim
   #1). Both must PASS. Baseline becomes 96/3.
2. Remove `extends` from the parser/checker/desugar; migrate the few
   users to `where`. (2-pass bootstrap if stdlib uses it.)
3. Migrate `-> [N]` interface surfaces to `-> gen N` where the design
   requires it.
4. Update `cr/docs/lyric-language-reference.md` §11–12 and
   `cr/docs/lyric-language-spec.md` interface/relation sections to
   match reality. Update `.ly.lyric` companions with new invariants.
5. Verify the falsifiable claims in the design doc's Overview; record
   the results (line counts, LOC deleted vs added) in a progress note.
   If a claim failed, say so plainly — that's signal, not shame.

Exit: 96 PASS / 3 FAIL / 99; self-test fixed point; both repos at the
same HEAD; docs true.

---

## Standing guidance for the implementer

- **Order within a phase**: parser → AST (+ .lyric companion) →
  checker → desugar → lowerer/backend → tests. Get ONE example
  end-to-end before generalizing (minimum viable, then grow).
- **Try the smallest thing end to end before adding infrastructure.**
  Bill's "minimum viable?" question has repeatedly saved 200+ LOC.
- **The checker owns truth.** Any information a later pass needs
  (impl identity, brand, vtable layout, family bindings) must be
  recorded on AST/registry structures by the checker/desugar — never
  re-derived from names downstream.
- **Ask Bill** at these specific checkpoints: before Phase 5 starts
  (Dict risk) and before deleting `extends` (Phase 6). (Design §13.6
  label collisions is now SETTLED — two-tier namespace, 2026-07-05;
  see the design doc.) Also whenever a design ambiguity survives contact
  with real code: the design doc §13 records your resolution.
- **Progress notes**: append a dated note to this file at each phase
  end — what shipped, what was deleted, surprises, deviations from
  the leanings and why.
