# Interface Redesign v2 — Implementation Plan

*For the implementing agent (expected: Claude Opus 4.6). Written
2026-07-03 by CodeRhapsody, reviewed by Bill. Revised same day after
design review with Claude Sonnet 4.6. Expanded 2026-07-03 with
concrete per-phase code audit.*

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

- **Two-repo protocol**: `lyric-next` is a local git clone with
  `origin = ~/projects/lyric`. **All source changes happen in
  `lyric-next`**. The stable compiler binary lives in `lyric/` and
  stays untouched until you achieve a verified fixed point in
  `lyric-next/`.

  **Mechanical workflow**:
  1. `cd ~/projects/lyric-next && git pull --ff-only` — sync ceiling
     to floor.
  2. Edit `.ly` source in `lyric-next/`.
  3. Build using the FLOOR binary: `lyric-next/` `Makefile` runs
     `./lyric` which is the checked-in binary (compiled from the
     stable `lyric.c`). `make lyric` builds from `lyric.c`;
     `make update` runs that binary on `src/**/*.ly` to regenerate
     `lyric.c`.
  4. `make self-test` — the stage-2 `lyric.c` compiles itself and the
     output must match. This is the fixed-point test.
  5. **Only after fixed point passes**: commit in `lyric-next`, then
     `cd ~/projects/lyric && git pull --ff-only` to bring the floor
     up. Now `lyric/` has the new compiler.
  6. Check both repos at the same HEAD before claiming shipped.

  **Why this matters**: if your `.ly` changes introduce new syntax the
  old `./lyric` binary can't parse, the build in step 3 fails. That's
  the signal to use 2-pass bootstrap (see below). If you edited
  `lyric/` directly and broke the binary, you'd have no working
  compiler to recover with.

- **Bootstrap**: `make lyric` (build from checked-in lyric.c) →
  `make update` (regen) → `make self-test` (fixed point — SACRED).
  If a `.ly` change breaks the build, the binary is stale:
  `git checkout HEAD -- lyric.c && make clean && make -s lyric && make update`.

  **2-pass bootstrap** (when new syntax breaks the old binary):
  The old `./lyric` can't parse the new `.ly` source. Solution:
  1. Make the new syntax OPTIONAL first — the old binary can still
     parse the source, just ignores the new constructs.
  2. `make update` with the old binary → new `lyric.c` that
     understands the new syntax.
  3. `make lyric` to build the new binary from the new `lyric.c`.
  4. Now use the NEW binary to compile source that uses the new syntax.
  5. `make update && make self-test` to verify fixed point.

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
| 5 | Relation unification: relation ⇒ named-impl desugar, generic relation templates, hint-fit diagnostics | **4** |
| 6 | Acid tests green: `graph.ly`, `tree.ly` rewritten and PASSING; `extends` removed; docs updated | 5 |

**Phase 5 is sequential after Phase 4**, not parallel. Both phases
modify vtable layout, ImplDecl structures, and the checker's
satisfaction machinery. Parallel work on shared data structures
invites merge conflicts and subtle invariant violations that only
surface at bootstrap time — when they're most expensive to debug.

Each phase ends with: suite ≥ baseline, `make self-test` fixed point,
one regen commit, and a short progress note appended to this file.

---

## Phase 0 — Audit and scaffolding (no behavior change)

Goal: know the terrain; make the cheap reversible decisions.

### 0.1 Inventory existing vtable / interface dispatch code

**c_backend** (`src/c_backend/c_backend.ly`):
- `CGen.iface_by_name: Dict<Sym, LInterfaceDecl>?` — already indexes
  interfaces (populated in `new_cgen`, line ~87).
- `CGen.impl_map: Dict<Sym, [string]>?` — maps interface name to list
  of implementing class names. Used for vtable instance emission.
- Vtable struct emission: search for `vtable` in `emit_c` (line ~5227).
  The June 2026 prototype emits per-(class, interface) static vtable
  instances as C structs of function pointers. The vtable struct itself
  is named `<iface>_vtable_t`; instances are
  `<class>_<iface>_vtable`.
- Interface dispatch: `emit_method_call_expr` (line ~2205) checks
  `iface_by_name` and emits indirect calls through vtable slots.
- Boxing: `emit_call_expr` (line ~2129) handles auto-boxing for
  interface-typed parameters — wraps `(ly_iface){obj, &vtable}`.

**lowerer** (`src/lowerer/lowerer.ly`):
- `Lowerer.lowered_ifaces: Dict<Sym, LInterfaceDecl>?` — populated by
  `lower_interface_decl` (line ~670).
- `lower_interface_decl` (line ~670) → produces `LInterfaceDecl` with
  method signatures for vtable layout.
- `lower_impl_block` (line ~701) → produces forwarding wrapper
  `LFuncDecl`s and populates `impl_method_renames`. This is the core
  code that will need extension for vtable slot population.
- Interface-typed calls route through `impl_method_renames` — keyed
  by `class_name.method_name` → mangled wrapper name.

**lir** (`src/lir/lir.ly`):
- `LInterfaceDecl` (line ~665): `name`, `methods: [LInterfaceMethod]`,
  `type_params: [LTypeParam]`, `is_exported`.
- `LInterfaceMethod` (line ~658): `name`, `params: [LParam]`,
  `receiver_type: string`, `return_type: LType?`.
- No `LTyInterface` / `LTyFatPointer` kind exists in `LTypeKind` yet.
  Interface values are currently dispatched via the rename map, not via
  fat pointers.

**checker** (`src/checker/checker.ly`):
- `TypeKind.Interface(name: string)` — exists but only used for `error`
  and `any` today. The checker's `is_assignable` handles Interface as
  a structural subtype check (line ~570).
- Interface satisfaction is currently checked structurally in
  `is_assignable` (searches for methods by name/signature).
- No lazy-at-boxing-site checking; satisfaction is checked on every
  assignment/call.

**runtime** (`runtime/lyric_runtime.h`):
- No `ly_iface` or fat pointer typedef exists yet.
- No vtable struct infrastructure. The runtime currently has slab
  allocators, string ops, channel ops, and test harness.

### 0.2 Grep usage counts for migration sizing

Run these before starting:
```bash
cd ~/projects/lyric
grep -rn 'extends ' src/ stdlib/ testdata/ --include='*.ly' | grep -v '\.lyric' | wc -l
grep -rn '\-> \[' src/ stdlib/ testdata/ --include='*.ly' | grep 'interface\|impl' | wc -l
grep -rn '^impl ' src/ stdlib/ testdata/ --include='*.ly' | grep -v '\.lyric' | wc -l
```

### 0.3 Fat pointer C representation

Add to `runtime/lyric_runtime.h` (types only, no users yet):
```c
/* Interface fat pointer: (data pointer, vtable pointer) */
typedef struct {
    void* _data;
    const void* _vt;
} ly_iface;
```

SoA variant (`uint32_t _handle` instead of `void* _data`) is deferred
per design §13.4 leaning.

### 0.4 AST skeleton nodes

**ast.ly** — add these types/fields:

1. **New TypeExprKind variant**: `InterfaceType(iface_name: Sym,
   member_name: Sym?, brand: Sym?)` — represents `Iface.Member` and
   `brand.Member` in type position. `member_name == null` means bare
   interface name (single-param case). `brand == null` means unbranded.
   Add to the TypeExprKind enum (line ~28).

2. **ImplBlock.name: Sym?** — optional brand/name for named impls
   (Level 2). `null` = anonymous. Add after `for_type` (line ~226).

3. **InterfaceDecl** changes:
   - Add `where_clauses: [InterfaceWhereClause]` — for Phase 4's
     `where` on interfaces. Can be empty initially. (Separate from
     existing `WhereClause` which is for functions.)
   - Add `vtable_layout: [VtableSlot]?` — populated by the checker,
     consumed by the lowerer. null until computed.
   - `extends_name` / `extends_args` will be deleted in Phase 6; mark
     as deprecated in comments now but don't remove yet.

4. **New struct VtableSlot**:
   ```
   struct VtableSlot {
       method_name: Sym?
       family_param: Sym?      // which family member this slot belongs to
       is_getter: bool         // true for field getter/setter slots
       is_setter: bool
   }
   ```

5. **New struct InterfaceWhereClause** (for Phase 4):
   ```
   class InterfaceWhereClause {
       interface_name: Sym?
       type_args: [Sym]
       span: Span
   }
   ```

Update `ast.ly.lyric` with new types and invariants.

### 0.5 LIR skeleton types

**lir.ly** — add these:

1. **New LTypeKind variant**: `TyInterfaceRef` — the fat pointer type.
   Add to LTypeKind enum (line ~7). Fields on LType for this variant:
   - Reuse `name: string` for the interface name
   - Add `member_name: string` for the family member
   - Add `brand: string` for branded types (empty = anonymous)

2. **LInterfaceDecl** extension:
   - Add `family_params: [string]` — which type params are family
     (receiver-position) vs value (Phase 4).
   - Add `vtable_slots: [LVtableSlot]` — ordered list of slots.

3. **New struct LVtableSlot**:
   ```
   struct LVtableSlot {
       name: string
       family_param: string
       func_ptr_type: LType?
       is_getter: bool
       is_setter: bool
   }
   ```

4. **New LExprKind variants**:
   - `ExBoxInterface` — boxing coercion: `(ly_iface){obj, &vtable}`
   - `ExUnboxInterface` — extract data pointer from fat pointer
   - `ExVtableCall` — indirect call through vtable slot

5. **New LStmtKind variant**: `StTypeAssert` — for type switch on
   interface values via vtable identity compare.

### Exit criteria
Suite unchanged, self-test fixed point, notes committed.
Size: small (≤300 LOC). Risk: low.

---

## Phase 1 — Single-param interface types (unify `error`)

Goal: `Printable`-style one-param interfaces usable in type position;
`error` becomes an ordinary instance of the mechanism.

### 1.1 Parser changes (`src/parser/parser.ly`)

**`parse_type_expr`** (line ~1207) and **`parse_base_type`** (line ~1259):
Currently, a bare `Ident` in type position produces `TypeExprKind.Named`.
Add a branch: if the identifier is a known interface name followed by
`.Member`, parse `InterfaceType(iface, member, null)`. For single-param
interfaces, bare `InterfaceName` in type position is also valid — parse
as `InterfaceType(iface, null, null)`.

The tricky part: the parser doesn't know which names are interfaces
vs classes. Options:
- **Option A (recommended)**: Parse `Ident.Ident` as a new
  `QualifiedType` TypeExprKind; let the checker resolve whether it's
  a module reference, interface family member, or enum variant.
  This avoids needing forward knowledge in the parser.
- **Option B**: Keep all `Name.Member` as `Named` with dotted name;
  resolve in checker. Less clean but minimal parser change.

**Leaning**: Option A. Add `QualifiedType(base: Sym, member: Sym)` to
TypeExprKind. The checker resolves it in `resolve_type_expr`.

### 1.2 AST updates (`src/ast/ast.ly`)

- Add `QualifiedType(base: Sym, member: Sym)` variant to TypeExprKind
  enum (line ~28).
- This is the minimal parser-side change; semantic meaning assigned
  by the checker.

### 1.3 Checker changes (`src/checker/checker.ly`)

**`resolve_type_expr`** (line ~1121) and **`resolve_named_type`**
(line ~1185):
- Add a case for `TypeExprKind.QualifiedType`: look up `base` in the
  registry. If it's an interface with one type param, resolve
  `QualifiedType(Iface, T)` → `TypeKind.Interface(name: "Iface")`.
  If it's a module, dispatch to `resolve_module_func`. If it's an
  enum, treat as qualified variant.
- For bare `Named("Printable")` where the name is a single-param
  interface, resolve to `TypeKind.Interface("Printable")` directly.

**`is_assignable`** (line ~570):
- Currently handles `TyInterface` for `error` and `any` via
  structural signature checking. Generalize: for any interface typed
  value, perform structural satisfaction check.
- **Lazy checking at boxing sites** (design §3): instead of checking
  satisfaction on every assignment, check ONLY at:
  - Explicit `as Iface` casts
  - Function call argument passing to interface-typed params
  - Variable initialization of interface-typed vars
  This is a semantic change from the current eager approach. The
  `check_call` (line ~3471) and `check_assign` (line ~2775) functions
  are the boxing sites.

**New: `check_structural_satisfaction`**:
- Walk the interface's abstract methods (from `InterfaceDecl` in
  `iface_decls`). For each, verify the concrete class has a matching
  method (name, parameter types, return type).
- Produce ONE diagnostic listing ALL unsatisfied members on failure.
- Reuse existing machinery from `validate_impl_satisfies_abstract`
  (line ~5432) but generalize it from impl-centric to structural.

**`implements` assertion**: `check_implements` (line ~2088) currently
does nothing meaningful. Wire it to `check_structural_satisfaction`
so `class Foo { implements Printable }` is checked eagerly at the
class declaration site.

### 1.4 Lowerer changes (`src/lowerer/lowerer.ly`)

**`lower_type`** (line ~187) and **`lower_named_type`** (line ~270):
- Add handling for `TypeKind.Interface` → produce `LTyInterfaceRef`
  with the interface name and family member.
- Currently `error` is special-cased as `LTyError` / `LTyErrorResult`.
  The new path: `error` is just `LTyInterfaceRef("error", "T", "")`.

**`lower_file`** (line ~448) — boxing coercion:
- At call sites where a concrete type flows into an interface-typed
  parameter, emit `ExBoxInterface` (wraps data pointer + vtable
  reference).
- At sites where an interface-typed value is returned or stored,
  no coercion needed (it's already a fat pointer).

**Vtable construction** (`lower_interface_decl`, line ~670):
- Extend to produce vtable slot layout from the interface's method
  list. Each method → one slot. Field getters/setters from desugar
  pass 1 → additional slots.
- Per (class, interface) pair where the class structurally satisfies,
  emit a static vtable constant with function pointers to the class's
  concrete methods.

**`lower_impl_block`** (line ~701):
- Keep the existing forwarding wrapper generation for alias bindings.
- Additionally, wire the wrapper into the vtable slot for its method.

### 1.5 C backend changes (`src/c_backend/c_backend.ly`)

**`c_type`** (line ~377):
- Add case for `TyInterfaceRef` → emit `ly_iface` (the fat pointer
  typedef from Phase 0).

**Vtable emission** (new section in `emit_c`, line ~5227):
- For each interface: emit a `typedef struct { <func_ptr_per_slot> }
  <iface>_vtable_t;`.
- For each (class, interface) satisfaction: emit a `static const
  <iface>_vtable_t <class>_<iface>_vtable = { <func_ptrs> };`.
- The existing `impl_map` dict already tracks which classes implement
  which interfaces — use it as the data source.

**Boxing emission**:
- `ExBoxInterface` → `(ly_iface){ (void*)obj, (const void*)&vtable }`.
- `ExUnboxInterface` → `((<class>*)iface._data)`.

**Interface method calls** (`emit_method_call_expr`, line ~2205):
- When the receiver is `TyInterfaceRef`, emit indirect call through
  vtable: `((<iface>_vtable_t*)recv._vt)->method(recv._data, args)`.

**Type switch on interface** (`emit_type_switch_stmt`, line ~3396):
- Compare vtable pointer identity: `if (val._vt == &Class_Iface_vtable)`.

### 1.6 Error migration

The most sensitive part. `error` is used pervasively:
- `(T, error)` return tuples
- `?` try operator
- `is_error_type` checks in checker/lowerer/c_backend

**Strategy**: keep `(T, error)` working via a compatibility layer:
1. `error` becomes `interface error<T> { func T.message(self) -> string }`
   with T being the sole family member.
2. `LTyErrorResult` remains as-is in LIR for `(T, error)` tuples.
3. The `lower_type` for `error` produces `LTyInterfaceRef("error", "T", "")`
   in NEW code but `LTyError` when it appears in a tuple context.
4. `?` operator lowering in `lower_try` (line ~3509) continues to
   work because it extracts from `(T, error)` tuples which are still
   `LTyErrorResult`.

**Risk mitigation**: keep the old `LTyError`/`LTyErrorResult` path
alive and deletable in one commit. Bisection must be clean.

### 1.7 Tests

- `testdata/iface_single.ly`: boxing, calls through interface, type
  switch, heterogeneous `[Printable]` slice, error as interface.
- Probes: unsatisfied member diagnostic, `implements` assertion failure,
  ambiguous satisfaction.

### Exit criteria
Suite ≥ baseline (error tests still green via new path).
Size: medium (~800–1200 LOC). Risk: medium — the error migration is
the regression hazard.

---

## Phase 2 — Multi-param erased families + defaults-once

Goal: `Graph.G/.N/.E` types; default methods compiled once over fat
pointers. This dissolves old 4w1-a.

### 2.1 Parser changes (`src/parser/parser.ly`)

Minimal. `Iface.Member` already parses as `QualifiedType` from Phase 1.
Multi-param interfaces like `DirectedGraph<G, N, E>` declare three
family members; `DirectedGraph.G`, `DirectedGraph.N`, `DirectedGraph.E`
are all `QualifiedType("DirectedGraph", "G")` etc.

`gen T` already parses (language reference §4, §18). No parser changes
needed for gen-returning interface surfaces.

### 2.2 Checker changes (`src/checker/checker.ly`)

**Family classifier**:
- In `register_interface` (line ~1709): classify each type parameter
  as *family* (appears in receiver position of any method) or *value*
  (appears only in value positions). Store the classification on the
  `TypeInfo` for the interface.
- Value parameters → Phase 4. For now, reject interfaces where a
  non-receiver param appears in signatures with "value parameters not
  yet supported" — a hard diagnostic, not a silent skip.

**Signature chase** (design §3) — new function `check_structural_chase`:
- Input: anchor class (the one being boxed) and the interface.
- Algorithm:
  1. Match the anchor against the first family parameter's methods.
  2. For each method whose return type references another family param,
     extract the concrete type binding (e.g., `Net.nodes() -> gen Route`
     binds N = Route).
  3. Verify each bound type satisfies all methods declared for its
     family parameter.
  4. Loop-closure check: if `E.dst() -> N` and N is already bound to
     Route, verify `Via.dst() -> Route`.
  5. One diagnostic on failure showing the entire chase.

**Vtable layout** (on `InterfaceDecl` or `TypeInfo`):
- One vtable per (class-tuple, interface, anonymous-impl).
- Covers all family members' methods + field accessor slots.
- Slot order = declaration order.
- Reserve prefix space for Phase 4 (where refinement).

### 2.3 Desugar impact

**`desugar_specialize_default_impls`** (line ~762) — this is the
existing pass 4.5 that creates specialized copies of default methods
on concrete receiver classes. Under the new design, default methods
are compiled ONCE over fat pointers, so this pass will eventually be
**deleted** (it's the 4w1-a machinery the design explicitly kills).

**However**: do NOT delete it in Phase 2. It's still needed for
relation hint default methods (ArrayList.append etc.) which are
flattened, not erased. The deletion happens in Phase 5 when relations
become impl-based.

For now, add a flag to distinguish erased-interface default methods
(compiled once, no specialization) from flattened-interface default
methods (still specialized per impl). The discriminator is the
interface declaration: if it has `field` declarations, it's flattened;
otherwise erased.

**`desugar_default_impls`** (line ~897) — pass 5 extracts bodied
interface methods to top-level generic functions. For erased interfaces
(no `field`), this pass should produce ONE concrete function per
default method that takes `ly_iface` params and calls through vtable
slots internally. The function is NOT generic — it's compiled once.

### 2.4 Lowerer changes (`src/lowerer/lowerer.ly`)

**Default method lowering**:
- For an erased interface's default method, `lower_func` (line ~1009)
  produces a function whose parameters are `LTyInterfaceRef`.
- Inside the function body, `self.method()` calls become vtable
  indirect calls (`ExVtableCall`).
- Field access inside default bodies → vtable getter/setter slots
  (the Java default-method pattern). This is critical — defaults
  can reference `field` getters even on erased interfaces (the fields
  are exposed as getter/setter vtable slots, not as injected storage).

**Generator boxing**:
- When a `gen T` surface yields values that are interface-typed
  (e.g., `func G.nodes(self) -> gen N`), each yielded element must be
  boxed as `ly_iface`. The for-loop on the consumer side receives
  `ly_iface` values and can call interface methods on them.
- Existing generator machinery: `emit_for_stmt` (c_backend line ~3331),
  `emit_generator_func_decl` (line ~3712). The yield site needs boxing
  coercion.

### 2.5 C backend changes (`src/c_backend/c_backend.ly`)

**`ExVtableCall` emission**:
- New in `emit_expr_str` (line ~1869): emit
  `((<iface>_vtable_t*)recv._vt)->slot_name(recv._data, args)`.
- The receiver is `ly_iface`; arguments to the vtable function are
  the raw data pointer plus regular args.

**UFCS resolution** (design §8):
- Resolution order: class method → interface default → free function.
- `check_method_call` (checker line ~3870) already resolves methods.
  Add a tier for interface defaults and free functions over interface
  types. Same-tier ambiguity → compile error.
- Auto-boxing on receiver: when a class method call fails but the
  class structurally satisfies an interface whose default method
  matches, auto-box the receiver and route to the default.

### 2.6 Tests

- `testdata/iface_family.ly`: a small DirectedGraph over slice-backed
  classes, structural (Level 0), default BFS/count, free-function +
  UFCS call.
- Probes: chase-failure diagnostic (wrong return type), ambiguous UFCS.

### Exit criteria
Suite ≥ baseline; family interfaces usable end-to-end at Level 0.
Size: large (~1500–2500 LOC). Risk: HIGH — this is the heart.
Sub-risks: generator-of-boxed-values plumbing; devirtualization is
explicitly OUT of scope (correctness first; optimizer later).

---

## Phase 3 — The impl ladder: anonymous, named, brands, coherence

Goal: design §4 + §5 complete.

### 3.1 Parser changes (`src/parser/parser.ly`)

**`parse_impl`** (line ~674):
- Currently parses `impl Interface<Type, Type, ...> [owns|refs] [for
  ConcreteType] { ... }`.
- Add optional brand name: `impl name: Interface<...> { ... }`.
  After `impl`, if the next two tokens are `Ident :`, consume the
  brand name and store in `ImplBlock.name` (added in Phase 0).
- Alias binding RHS grammar: currently `parse_impl_mapping_short`
  (line ~755) and `parse_impl_mapping` (line ~817) parse
  `T.member = Concrete.accessor`. Extend the RHS to allow dotted
  forms: `Concrete.label.member` (labeled-scope members). This
  resolves through existing Phase 3e dotted-scope machinery at the
  checker level.

### 3.2 Checker changes (`src/checker/checker.ly`)

**Anonymous impl with alias bindings**:
- `register_impl_methods` (line ~1463, the Phase 1.5 entry) and
  `register_impl_methods` → `register_impl_methods` (line ~2101):
  currently registers interface methods on concrete classes.
- Extend: for each `ImplMapping` with `kind == Alias`, verify the
  RHS signature matches the interface slot (after type-var
  substitution). Near-miss → error naming both signatures. Exact
  match → populate the vtable slot with the RHS callable.
- Mixed-mode auto-derive: for members NOT covered by an alias, fall
  through to structural lookup (existing behavior).

**Named impls — brand types**:
- Add `TyBranded(brand: string, inner: Type)` variant to `TypeKind`
  enum (line ~19). This wraps an existing `TyInterface` with a brand
  name.
- `types_equal` (line ~397): two branded types are equal iff brand AND
  inner are equal.
- `is_assignable` (line ~570): `TyBranded(b, T)` is assignable to
  bare `TyInterface(T)` (brand widening — design §4.1), but NOT to
  `TyBranded(other_brand, T)` (cross-brand mixing → error).

**Boxing vs accepting** (design §4.2):
- At boxing sites (assignment to interface-typed var, arg passing):
  unqualified interface type → select the anonymous impl. If only
  named impls exist → error listing the named candidates.
- At accepting sites (parameter/field type declarations): `Iface.T`
  is existential — accepts any brand. This is the default behavior.

**Coherence checks** (design §5):
- **One anonymous impl per (interface, class-tuple)**: after all
  Phase 1.5 registration, scan for duplicates. Error at the second
  declaration site.
- **Orphan rule**: impl's package must own the interface OR at least
  one participating class. Check at `register_impl_methods` time.
- **Named impls invisible unless named**: falls out of brand scoping.
  Verify with a probe test — don't build extra machinery.

### 3.3 Lowerer changes

**Named impl vtables**:
- Each named impl produces its own vtable instance (distinct from
  the anonymous impl's vtable for the same class-tuple).
- Branded types lower to `LTyInterfaceRef` with a non-empty `brand`
  field. The c_backend emits a distinct vtable per brand.

### 3.4 C backend changes

**Brand vtable naming**:
- Anonymous: `<class>_<iface>_vtable`
- Named: `<brand>_<class>_<iface>_vtable`

**Cross-brand error emission**: when the checker rejects a cross-brand
assignment, the diagnostic mentions both brands and the interface.

### 3.5 Tests

- `testdata/iface_impls.ly`: renamed-member impl, two named impls
  over one class triple (mini FPGA a_side/b_side), brand mixing probe
  (error), duplicate-anonymous probe (error), orphan probe (error).

### Exit criteria
Suite ≥ baseline. Size: large (~1200–2000 LOC).
Risk: medium-high — brand types touch the checker's type-equality core.

---

## Phase 4 — `where` refinement + value parameters

Goal: design §6 + §2.1 complete; `extends` replaceable.

### 4.1 Parser changes (`src/parser/parser.ly`)

**`parse_interface`** (line ~540):
- Currently parses `extends` clause (line ~580-ish). Add `where`
  clause parsing: `where Interface<T1, T2, ...>, Constraint<W>`.
  Store as `InterfaceDecl.where_clauses` (added in Phase 0).
- `extends` continues to parse for backward compatibility; will be
  removed in Phase 6.

### 4.2 Checker changes (`src/checker/checker.ly`)

**Where clause semantics** (design §6):
1. **Satisfaction**: when chasing signatures for a refined interface,
   also chase the parent interface's surface. Modify
   `check_structural_chase` to be recursive through where clauses.
2. **Scope**: parent interface's abstract surface and default methods
   are callable on family members inside the refined interface's
   bodies and at call sites. Modify method resolution in
   `check_method_call` (line ~3870) to search parent surfaces.
3. **Vtable prefix**: parent's vtable is a prefix of the child's.
   When computing vtable layout, place parent's slots first.

**Vtable prefix implementation**:
- In vtable layout computation (added in Phase 2): for a refined
  interface with `where Parent<...>`, prepend Parent's slots.
- Override: if the child re-declares a parent method with the same
  signature, it replaces the slot IN the prefix.
- Upcast `WDG<f32>.G → DG.G`: same fat pointer, prefix view. The
  lowerer simply reinterprets the vtable pointer. No conversion code.

**Value parameters** (design §2.1):
- Parameters that appear only in value positions (never as receivers)
  are monomorphized. `WeightedDirectedGraph<G, N, E, W>`: W is a
  value parameter; G/N/E are family parameters.
- The interface family is instantiated per W-binding:
  `WDG<f32>.G`, `WDG<i32>.G` are distinct types.
- Default methods compile once PER VALUE-PARAM BINDING (not per
  class-tuple). Since value bindings are few, cost is nil.
- Method on a value parameter = error unless a constraint provides it.

**Transitive impl binding** (design §6.1):
- Three cases when impl'ing a refined interface:
  1. Parent not otherwise satisfied → this impl establishes it.
  2. Parent already has anonymous satisfaction → must agree; rebinding
     parent members → error.
  3. Named impl → propagates a named parent satisfaction under the
     same name; rebinding unrestricted.
- Modify `validate_impl_satisfies_abstract` (line ~5432) to handle
  the three cases.

**Numeric constraint**: `Numeric<W>` — fold the minimum needed here.
Literal arithmetic against concrete W does most of the work.

### 4.3 Desugar changes (`src/desugar/desugar.ly`)

**`desugar_interface_extends`** (line ~29):
- This pass materializes `extends` by deep-copying parent members
  into the child. For `where`-based refinement, this pass is NOT
  needed — `where` is a requirement, not a copy.
- However, keep this pass alive for backward compatibility until
  Phase 6 deletes `extends`.
- Add a new pass (or extend this one): for `where` clauses, record
  the parent interface's surface as "in scope" on the child interface
  WITHOUT copying. The checker will use this metadata.

### 4.4 Tests

- `testdata/iface_refine.ly`: WeightedDirectedGraph over the Phase 2
  graph; total_weight with W ∈ {i32, f64}; DG algorithm running on a
  WDG value through the prefix; override probe; rebind-contradiction
  probe.

### Exit criteria
Suite ≥ baseline. Size: large (~1200–2000 LOC). Risk: medium.

---

## Phase 5 — Relation unification (sequential after Phase 4)

Goal: design §7 complete; the textual injection layer dies.

**Risk management**: Dict (`HashedList`) is load-bearing for the
compiler itself — `src/resolver/`, `src/checker/`, and the stdlib
all use Dict internally. A broken Dict breaks the bootstrap with no
fallback. Phase 5 therefore uses a **vertical-slice strategy**: migrate
one hint type end-to-end through the new impl path before touching
the next, keeping the old path alive as the fallback for unmigrated
hints until all three are done.

### Existing code to be modified or deleted

**desugar.ly** — the core of the old relation machinery:
- `desugar_relations` (line ~262): the 3-phase (A/B/C) relation
  materializer. Phase A finds-or-creates impl blocks from relation
  decls. Phase B injects fields and FieldBind mappings. Phase C
  populates ClassDecl.css SubScope metadata.
  This entire function will be replaced with a desugar that converts
  `relation` declarations into `ImplDecl` AST nodes with brand names
  derived from labels.
- `desugar_destructors` (line ~568): deep-copies destructor bodies
  onto concrete classes. This logic moves into the flattened-impl
  path (which already has it for user-authored ownership impls).
- `desugar_specialize_default_impls` (line ~762): pass 4.5 creates
  specialized copies of default methods. For erased interfaces, this
  was neutered in Phase 2 (defaults compile once). For flattened
  interfaces (hints), this pass continues to be needed — the default
  methods (like `ArrayList.append`) are monomorphized per-impl, not
  compiled once over fat pointers.
- `desugar_default_impls` (line ~897): pass 5 extracts bodied methods
  to top-level generics. Unchanged for erased interfaces.
- Deep copy utilities (`deep_copy_*`, line ~1256+): retained.
- Rich substitution (`substitute_type_params_rich_in_*`, line ~1673+):
  retained.
- Method renaming (`rename_method_calls_in_*`, line ~1820+): may be
  simplified once label-prefixed names become brand-qualified.

**checker.ly** — validation passes:
- `validate_relation_hints` (line ~5322): checks hint-shape invariants
  (exactly 2 type params, all members annotated with a side). This
  validation moves into the new desugar path: bad hint fit → hard
  diagnostic at the `relation` line.
- `validate_impl_satisfies_abstract` (line ~5432): unchanged; it
  validates the new ImplDecls the same way.
- `register_impl_methods` (line ~1463 / ~2101): already handles impl
  blocks; the new relation-derived impl blocks flow through the same
  path.

**monomorphizer.ly** — generic specialization:
- Already handles generic classes and partial impls (4w1-d shipped).
  The new generic relation templates (`impl<K,V> HashedList<Dict<K,V>:d,
  DictEntry<K,V>:d>`) ride these exact rails.
- `rewrite_impl_renames` (line ~3772): the `@`-delimited impl method
  rename expansion. Will need to handle the new relation-derived impls.

**c_backend.ly** — vtable and dispatch:
- No major changes; the new relation-derived impls produce vtables
  the same way as user-authored impls.
- The existing `emit_slab_infrastructure` (line ~4446) and destructor
  emission paths continue to work — relation-derived impls still
  produce the same slab allocator and destructor code, just sourced
  from ImplDecl instead of RelationDecl.

### 5a — Dict vertical slice (HashedList)

1. **New desugar path**: convert
   `relation HashedList Dict<K,V>:d owns [DictEntry<K,V>:d]`
   into:
   ```
   impl<K,V> d: HashedList<Dict<K,V>:d, DictEntry<K,V>:d> owns
       where Hashable<K> { }
   ```
   The `d` is the brand (from the label). The `<K,V>` makes it a
   partial impl template (4w1-d machinery).

2. Route through existing `desugar_relations` Phase B for field
   injection — but sourced from the new ImplDecl, not from
   RelationDecl. The field injection code (building `__d_` prefixed
   fields on Dict and DictEntry) is reused.

3. **Keep old path alive** for ArrayList and DoublyLinked. The old
   `desugar_relations` function gets a predicate: if the relation's
   hint is `HashedList`, route to the new path; otherwise, old path.

4. **Bootstrap test after EVERY substep** — `make update && make self-test`.
   Dict is used during compilation.

### 5b — ArrayList migration

Same pattern as 5a but non-generic (simpler).

1. Desugar `relation ArrayList P:l owns [C:l]` → named ImplDecl.
2. Add `pub func P.iter(self) -> gen C` default method to ArrayList
   in stdlib, enabling §7.3 alias bindings.
3. Old path now only serves DoublyLinked.

### 5c — DoublyLinked migration

1. Same pattern. Handle `refs` vs `owns` destructor-pair difference.
2. Add `pub func P.iter(self) -> gen C` default to DoublyLinked.
3. Old RelationDecl path is now dead code. Delete it.

### 5d — Cleanup and deletion

**Code to delete** (substantial — expect negative LOC delta):

1. **`desugar_relations` old path** — the A/B/C phases that operated
   on RelationDecl. The new path operates on ImplDecl exclusively.

2. **TypeArgs threading hacks** — search for defensive patches that
   work around the old textual-injection layer's TypeArgs loss.
   Locations to check:
   - `monomorphizer.ly` around `collect_from_type` (line ~314) —
     class field type walking that special-cases relation-injected fields.
   - `lowerer.ly` around `lower_impl_block` (line ~701) — the
     `subst_impl_type` (line ~973) function that manually threads
     type args.
   - `c_backend.ly` vtable emission — any special-casing for
     relation-backed interfaces.

3. **Hint-fit diagnostics**: replace silent skips in
   `validate_relation_hints` (line ~5322) with hard errors at the
   `relation` line. Bad arity, cross-side references, missing abstract
   member on the concrete class → compile error.

4. **Collapse RelationDecl post-desugar**: after all three hints are
   migrated, `RelationDecl` AST nodes become dead after desugar.
   The checker and downstream passes should never see them.
   - `RelationDecl` class (ast.ly line ~275): keep in AST for
     parsing, but verify no downstream pass reads it.
   - `RelationSide` struct (ast.ly line ~269): same.
   - `RelationKind` enum (ast.ly line ~267): still used by
     `ImplBlock.kind` and `DestructorBlock.kind`; keep.

### Exit criteria
Suite ≥ baseline, Dict/relation tests green, RelationDecl gone after
desugar, old injection path fully deleted.
Size: large (~1000–1800 LOC net, likely NEGATIVE after deletions).
Risk: HIGH but mitigated by vertical slicing.

---

## Phase 6 — Acid tests, `extends` removal, docs

### 6.1 Rewrite test files

**`testdata/graph.ly`** — rewrite against the new design:
- `DirectedGraph<G, N, E>` with `gen`-returning surfaces instead of
  `-> [N]`.
- Structural satisfaction (Level 0) for slice-backed classes.
- Relation-backed classes satisfy via alias bindings (§7.3):
  `G.nodes = Net.routes.iter`.
- Default `count_edges` compiled once over fat pointers.
- Expect FEWER user-written lines (design falsifiable claim #1).

**`testdata/tree.ly`** — same treatment.

Both must PASS. Baseline becomes 96 PASS / 3 FAIL.

### 6.2 Remove `extends`

**parser.ly** — `parse_interface` (line ~540):
- Remove the `extends` parsing branch.
- Migrate existing users to `where`.

**desugar.ly** — `desugar_interface_extends` (line ~29):
- Delete entirely. Also delete `resolve_extends` (line ~51) and
  `deep_copy_func_decl` (line ~125) if no other callers remain.

**ast.ly** — `InterfaceDecl`:
- Remove `extends_name` and `extends_args` fields (line ~189).

**2-pass bootstrap**: if stdlib interfaces use `extends`, the old
binary can't parse the new source. Use the 2-pass bootstrap:
1. Build with old binary (which still understands `extends`).
2. `make update` to regen lyric.c with new binary.
3. `make self-test` to verify fixed point.

### 6.3 Migrate `-> [N]` surfaces

In interface declarations, change method return types from `-> [N]`
to `-> gen N` where the design requires generator-based iteration.
Existing stdlib hint interfaces (ArrayList, DoublyLinked, HashedList)
whose default methods return slices may keep `-> [T]` if that's what
they actually return — only capability-interface surfaces should use
generators.

### 6.4 Documentation updates

- `cr/docs/lyric-language-reference.md` §11–12: update interface and
  relation sections to match reality.
- `cr/docs/lyric-language-spec.md`: update interface/relation sections.
- All `.ly.lyric` companion files: update with new invariants.

### 6.5 Verify falsifiable claims

From the design doc's Overview:
1. ☐ `graph.ly` and `tree.ly` compile with fewer user-written lines.
2. ☐ The compiler lost more code than it gained (count LOC delta).
3. ☐ Three bug classes are unrepresentable (wrong-impl mixing,
   TypeArgs loss, divergent extends copies).
4. ☐ Third party can add `min_cut` via free function + UFCS.
5. ☐ Zero migration for existing relation code.

Record results in a progress note. If a claim failed, say so.

### Exit criteria
96 PASS / 3 FAIL / 99; self-test fixed point; both repos at same HEAD;
docs true.

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

---

## Appendix A — Key function cross-reference

Quick lookup: which existing functions in which files are affected by
each phase. Source line numbers from the `.ly.lyric` companion files
(may drift as code changes — grep the function name).

### AST (`src/ast/ast.ly`)
| Function/Type | Lines | Phases | Action |
|---|---|---|---|
| `TypeExprKind` enum | 28 | 0,1 | Add `QualifiedType`, `InterfaceType` variants |
| `InterfaceDecl` | 189 | 0,4,6 | Add `where_clauses`, `vtable_layout`; delete `extends_*` in Ph6 |
| `ImplBlock` | 226 | 0,3 | Add `name: Sym?` for brand |
| `RelationDecl` | 275 | 5 | Dead after desugar post-Phase 5 |
| `ImplMapping` | 216 | 3 | RHS grammar extension for labeled-scope |

### Parser (`src/parser/parser.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `parse_type_expr` | 1207 | 1 | Handle `Ident.Ident` as QualifiedType |
| `parse_base_type` | 1259 | 1 | Same |
| `parse_interface` | 540 | 4,6 | Add `where` clause; delete `extends` in Ph6 |
| `parse_impl` | 674 | 3 | Add optional brand name `impl name: Iface<...>` |
| `parse_impl_mapping` | 817 | 3 | Extend RHS for dotted-scope members |

### Checker (`src/checker/checker.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `resolve_type_expr` | 1121 | 1 | Handle QualifiedType → interface/module/enum |
| `resolve_named_type` | 1185 | 1 | Bare interface name → TyInterface |
| `is_assignable` | 570 | 1,3 | Structural satisfaction; brand widening; cross-brand error |
| `register_interface` | 1709 | 2 | Family/value param classification |
| `register_impl_methods` | 1463 | 3,5 | Coherence; orphan rule; brand registration |
| `check_method_call` | 3870 | 2 | UFCS resolution tiers |
| `check_field_access` | 4184 | 2 | Interface member access through vtable |
| `validate_relation_hints` | 5322 | 5 | Move to desugar; hard errors |
| `validate_impl_satisfies_abstract` | 5432 | 4 | Transitive binding 3-case rule |
| `check_implements` | 2088 | 1 | Wire to structural satisfaction |
| `TypeKind` enum | 19 | 3 | Add `TyBranded` variant |

### Desugar (`src/desugar/desugar.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `desugar_interface_extends` | 29 | 6 | DELETE (replaced by `where`) |
| `resolve_extends` | 51 | 6 | DELETE |
| `deep_copy_func_decl` | 125 | 6 | DELETE if no other callers |
| `desugar_interface_fields` | 179 | 1 | Unchanged (getter/setter synthesis) |
| `desugar_relations` | 262 | 5 | REPLACE with relation→ImplDecl desugar |
| `desugar_destructors` | 568 | 5 | Retain for flattened impls |
| `desugar_specialize_default_impls` | 762 | 2,5 | Skip for erased interfaces; retain for flattened |
| `desugar_default_impls` | 897 | 2 | Produce once-compiled functions for erased ifaces |

### Lowerer (`src/lowerer/lowerer.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `lower_type` | 187 | 1 | Handle TyInterface → LTyInterfaceRef |
| `lower_named_type` | 270 | 1 | Same |
| `lower_interface_decl` | 670 | 1,2 | Vtable layout construction |
| `lower_impl_block` | 701 | 1,3 | Vtable slot population |
| `lower_func` | 1009 | 2 | Interface-param functions |
| `lower_method_call` | 2666 | 2 | Vtable indirect calls |
| `subst_impl_type` | 973 | 5 | May simplify post-relation-unification |

### C Backend (`src/c_backend/c_backend.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `c_type` | 377 | 1 | Add TyInterfaceRef → `ly_iface` |
| `emit_c` | 5227 | 1,2 | Vtable struct + instance emission |
| `emit_method_call_expr` | 2205 | 2 | Vtable indirect calls |
| `emit_call_expr` | 2129 | 1 | Boxing coercion at call sites |
| `emit_type_switch_stmt` | 3396 | 1 | Vtable identity comparison |
| `emit_for_stmt` | 3331 | 2 | Generator-of-boxed-values |

### LIR (`src/lir/lir.ly`)
| Type | Lines | Phases | Action |
|---|---|---|---|
| `LTypeKind` enum | 7 | 0 | Add `TyInterfaceRef` |
| `LExprKind` enum | 105 | 0 | Add `ExBoxInterface`, `ExUnboxInterface`, `ExVtableCall` |
| `LInterfaceDecl` | 665 | 0,2 | Add family_params, vtable_slots |
| `LProgram` | 698 | 0 | No structural change |

### Monomorphizer (`src/monomorphizer/monomorphizer.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `monomorphize` | 3406 | 4,5 | Value-param instantiation; relation template specialization |
| `rewrite_impl_renames` | 3772 | 5 | Handle new relation-derived impls |
| `specialize_func` | 584 | 4 | Value-param default-method copies |
| `specialize_class` | 800 | 5 | Generic relation class specialization |

### Memory (`src/memory/memory.ly`)
| Function | Lines | Phases | Action |
|---|---|---|---|
| `slab_rewrite` | 633 | 5 | Unchanged — relation-derived impls produce same slab code |
| `is_rc_class_type` | 1728 | 5 | Unchanged — name-based lookup still works |

### Runtime (`runtime/lyric_runtime.h`)
| Item | Phases | Action |
|---|---|---|
| `ly_iface` typedef | 0 | ADD fat pointer struct |
| Slab infrastructure | — | Unchanged |
| RC macros | — | Unchanged |


---

## Appendix B — Worked examples: end-to-end data flow

These traces show exactly what each compiler pass produces for
interface-typed code. Read them before starting Phase 1 — they are
the single best way to build intuition for how the pieces fit.

### B.1 Single-param interface: boxing + call (Phase 1)

**Source:**
```lyric
interface Printable<T> {
    pub func T.to_string(self) -> string
}

class Cat {
    name: string
    pub func to_string(self) -> string { return self.name }
}

func show(p: Printable.T) {
    println(p.to_string())
}

func main() {
    let c = Cat { name: "Mittens" }
    show(c)                         // auto-boxing site
}
```

**Pass 1 — Parser** (`parse_interface`, `parse_func`, `parse_type_expr`):

```
InterfaceDecl {
    name: `Printable`
    itp: [TypeParam { name: `T` }]
    ifm: [FuncDecl { name: `to_string`, receiver_type: `T`,
                     return_type: Named("string"), body: null }]
}

FuncDecl {
    name: `show`
    params: [Param { name: `p`,
                     type_expr: QualifiedType(base: `Printable`, member: `T`) }]
}
```

The type `Printable.T` parses as `QualifiedType("Printable", "T")` —
the parser doesn't know if `Printable` is an interface, module, or
enum. The checker resolves that.

**Pass 2 — Desugar** (`desugar_all`):

`desugar_interface_fields` (pass 1): Printable has no `field` decls →
no getter/setter synthesis. (If it had `field T.label: string`, this
pass would add `T.label() -> string` and `T.set_label(string)`
FuncDecls with `is_synthesized = true`.)

`desugar_default_impls` (pass 5): `to_string` has no body (abstract)
→ nothing extracted. (If it had a default body, for an erased
interface the body would become a single top-level function taking
`ly_iface` params — see B.2.)

No other desugar passes affect this example. Cat is a plain class
with no relations.

**Pass 3 — Checker** (`check_file`):

Phase 0 (`preregister_type_names`): registers `Printable` and `Cat`
as stub TypeInfo entries.

Phase 1 (`register_lyric_block`):
- `register_interface`: Printable → TypeInfo with one method
  `to_string(self) -> string`, one type param `T`. Classified as
  **family** (T is in receiver position).
- `register_class`: Cat → TypeInfo with field `name: string`, method
  `to_string(self) -> string`.

Phase 1.5 (`register_interface_methods`): no impl blocks for
Printable → nothing registered on Cat. (If there were an
`impl Printable<Cat> {}`, this would register Printable's methods
on Cat's TypeInfo.)

Phase 2 (`check_lyric_block_bodies`):

`check_func_body` for `show`:
- `resolve_type_expr` on `QualifiedType("Printable", "T")`:
  looks up "Printable" in registry → it's an interface with one type
  param. Resolves to `Type { kind: Interface("Printable") }`.
  The `.T` is the sole family member, so bare `Printable` and
  `Printable.T` are equivalent.
- Parameter `p` gets type `TyInterface("Printable")` in scope.
- `check_method_call` for `p.to_string()`: receiver type is
  TyInterface("Printable"). Look up `to_string` in Printable's
  methods → found, returns `string`. Annotate expr.resolved_type.

`check_func_body` for `main`:
- `check_call` for `show(c)`: arg type is `TyClass("Cat")`, param
  type is `TyInterface("Printable")`.
- `is_assignable(TyClass("Cat"), TyInterface("Printable"))`:
  **structural satisfaction check** — does Cat have all of
  Printable's abstract methods? `to_string(self) -> string` ✓.
  Returns true.
- This is the **boxing site**. The checker records that Cat satisfies
  Printable (for vtable emission later).

**Pass 4 — Lowerer** (`lower_file`):

`register_block`:
- Registers Printable as `LInterfaceDecl` with one method slot:
  `to_string(self) -> string`.
- Registers the structural satisfaction Cat→Printable.

`lower_func` for `show`:
- Parameter `p` has type `LTyInterfaceRef("Printable", "T", "")`.
- `p.to_string()` lowers to:
  ```
  %0 = ExVtableCall { iface: "Printable", slot: "to_string",
                       receiver: p, args: [] }
  // → the data pointer p._data is passed as self to the vtable fn
  ```

`lower_func` for `main`:
- `show(c)` — arg `c` has type `LTyClassHandle("Cat")`, param
  expects `LTyInterfaceRef`. Emit boxing coercion:
  ```
  %0 = ExClassAlloc { class: "Cat", fields: [{name: "name", value: "Mittens"}] }
  %1 = ExBoxInterface { value: %0, iface: "Printable",
                         vtable: "Cat_Printable_vtable" }
  ExCall { func: "show", args: [%1] }
  ```

`lower_interface_decl` for Printable:
- Produces vtable layout: `[VtableSlot { name: "to_string",
  family_param: "T", func_ptr: fn(void*) -> string }]`.
- For Cat→Printable satisfaction, produces a static vtable instance:
  `Cat_Printable_vtable = { .to_string = Cat_to_string }`.

**Pass 5 — Monomorphizer**: nothing generic → pass-through.

**Pass 6 — Memory**: `Cat` gets slab allocation; `ly_iface` is a
value type (two pointers on stack), no RC.

**Pass 7 — C Backend** (`emit_c`):

Vtable type:
```c
typedef struct {
    LyricString (*to_string)(void* self);
} Printable_vtable_t;
```

Vtable instance:
```c
static const Printable_vtable_t Cat_Printable_vtable = {
    .to_string = Cat_to_string
};
```

Boxing:
```c
ly_iface _t1 = (ly_iface){ (void*)_t0, (const void*)&Cat_Printable_vtable };
show(_t1);
```

`show` function:
```c
void show(ly_iface p) {
    LyricString _t0 = ((Printable_vtable_t*)p._vt)->to_string(p._data);
    println(_t0);
}
```

Type switch (if needed):
```c
if (p._vt == (const void*)&Cat_Printable_vtable) {
    Cat* concrete = (Cat*)p._data;
    // ... use concrete Cat
}
```

---

### B.2 Multi-param family: default method compiled once (Phase 2)

**Source:**
```lyric
interface DirectedGraph<G, N, E> {
    func G.nodes(self) -> gen N
    func N.outgoing_edges(self) -> gen E
    func E.src(self) -> N
    func E.dst(self) -> N

    pub func G.count_edges(self) -> i32 {
        let mut total: i32 = 0
        for n in self.nodes() {
            for _e in n.outgoing_edges() { total = total + 1 }
        }
        return total
    }
}

class Net { /* has nodes() -> gen Route */ }
class Route { /* has outgoing_edges() -> gen Via, incoming_edges() -> gen Via */ }
class Via { /* has src() -> Route, dst() -> Route */ }

func main() {
    let net = Net { }
    // ... populate ...
    let count = net.count_edges()   // auto-box + UFCS to default method
}
```

**Parser**: same as B.1 — `DirectedGraph` parses as InterfaceDecl
with 3 type params (G, N, E), 4 abstract methods, 1 default method
(`count_edges` with a body).

**Desugar**:

`desugar_interface_fields`: no `field` decls → nothing.

`desugar_default_impls` (pass 5): `count_edges` has a body AND the
interface is erased (no `field` decls). Extract it as a **single
top-level function** (NOT per-impl specialized — that's the old 4w1-a
path being killed):

```
func DirectedGraph_count_edges(self: ly_iface) -> i32 {
    let mut total: i32 = 0
    for n in self.nodes() {        // vtable indirect call
        for _e in n.outgoing_edges() { total = total + 1 }
    }
    return total
}
```

Key: inside this function, `self` is `ly_iface` (a `DirectedGraph.G`
fat pointer). `self.nodes()` is a vtable call that returns a generator
of `DirectedGraph.N` fat pointers. Each yielded `n` is also `ly_iface`.
`n.outgoing_edges()` is another vtable call.

The function is compiled ONCE. It works for ANY class triple that
satisfies DirectedGraph — no monomorphization needed.

**Checker**:

Phase 1: `register_interface` for DirectedGraph. Classify type params:
- G: receiver of `nodes`, `count_edges` → **family**
- N: receiver of `outgoing_edges`, `incoming_edges`; return type of
  `src`, `dst` → **family**
- E: receiver of `src`, `dst`; return type of `outgoing_edges`,
  `incoming_edges` → **family**
- All three are family params. No value params. (W in
  WeightedDirectedGraph would be a value param — Phase 4.)

Phase 2 — **signature chase** for `net.count_edges()`:

The call `net.count_edges()` triggers UFCS resolution:
1. Class method on Net? No `count_edges` method → miss.
2. Interface default method? Check if Net satisfies any interface
   that has `count_edges`. Start the chase from DirectedGraph:

Chase from anchor G = Net:
```
G.nodes(self) -> gen N
  Net has nodes(self) -> gen Route  ✓  → bind N = Route

N.outgoing_edges(self) -> gen E
  Route has outgoing_edges(self) -> gen Via  ✓  → bind E = Via

N.incoming_edges(self) -> gen E
  Route has incoming_edges(self) -> gen Via  ✓  → E = Via (consistent)

E.src(self) -> N
  Via has src(self) -> Route  ✓  → N = Route (consistent)

E.dst(self) -> N
  Via has dst(self) -> Route  ✓  → N = Route (consistent)

Loop closed. Satisfaction verified: (Net, Route, Via) satisfies
DirectedGraph<G, N, E>.
```

If Via.dst() returned `Net` instead of `Route`, the diagnostic would
be: *"Net almost satisfies DirectedGraph: inferred N=Route, E=Via,
but Via.dst returns Net (expected Route)."*

**Lowerer**:

`net.count_edges()`:
1. Auto-box: `%0 = ExBoxInterface { value: net, iface: "DirectedGraph",
   vtable: "Net_DirectedGraph_vtable" }`
2. Call the once-compiled default:
   `%1 = ExCall { func: "DirectedGraph_count_edges", args: [%0] }`

Vtable for (Net, Route, Via) → DirectedGraph:
```
Net_DirectedGraph_vtable = {
    .nodes = Net_nodes,      // slot for G.nodes
}
Route_DirectedGraph_vtable = {
    .outgoing_edges = Route_outgoing_edges,   // slot for N.outgoing_edges
    .incoming_edges = Route_incoming_edges,
}
Via_DirectedGraph_vtable = {
    .src = Via_src,          // slot for E.src
    .dst = Via_dst,
}
```

Wait — one vtable per family member? Or one combined vtable?

**Design decision (important for the implementer)**: the vtable is
ONE struct per interface covering ALL family members' methods. The
fat pointer for `DirectedGraph.G` carries the FULL vtable (all slots
for G, N, and E). When `self.nodes()` yields a Route, the Route is
boxed with a fat pointer that carries the N-portion of the vtable.
How? The G-vtable includes function pointers for creating N and E
fat pointers from concrete values:

```c
typedef struct {
    // G methods
    Net_nodes_gen_t* (*nodes)(void* self);
    // N methods (needed when boxing yielded values)
    Via_gen_t* (*outgoing_edges)(void* self);
    Via_gen_t* (*incoming_edges)(void* self);
    // E methods
    void* (*src)(void* self);    // returns Route* (unboxed), re-boxed by caller
    void* (*dst)(void* self);
} DirectedGraph_vtable_t;
```

**Alternative (simpler, recommended for Phase 2)**: each family member
gets its own vtable struct. The G fat pointer carries the G vtable;
when `self.nodes()` yields a Route, the generator boxes it with the
N vtable. The vtables are separate but co-emitted for each satisfied
class-tuple. This is simpler because each fat pointer carries exactly
the methods callable on THAT family member:

```c
typedef struct {
    DirectedGraph_G_gen_t* (*nodes)(void* self);
    int32_t (*count_edges)(void* self);     // default method slot
} DirectedGraph_G_vtable_t;

typedef struct {
    DirectedGraph_N_gen_t* (*outgoing_edges)(void* self);
    DirectedGraph_N_gen_t* (*incoming_edges)(void* self);
} DirectedGraph_N_vtable_t;

typedef struct {
    void* (*src)(void* self);
    void* (*dst)(void* self);
} DirectedGraph_E_vtable_t;
```

**Leaning: per-family-member vtables.** This is simpler, matches Go's
"each interface type has its own vtable" model, and avoids threading
sibling vtables through yield sites. The G fat pointer doesn't need
to know about N's methods — it just needs to know how to box the
concrete Route into an N fat pointer when `nodes()` yields one.

**How boxing works inside the default method**: when `self.nodes()`
(a vtable call) yields a concrete `Route*`, the generator's yield
site wraps it:
```c
// Inside the nodes() generator's _next function:
*out = (ly_iface){ (void*)route, (const void*)&Route_DirectedGraph_N_vtable };
```
The generator knows the concrete types (it's a concrete function on
Net), so it knows which N vtable to use. The default method
`count_edges`, compiled once over `ly_iface`, just receives `ly_iface`
values and calls through their vtables.

**C Backend** — `count_edges` compiled once:

```c
int32_t DirectedGraph_count_edges(ly_iface self) {
    int32_t total = 0;
    // self.nodes() → vtable call, returns a generator of ly_iface
    DirectedGraph_G_vtable_t* vt = (DirectedGraph_G_vtable_t*)self._vt;
    DirectedGraph_G_nodes_gen_t* _gen = vt->nodes(self._data);
    ly_iface n;
    while (DirectedGraph_G_nodes_gen_next(_gen, &n)) {
        // n.outgoing_edges() → vtable call on the N fat pointer
        DirectedGraph_N_vtable_t* n_vt = (DirectedGraph_N_vtable_t*)n._vt;
        DirectedGraph_N_outgoing_edges_gen_t* _gen2 = n_vt->outgoing_edges(n._data);
        ly_iface _e;
        while (DirectedGraph_N_outgoing_edges_gen_next(_gen2, &_e)) {
            total = total + 1;
        }
    }
    return total;
}
```

This function works for ANY (G, N, E) triple — Net/Route/Via,
City/Road/Intersection, whatever. One compiled copy. The old 4w1-a
would have monomorphized a copy per triple.

---

### B.3 Key insight: where boxing happens

The boundary between "concrete code" and "interface code" is the
**boxing site** — where a concrete value becomes a fat pointer.

| Site | Who boxes | What's in the fat pointer |
|---|---|---|
| `show(cat)` — arg passing | Caller (main) | Cat*, &Cat_Printable_vtable |
| `net.count_edges()` — UFCS auto-box | Caller (main) | Net*, &Net_DG_G_vtable |
| `yield route` inside `nodes()` gen | Generator body (concrete Net_nodes) | Route*, &Route_DG_N_vtable |
| `return via.src()` inside interface body | Concrete method (Via_src) | Route* (unboxed — let the caller box if needed) |

**Rule**: concrete code always knows the concrete types, so it always
knows which vtable to attach. Interface code (default methods, free
functions over interface types) never needs to construct fat pointers
— it receives them and calls through them.

The one subtlety is generators: `nodes()` is declared on Net
(concrete), and its yield site boxes each Route with the N vtable.
The generator's `_next` function signature returns `ly_iface` to the
caller (the default method), but internally it constructs the fat
pointer from the concrete type + the known vtable.
