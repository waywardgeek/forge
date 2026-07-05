# Interface Redesign v2 — Interfaces as Type Families

*Designed 2026-07-03 in a morning design session by Bill Cox and
CodeRhapsody (Claude Fable 5), and refined through design Q&A on
2026-07-05. This is the working design document for the interface
system of [Lyric](/docs/lyric-language), a self-hosting systems
language whose compiler was written entirely by AI under real-time
human supervision. It is published as-is — including open questions,
recorded leanings, and references to internal bug history — because
the working document IS the artifact; a cleaned-up version would
claim less than this one demonstrates. File paths and companion
documents referenced below live in the Lyric repository.*

*Supersedes the dispatch/impl-selection portions of the internal
`multi-class-interface-redesign.md`. Labels-as-scopes (Phase 3), UFCS
(§4), and the field/method unification from that doc survive unchanged;
its Wave 2 is deleted (see §12).*

Status: **DESIGN APPROVED — implementation in progress (July 2026).**

---

## Overview: why this design, and how we know it's good

### The problem

Lyric needs one abstraction mechanism that serves three masters at
once:

1. **Go-style ergonomics** — pass a value to a function through an
   abstract interface, switch on the concrete type behind it, write
   the algorithm once. Lyric already half-has this (`error`, `any`).
2. **Multi-class contracts** — a graph is not one type; it's a
   *relationship among three* (graph, node, edge). Write max-flow,
   min-cut, BFS once, and run them over any structure that has nodes
   and edges — including structures whose adjacency lives in
   intrusive relation links, not slices.
3. **DataDraw-grade relations** — ownership-cascading, zero-overhead,
   field-injected data structures, including *multiple relations
   between the same two classes* and *generic* relations
   (`Dict<K,V>` owns `DictEntry<K,V>`).

No mainstream language serves all three. Go stops at one type per
interface. Rust's traits handle multi-parameter contracts but forbid
overlapping implementations — and multiple relations between the same
classes *are* overlapping implementations. Nobody does field
injection except Scala, and Scala does nothing else on this list.
Lyric's previous design served the three masters with three separate
mechanisms (structural `error`, monomorphized multi-class interfaces,
textual relation injection), and the seams between them are where the
bugs lived.

This design serves all three with **one mechanism**: an interface
declares a family of types; an implementation — anonymous, named, or
spelled `relation` — instantiates the family.

### What is borrowed, from where, and what we fixed in each

Every load-bearing piece of this design is a proven idea from a
production language. What's new is the composition — and in each case,
the composition removes a known pain point of the source language:

| Borrowed | From | The pain users have there | What we do about it |
|---|---|---|---|
| Fat pointers, structural satisfaction, lazy checking at the boxing site, type switches | **Go** | One interface constrains one type. You cannot say "these three types form a graph"; generic multi-type algorithms need awkward type-parameter threading, and `interface{}`-based graph libraries lose all type safety between node and edge | The family generalization: `Graph.G/.N/.E` are each a Go-style interface, generated from one declaration, with cross-references between them checked (an `E.dst` must return this family's `N`, not just "some node") |
| Anchor + associated types instead of multi-parameter constraints | **Rust** (associated types; the community's hard-won lesson that multi-param traits are usually wrong) | `dyn Trait` with associated types is painful (`dyn Graph<N=..., E=...>` must name them all); trait objects and generics feel like two languages | Associated types are erased *into the family*: `Graph.N` is a first-class type, no turbofish, no `where G: Graph<N=Route>` spelling. Dynamic is the default; monomorphization is the optimizer's job, not the user's syntax |
| Coherence discipline (orphan rule, no overlapping impls) | **Rust / Haskell** | Rust: you cannot implement a foreign trait for a foreign type, and you cannot have two impls at all — yet overlaying two graph structures on one node type is a real need (Haskell's overlapping-instances escape hatch is a well-known footgun) | **Named impls with branded types.** Overlap is legal but each extra impl is a namespace, invisible unless named. Alice declaring a second impl cannot change what Bob's code means (§5), and mixing values from two impls is a *compile error*, not a wrong answer (§4.1) |
| Modules-as-implementations | **ML / OCaml** (a functor instance exports types) | Module systems are famously heavyweight; functor plumbing is its own skill | Named impls only appear when there are ≥2 wirings; the common case is zero ceremony. The module machinery is pay-per-ambiguity |
| Default methods compiled once, field access via accessor slots | **Java 8+** (default methods call abstract getters) | Interfaces can't touch state, so defaults are second-class; and retrofitting defaults onto erased generics caused years of bridge-method bugs | Same discipline (defaults touch state only through vtable getters), but the split is *principled and syntactic*: `field` declarations flip the whole interface to the flattened strategy, so there is no half-erased middle ground to breed bridge bugs |
| Trait fields via compile-time flattening | **Scala** (mixin state) | Trait linearization order, initialization order traps, and the diamond | No linearization: state comes only from explicit `relation`/impl declarations, uniqueness is enforced per (interface, tuple), and two bundles of the same interface's state are distinct *brands*, not a merged diamond |
| Intrusive, ownership-cascading, code-generated relations | **DataDraw** (Bill's C code generator) | Untyped: generated accessors are C macros; algorithms over the relation graph must be hand-written per schema | Relation-backed structures satisfy ordinary capability interfaces like `DirectedGraph`, so the shared algorithm library runs on DataDraw-style intrusive structures (§7.3) |
| Typed `relation` declarations, UFCS, `!` unwrap / `isnull` | **Rune** (Bill's prior language, the direct ancestor) | Generic relations worked, but barely — tape and glue. Relation identity and type arguments lived *below* the type system (generated names, textual expansion), invisible to the checker. Rune's `Dict<K,V>` was built that way; Lyric's first-generation implementation faithfully inherited the disease (the 2026-06 `classRenames` last-writer-wins bug, the six-layer TypeArgs-propagation lineage) | Generic relations become typed generic impls from the parser onward (§7.4): type arguments ride the same monomorphization rails as every other generic, and impl identity lives in brands and vtables where the checker can see it. The bug class is unrepresentable in *both* descendants' terms |
| Existentials for "a value plus evidence" | **Haskell / System F** | Existential types are expert-only syntax | They appear here only as the *reading* of what a fat pointer already is; no user-facing syntax at all |

### The two decisions that make it hold together

Everything above composes because of two rules, and both are
decisions *about where knowledge lives*, not features:

1. **One syntactic property picks the compilation strategy.** An
   interface with only methods is erased (fat pointers, algorithms
   compiled once — the Go/Java lane). An interface that declares
   `field` is flattened (injected state, monomorphized accessors,
   direct field access — the Scala/DataDraw lane). The user never
   chooses a strategy; the declaration's shape *is* the choice. §7.1
   justifies the flattened lane: chosen for the current hints (speed,
   simpler machinery, debuggable state), and forced outright once an
   injected field's type is a value parameter — no erased
   representation can carry unboxed varying-size storage.

2. **Impl identity is carried by values and types, never by names
   below the type system.** The previous design tracked "which
   relation is this?" with textual label prefixes and a global alias
   dictionary — knowledge stored *below* the type system, invisible to
   the checker, re-derived (buggily) by later passes. Here the same
   knowledge lives in the vtable (runtime) and the brand (compile
   time), where the checker can see it and the optimizer can exploit
   it.

### Falsifiable claims

How we'll know this design is good — concrete, checkable
consequences rather than aspirations:

- `testdata/graph.ly` and `testdata/tree.ly` compile and run with
  **fewer user-written lines** than under the previous design (the
  adapter-method boilerplate disappears — §7.3).
- The compiler **loses** more code than it gains: per-impl
  default-method emission (4w1-a), the Wave 2 pipeline, `extends`
  deep-copy, and the `_method_aliases` machinery are all deleted
  (§10), while the main addition — vtable construction — was already
  prototyped in June 2026.
- Three historical bug classes become *unrepresentable*, not fixed:
  wrong-impl mixing (brands, §4.1), TypeArgs loss in relation
  injection (typed impls on monomorphization rails, §7.4), and
  divergent copies of inherited surfaces (`where` shares, never
  copies, §6).
- A third party can add `min_cut` to the graph library without
  touching the interface, without genericity, and callable as
  `net.min_cut(...)` (§8) — matching Go's extension ergonomics, which
  neither Rust traits nor Java interfaces achieve.
- Zero migration for existing relation code: the `relation` line,
  labels, and dotted scopes are unchanged (§12).

---

## 0. TL;DR

An interface declares a **family of Go-style interface types** — one per
class-typed parameter. `Graph<G, N, E>` yields `Graph.G`, `Graph.N`,
`Graph.E`, each a fat-pointer type (data pointer + vtable) usable in
type position exactly like a Go interface.

- **Satisfaction is structural** (signature-chasing from the anchor).
  Impl blocks exist only to *rename* or *disambiguate*.
- **Ceremony is proportional to ambiguity**: no impl for the common
  case; an anonymous impl for name mismatches; **named impls** with
  branded types for multiplicity.
- **Two compilation strategies, chosen by one syntactic property**:
  method-only interfaces are *erased* (fat pointers, default methods
  compiled once); state-injecting interfaces (`field` declarations —
  i.e. relation hints) are *flattened* (fields injected, methods
  monomorphized, direct access). Relations keep zero overhead.
- **Relations ARE named impls**: the relation's labels are the brand.
  Generic relations (`Dict<K,V>`) are partial-impl templates —
  the shipped 4w1-d machinery.
- **Refinement uses `where`, not `extends`**: requirement-not-copy,
  with vtable-prefix subsumption giving free upcasts.
- Coherence is solved by construction: named impls are invisible
  unless named; anonymous impls are unique per (interface,
  class-tuple) and subject to an orphan rule.

Everything above *deletes* machinery relative to the previous design:
Wave 2 relation equivalence, `extends` deep-copy, per-impl
default-method monomorphization (4w1-a), and the textual field
injection layer that produced the `void*`/TypeArgs bug lineage.

---

## 1. Motivation

The previous design (multi-class-interface-redesign.md) was
implemented from an under-specified model and accumulated predictable
cracks:

- 4w1-a (default-method monomorphization-and-emission) never landed;
  `graph.ly` still fails.
- Relation labels, impl aliases, and monomorphizer rewrites interact
  through several fragile seams (`_method_aliases` RC bug, suffix
  stripping, Phase 1.5b callable-vs-implemented pollution).
- The question "what does an interface *declare*?" had no single
  answer: `error` was a Go-style type, `Graph<G,N,E>` was a
  monomorphized constraint, relations were a third thing.

This redesign starts from that first question and derives everything
else from the answer.

---

## 2. Core model: an interface declares a family of types

```lyric
interface DirectedGraph<G, N, E> {
    // abstract surface
    func G.nodes(self) -> gen N
    func N.outgoing_edges(self) -> gen E
    func N.incoming_edges(self) -> gen E
    func E.src(self) -> N
    func E.dst(self) -> N

    // default method — compiled ONCE over fat pointers
    pub func G.count_edges(self) -> i32 {
        let mut total: i32 = 0
        for n in self.nodes() {
            for _e in n.outgoing_edges() { total = total + 1 }
        }
        return total
    }
}
```

This declares **three types**: `DirectedGraph.G`, `DirectedGraph.N`,
`DirectedGraph.E`. Each is a fat pointer `(data, vtable*)`. A
single-parameter interface (`error`, `Printable<T>`) is the
family-of-one case — `error` used bare in type position means its one
family member, preserving today's `(T, error)` unchanged. `any` is
`interface {}` — the empty surface. Type switches recover concrete
types from any boxed value.

**The existential reading**: a value of type `Graph.G` is "there exist
G, N, E satisfying Graph, and here is the G." Values you extract
(`g.nodes()` yields `Graph.N`) are opaque handles usable only through
the interface surface — which is exactly what graph algorithms need.

### 2.1 Family parameters vs value parameters

A parameter that appears in **receiver position** (`func G.nodes`) is
a **family parameter**: it gets an interface type and is erased to a
fat pointer. A parameter that appears only in value positions is a
**value parameter** and is monomorphized:

```lyric
interface WeightedDirectedGraph<G, N, E, W>
        where DirectedGraph<G, N, E>, Numeric<W> {
    func E.weight(self) -> W
    pub func G.total_weight(self) -> W { ... }
}
```

`W` may be any type — `u64`, `f64`, a struct. The interface family is
instantiated per W-binding and spelled with the value params only:
`WeightedDirectedGraph<f32>.G`. Default methods compile once **per
value-parameter binding** (W bindings are few; cost is nil).

Declaring a method on a value parameter (`func W.foo`) is an error
unless a constraint provides it.

---

## 3. Satisfaction: structural, via signature-chasing

No impl block is needed when names line up (Level 0 of the ladder,
§4). The checker verifies satisfaction by **chasing signatures from
the anchor**:

1. `Net.nodes(self) -> gen Route` ⇒ binds N = Route.
2. Route must have `outgoing_edges(self) -> gen E` ⇒ binds E = Via.
3. Via must have `src`/`dst` returning Route — closing the loop.

Failure produces ONE diagnostic showing the whole chase: *"Net almost
satisfies DirectedGraph: inferred N=Route, E=Via, but Via.dst returns
Net (expected Route)."*

- Satisfaction is checked **lazily at the boxing site** (Go model) —
  no global quadratic pass.
- `implements DirectedGraph` on a class remains available as an
  **assertion**: check now, at the class declaration, error early.
  This finally gives `implements` enforced meaning.
- Accidental structural satisfaction (the Go one-method-interface
  cost) is accepted; `Graph`-sized surfaces make coincidence
  vanishingly unlikely, and `error` is already structural today.

**Boundary**: structural satisfaction applies only to **method-only
interfaces**. An interface that declares `field T.name` (state
injection) can never be satisfied structurally — you cannot
accidentally grow storage. State requires a declaration (`relation`
or explicit impl). See §7.

---

## 4. The impl ladder

Ceremony appears exactly when ambiguity appears:

**Level 0 — nothing.** One wiring, matching names ⇒ structural.
`net.max_flow(a, b)` auto-boxes and works.

**Level 1 — anonymous impl.** Names don't match (relation accessors,
adapting foreign classes):

```lyric
impl DirectedGraph<Net, Route, Via> {
    N.outgoing_edges = Route.a_outgoing     // alias binding
}
```

Unbound members are auto-derived structurally (mixed mode). The alias
RHS may be any callable in the concrete class's scope, **including
labeled relation-scope members** (`Net.routes.iter`, `Via.src.parent`)
— see §7.3.

**Level 2 — named impls.** The same classes participate in the same
interface more than once (FPGA: two graph structures over
Net/Route/Via):

```lyric
impl a_side: DirectedGraph<Net, Route, Via> { ... }
impl b_side: DirectedGraph<Net, Route, Via> { ... }
```

A named impl is a **module**: it owns branded types `a_side.G`,
`a_side.N`, `a_side.E`.

### 4.1 Branding

`a_side.N` and `b_side.N` are **distinct static types with identical
runtime representation** (fat pointer). Passing a `b_side.N` to
`a_side`'s `max_flow` is a compile error — the
silently-traverse-the-wrong-edge-set bug class is unrepresentable.

**Brand widening**: `a_side.G` coerces to bare `Graph.G` (and, via
prefix, to any interface `Graph` refines — §6). Widening is always
safe: behavior travels with the vtable in the value; the brand only
restricts *mixing*.

### 4.2 Boxing vs accepting (keeps Rule 1 honest)

- At **boxing** sites (`net as Graph.G`, auto-box at a call), an
  unqualified interface type selects the **anonymous** impl. If only
  named impls exist for the classes, unqualified boxing is an error:
  *"Net implements Graph only under named impls a_side, b_side;
  qualify which."*
- At **accepting** sites (parameter/field types), `Graph.G` is
  existential — it accepts any brand. This is what lets branded values
  flow into the shared algorithm library.

---

## 5. Coherence: Alice cannot break Bob

**Rule 1 — named impls are invisible unless named.** Bare interface
types resolve only to the anonymous impl. Declaring
`impl a_side: ...` creates a new namespace; it never enters the
resolution scope of existing code. (Departure from Haskell's global
instance soup; ML-module flavor.)

**Rule 2 — uniqueness + orphan rule for anonymous impls.**

- At most **one** anonymous impl per (interface, class-tuple),
  program-wide. A second is a compile error at the *new* declaration
  site — never a silent rebinding.
- Any impl (anonymous or named) may only be declared in a package that
  owns the interface **or** at least one participating class.
  Strangers wrap (newtype) instead.

Residual breakage vector: the class owner renames a method that
structural satisfaction depended on — ordinary API breakage, caught at
compile time by the chase diagnostic; `implements` moves the failure
to the owner's build.

---

## 6. Refinement: `where` on interfaces (requirement, not copy)

```lyric
interface WeightedDirectedGraph<G, N, E, W>
        where DirectedGraph<G, N, E>, Numeric<W> { ... }
```

The where clause has three consequences — and copies **nothing**:

1. **Satisfaction**: the chase for WDG also chases DG's surface.
2. **Scope**: DG's abstract surface and default methods are callable
   on G/N/E inside WDG bodies and at WDG call sites.
3. **Representation**: `WDG<W>.G`'s vtable embeds `DG.G`'s vtable as a
   **prefix**. Upcast `WDG<f32>.G → DG.G` is free (same pointer,
   prefix view). Every DirectedGraph algorithm works on weighted
   graphs with zero glue.

**Override**: WDG may re-declare a DG method with the same signature;
it replaces the slot *in the prefix* — virtual-override semantics,
so even a `DG.G` view dispatches to the override.

**`extends` is deleted** as a primitive (its desugar-time deep copy —
and the bug class where a parent change skews already-copied children
— goes with it).

**Fields never flow through constraints**: a where clause on a
state-injecting interface only *requires* that some relation/impl
already established the state; injection happens solely at that
declaration.

### 6.1 One impl for a refined interface

An impl of WDG may bind the **full transitive surface** (DG's members
included). Three cases:

1. **DG not otherwise satisfied** ⇒ this impl *establishes* the
   anonymous DG satisfaction as a side effect. One declaration, both
   interfaces served.
2. **Anonymous DG satisfaction already exists** ⇒ the impl inherits it
   as its prefix and **may not rebind** DG members. Contradiction is a
   compile error: *"nodes is already bound by the DirectedGraph
   satisfaction for Net; to rewire it, use a named impl."*
3. **Different DG wiring wanted** ⇒ name the impl. A named WDG impl
   implicitly defines a named DG satisfaction **under the same name**;
   rebinding is unrestricted inside it (the brand fences it).

---

## 7. State-injecting interfaces and relations

### 7.1 The boundary

One syntactic property — does the interface declare `field T.name` —
selects everything:

| | Method-only (capability) | State-injecting (hint) |
|---|---|---|
| Examples | Graph, Printable, error | ArrayList, DoublyLinked, HashedList |
| Satisfaction | structural (or impl) | **declaration required** (`relation`/impl) |
| Compilation | **erased** — fat pointers, defaults compiled once | **flattened** — fields injected, methods monomorphized, direct access |
| Precedent | Go/Java/Rust default methods | Scala trait fields / mixin flattening |

Flattening is a **choice** for today's hints and **forced** only at a
boundary the design permits but no shipped hint yet crosses
(clarified with Bill, 2026-07-05):

- Every field the current hints inject is representation-uniform
  (class pointers, `i32`, `u64`, `[C]`), so their default methods
  *could* be compiled once over accessor vtable slots, with
  ref/unref as nullable slots. We flatten anyway because: (a) the
  speed is the product promise — relations are the compiler's own
  inner loop, and an erased `append` is ~7 uninlinable indirect
  calls in place of five direct stores; (b) at relation use sites
  the concrete types are always statically known, so recovering the
  speed would need a devirtualizer that re-does monomorphization in
  a harder place — flattening IS devirtualization done at the
  declaration, where it's trivial; (c) injected state stays visible
  as plain struct members (the debugging half of Java's
  default-method lesson).
- Erasure becomes *impossible* the moment an injected field's type
  is a value parameter (e.g. a hint storing an inline `K` copy):
  one compiled body cannot address storage whose size varies per
  instantiation without boxing it, and the trusted-RC machinery
  decides ref/unref no-ops per monomorphized copy. The boundary
  rule draws the line where it would eventually be forced.


A flattened relation can *additionally* stamp out a vtable on demand
if someone boxes a participant (the vtable's getters/setters read the
label-mangled fields directly). Static is the default; dynamic is
available.

### 7.2 Relations ARE named impls; labels are the brand

```lyric
relation DoublyLinked Net:routes owns [Route:net]
```

is sugar for a named impl whose brand is the label pair. Two DLL
relations on one class pair = two named impls = two disjoint field
bundles — the coherence rules of §5 and the label rules of Phase 3
turn out to be the **same rule**. Where-clauses over state-injecting
interfaces name the brand: `where DoublyLinked<P:routes, C:net>`.

The `owns`/`refs` modifier continues to select the destructor pair;
destructor generation is unchanged (flattened, per relation).

### 7.3 Relation-backed capability interfaces (kills Wave 2)

Design consequence discovered in the DoublyLinked walkthrough:
**abstract surfaces should demand iteration, not storage** —
`func G.nodes(self) -> gen N`, not `-> [N]`. Slice-backed and
link-chasing impls then satisfy the same surface with no adaptation
and no materializing allocations. (Generators of fat pointers box
each yielded element; homogeneous vtable.)

Hint interfaces provide iteration as a default method
(`pub func P.iter(self) -> gen C`), injected under the label scope.
The capability impl is then one alias line per accessor:

```lyric
impl DirectedGraph<Net, Route, Via> {
    G.nodes          = Net.routes.iter      // labeled-scope member as RHS
    N.outgoing_edges = Route.out_e.iter
    N.incoming_edges = Route.in_e.iter
    E.src            = Via.src.parent       // relation back-pointer auto-getter
    E.dst            = Via.dst.parent
}
```

No hand-written adapter methods. This subsumes the previous design's
Wave 2 (relation equivalence): no new syntax, no `Collection<P,C>`
vocabulary interface, no DesugarImplEquivalences pass. **Wave 2 is
deleted.** Auto-projection of label scopes remains rejected (§3.4 of
the previous doc): if the relation label happens to match the
interface member name, you still write the one-line binding.

### 7.4 Generic relations (the Dict case)

```lyric
relation HashedList Dict<K, V>:d owns [DictEntry<K, V>:d]
```

desugars to a **generic named-impl template**:

```lyric
impl<K, V> HashedList<Dict<K, V>:d, DictEntry<K, V>:d> owns
    where Hashable<K> { }
```

- This is exactly **4w1-d partial impls** (shipped). Generic relations
  stop being a special desugar path; type arguments ride the ordinary
  monomorphization rails. The textual-injection layer that produced
  the six-layer `void*`/TypeArgs bug lineage ceases to exist — the bug
  class becomes unrepresentable.
- Abstract requirements (`C.hash_key(self) -> u64`) are checked
  **generically at the relation declaration site**, under propagated
  constraints. Bad hint fit is a hard diagnostic on the `relation`
  line (replaces today's silent skip — panic-don't-fallback).
- Uniqueness/overlap (§5) is checked at the **template** level; a
  concrete impl overlapping a template is a compile error. No
  specialization (future extension if evidence demands).

---

## 8. Default methods vs free functions; UFCS

**Inside the interface** — default methods: for algorithms canonical
to the contract. Compiled once (per value-param binding) over fat
pointers; overridable per refinement (§6) — and per impl.

**Outside** — ordinary functions over interface types:

```lyric
pub func max_flow(g: Graph.G, source: Graph.N, sink: Graph.N) -> i32
```

No genericity, no extension blocks, compiled once. **UFCS** closes the
syntax gap: `net.max_flow(a, b)` resolves to the free function with
auto-boxing on the receiver.

**Resolution order**: concrete class method → interface default method
→ free function. Ambiguity within a tier is a compile error requiring
qualification. The honest criterion for defaults vs free functions:
only defaults can be overridden per-impl.

Field access inside default-method bodies lowers to vtable
getter/setter calls (the Java default-method pattern); devirtualizes
to a direct offset load when monomorphized.

---

## 9. ABI and codegen

- **Fat pointer**: `(void* data, const vtable*)`. SoA mode:
  `(u32 handle, const vtable*)`; vtable functions take handles.
- **Vtable**: static, one per (class-tuple, interface, impl) —
  covering all family members' methods plus field getters/setters
  needed by default bodies. Refinement lays the required interface's
  vtable as a **prefix** (§6).
- **Homogeneous boxed slices**: within one impl every node shares a
  vtable, so `[Graph.N]` may be represented as `(vtable*, [ptr])`
  rather than an array of fat pointers. Decide before ABI freeze
  (open question §13).
- **Devirtualization**: when the concrete type behind a fat pointer is
  statically known at a call site (most boxing sites), the optimizer
  may call the target directly and/or monomorphize a specialized copy
  of a default method / free function. Semantics identical; Go
  intuition ("dynamic by default, devirtualize when known") holds.
  **Mandate (Bill, 2026-07-05): this is a requirement, not a maybe.**
  Erasure is the semantic model, not an ABI. A default method body is
  structurally a generic function over the family params; specializing
  it reuses the ordinary generic-monomorphization machinery. When an
  interface has exactly one satisfying tuple in the whole program, the
  compiler MUST specialize everything and emit no vtable at all;
  in general the erased/vtable emission is the fallback for genuinely
  dynamic sites (heterogeneous collections, type switches over unknown
  values) and may never be emitted for many programs. Sequencing:
  correctness-first over fat pointers (the erased output is the
  differential-testing oracle), specialization as its own phase after.
  Binary-level polymorphism (.so/.dll vtable ABI export) is explicitly
  deferred until Lyric defines shared-library compilation; nothing in
  this design requires vtable emission for export.
- June 2026 vtable groundwork (boxed values, static per-(class,
  interface) vtables, `error` dispatch) is the starting point; the
  piece skipped then — generic interfaces — is handled by the
  family/value-parameter split, which makes interfaces non-generic
  from codegen's perspective.

---

## 10. What this deletes

| Deleted | Replaced by |
|---|---|
| 4w1-a per-impl default-method monomorphization-and-emission | defaults compiled once over fat pointers |
| Wave 2 (abstract relations, `G:l/N:l = P:l/C:l` syntax, `Collection<P,C>`, DesugarImplEquivalences) | `gen`-based surfaces + labeled-scope alias RHS (§7.3) |
| `extends` deep copy (deep_copy_func_decl et al.) | `where` requirement + vtable prefix (§6) |
| Textual relation field injection through 6 layers | relations as typed generic impls on monomorphization rails (§7.4) |
| `_method_aliases` global / suffix-stripping / Phase 1.5b pollution | vtable dispatch + brands |
| Silent skip of bad relation hints | hard diagnostic at the relation line |
| `implements` as unenforced decoration | `implements` as satisfaction assertion |

---

## 11. Worked examples (session-verified)

These are the four cases we used to verify the design. Each is
complete — interface, concrete classes, and use sites — and each
exercises a different span of the design: erased families and the impl
ladder (11.1), refinement and value parameters (11.2), state injection
and relation unification (11.3), and generic relations (11.4).

### 11.1 DirectedGraph — erased family, impl ladder, UFCS

**The interface.** Declares three types: `DirectedGraph.G`,
`DirectedGraph.N`, `DirectedGraph.E` — each a fat pointer. The surface
demands iteration (`gen`), never storage (§7.3), so slice-backed and
link-chasing implementations satisfy it identically.

```lyric
interface DirectedGraph<G, N, E> {
    // abstract surface
    func G.nodes(self) -> gen N
    func N.outgoing_edges(self) -> gen E
    func N.incoming_edges(self) -> gen E
    func E.src(self) -> N
    func E.dst(self) -> N

    // default methods — compiled ONCE, over fat pointers
    pub func G.count_edges(self) -> i32 {
        let mut total: i32 = 0
        for n in self.nodes() {
            for _e in n.outgoing_edges() { total = total + 1 }
        }
        return total
    }

    pub func N.out_degree(self) -> i32 {
        let mut d: i32 = 0
        for _e in self.outgoing_edges() { d = d + 1 }
        return d
    }
}
```

**Level 0 — structural satisfaction, no impl.** A slice-backed toy
whose member names match the surface exactly:

```lyric
class Airline {
    name: string
    airports: [Airport]
    pub func nodes(self) -> gen Airport {
        for a in self.airports { yield a }
    }
}

class Airport {
    code: string
    deps: [Flight]
    arrs: [Flight]
    pub func outgoing_edges(self) -> gen Flight {
        for f in self.deps { yield f }
    }
    pub func incoming_edges(self) -> gen Flight {
        for f in self.arrs { yield f }
    }
}

class Flight {
    dep: Airport
    arr: Airport
    pub func src(self) -> Airport { return self.dep }
    pub func dst(self) -> Airport { return self.arr }
}
```

The signature chase (§3), from the anchor: `Airline.nodes` returns
`gen Airport` ⇒ **N = Airport**; `Airport.outgoing_edges` returns
`gen Flight` ⇒ **E = Flight**; `Flight.src`/`dst` return `Airport` —
the loop closes. Checked lazily at the first boxing site. To check
eagerly instead, assert it: `class Airline implements DirectedGraph`.

**Use sites** — boxing, defaults, free functions, UFCS:

```lyric
// External algorithm: a plain function over interface types.
// Compiled once. No genericity, no impl block, third-party-writable.
pub func has_edges(g: DirectedGraph.G) -> bool {
    for n in g.nodes() {
        for _e in n.outgoing_edges() { return true }  // gen is lazy — O(1)
    }
    return false
}

pub func max_flow(g: DirectedGraph.G,
                  source: DirectedGraph.N,
                  sink: DirectedGraph.N) -> i32 {
    // Edmonds–Karp over the abstract surface — uses only nodes(),
    // outgoing_edges(), src(), dst(). Body elided.
}

let al = Airline { name: "Lyric Air", airports: [...] }

let g: DirectedGraph.G = al          // explicit boxing (anonymous impl)
println(al.count_edges())            // default method; receiver auto-boxed
println(al.has_edges())              // UFCS → free function, auto-boxed
let f = al.max_flow(jfk, sfo)        // UFCS; jfk/sfo box to DirectedGraph.N
```

Resolution order at `al.count_edges()`: concrete class method (none) →
interface default (hit). At `al.has_edges()`: class (none) → default
(none) → free function (hit).

**Level 2 — named impls and brands.** The FPGA case: two graph
structures over the same three classes (the routing fabric wired two
ways). Relation labels referenced here are declared in §11.3.

```lyric
impl a_side: DirectedGraph<Net, Route, Via> {
    G.nodes          = Net.routes.iter
    N.outgoing_edges = Route.a_out.iter
    N.incoming_edges = Route.a_in.iter
    E.src            = Via.a_src.parent
    E.dst            = Via.a_dst.parent
}

impl b_side: DirectedGraph<Net, Route, Via> {
    G.nodes          = Net.routes.iter
    N.outgoing_edges = Route.b_out.iter
    N.incoming_edges = Route.b_in.iter
    E.src            = Via.b_src.parent
    E.dst            = Via.b_dst.parent
}
```

`a_side.N` and `b_side.N` are distinct static types with identical
runtime representation. Mixing is a compile error; widening is free:

```lyric
let ga: a_side.G = net
let gb: b_side.G = net
let na: a_side.N = route

println(ga.count_edges())            // counts the a-side edge set
println(gb.count_edges())            // counts the b-side edge set

let f = gb.max_flow(na, nb)
// ✗ compile error: max_flow's source is DirectedGraph.N brand-bound by
//   receiver gb to b_side; na has brand a_side.
//   The silently-traverse-the-wrong-edge-set bug is unrepresentable.

func report(g: DirectedGraph.G) { println(g.count_edges()) }
report(ga)                           // ✓ accepting site is existential —
report(gb)                           // ✓ any brand flows in

let gx: DirectedGraph.G = net
// ✗ compile error: Net implements DirectedGraph only under named impls
//   a_side, b_side; qualify which (net as a_side.G).
```

### 11.2 WeightedDirectedGraph — `where` refinement, value param W

**The interface.** G, N, E are family parameters (receiver position ⇒
erased); **W appears only in value positions ⇒ monomorphized** per
binding (§2.1). The `where` clause *requires* DirectedGraph — copies
nothing (§6).

```lyric
interface WeightedDirectedGraph<G, N, E, W>
        where DirectedGraph<G, N, E>, Numeric<W> {
    func E.weight(self) -> W

    // Default method: DG's surface (self.nodes, n.outgoing_edges) is in
    // scope via the where clause. Compiled once per W-binding.
    pub func G.total_weight(self) -> W {
        let mut sum: W = W.zero()
        for n in self.nodes() {
            for e in n.outgoing_edges() { sum = sum.add(e.weight()) }
        }
        return sum
    }
}
```

**Structural satisfaction extends the chase.** Add one method to the
Level-0 classes of §11.1 and the whole refined surface is satisfied —
no impl:

```lyric
// Flight gains:  pub func weight(self) -> f32 { return self.miles }

let wg: WeightedDirectedGraph<f32>.G = al   // value params only in the spelling
println(al.total_weight())                  // f32; auto-boxed via UFCS
```

**Free upcast via vtable prefix.** `WDG<f32>.G`'s vtable embeds
`DG.G`'s vtable as a prefix — the upcast is the same pointer,
reinterpreted:

```lyric
let g: DirectedGraph.G = wg        // free — no wrapper, no re-boxing
report(g)                          // every DG algorithm works, zero glue

// Free function over the refined family — note the value-param spelling:
pub func max_weight(g: WeightedDirectedGraph<f32>.G) -> f32 {
    let mut best: f32 = 0.0
    for n in g.nodes() {
        for e in n.outgoing_edges() {
            if e.weight() > best { best = e.weight() }
        }
    }
    return best
}
```

**One impl serving both interfaces** (§6.1 case 1). For the
relation-backed FPGA classes, an impl of WDG may bind the full
transitive surface. If no DirectedGraph satisfaction exists yet for
(Net, Route, Via), this *establishes* the anonymous one as a side
effect:

```lyric
impl WeightedDirectedGraph<Net, Route, Via, f32> {
    G.nodes          = Net.routes.iter      // DG members — establishes
    N.outgoing_edges = Route.a_out.iter     // the anonymous DirectedGraph
    N.incoming_edges = Route.a_in.iter      // satisfaction as a side effect
    E.src            = Via.a_src.parent
    E.dst            = Via.a_dst.parent
    E.weight         = Via.delay            // field auto-getter — WDG's own member
}
```

If an anonymous DG satisfaction *already* existed, rebinding
`N.outgoing_edges` here would be a compile error (§6.1 case 2):
*"outgoing_edges is already bound by the DirectedGraph satisfaction for
Route; to rewire it, use a named impl."*

### 11.3 DoublyLinked — state injection, relations as named impls

**The hint interface.** One `field` declaration flips the whole
interface to the **flattened** strategy (§7.1): fields injected under
the label, methods monomorphized per relation, direct field access,
zero overhead. Structural satisfaction is impossible — state requires
a declaration.

```lyric
interface DoublyLinked<P, C> {
    field P.first:  C?
    field P.last:   C?
    field C.next:   C?
    field C.prev:   C?
    field C.parent: P?

    pub trusted func P.append(self, child: C) {
        ref child
        child.prev = self.last
        child.next = null
        if isnull(self.first) {
            self.first = child
        } else {
            self.last!.next = child
        }
        self.last = child
        child.parent = self
    }

    pub trusted func P.remove(self, child: C) {
        if isnull(child.prev) { self.first = child.next }
        else { child.prev!.next = child.next }
        if isnull(child.next) { self.last = child.prev }
        else { child.next!.prev = child.prev }
        child.next = null
        child.prev = null
        child.parent = null
        unref child
    }

    // Iteration as a default method — injected under the label scope.
    // This is what makes the capability bridge below one line per slot.
    pub func P.iter(self) -> gen C {
        let mut cur = self.first
        while !isnull(cur) {
            yield cur!
            cur = cur!.next
        }
    }

    destructor owns P {
        let mut cur = self.first
        while !isnull(cur) {
            let nxt = cur!.next
            cur!.destroy()          // cascade
            cur = nxt
        }
    }
    destructor owns C { self.parent!.remove(self) }
    destructor refs P {
        let mut cur = self.first
        while !isnull(cur) {
            let nxt = cur!.next
            cur!.next = null        // unlink; children survive
            cur!.prev = null
            cur!.parent = null
            cur = nxt
        }
        self.first = null
        self.last = null
    }
    destructor refs C { self.parent!.remove(self) }
}
```

**Relations ARE named impls; labels are the brand** (§7.2). The FPGA
schema — note two relations on the *same* class pair (Route, Via),
legal because each label pair is a distinct brand with a disjoint
field bundle:

```lyric
class Net   { name: string }
class Route { id: i32 }
class Via   { delay: f32 }

relation DoublyLinked Net:routes  owns [Route:net]
relation DoublyLinked Route:a_out refs [Via:a_src]   // same (P, C) pair —
relation DoublyLinked Route:a_in  refs [Via:a_dst]   // four times, four
relation DoublyLinked Route:b_out refs [Via:b_src]   // brands, four disjoint
relation DoublyLinked Route:b_in  refs [Via:b_dst]   // field bundles
```

Each `relation` line desugars to a named impl whose brand is the label
pair; e.g. the first is
`impl DoublyLinked<Net:routes, Route:net> owns { }`. The `owns`/`refs`
keyword selects the destructor pair. Injected storage is label-mangled
(`Net.__routes_first`, `Via.__a_src_next`, …); user access goes through
the dotted scope:

```lyric
let net = Net { name: "n1" }
let r = Route { id: 0 }
net.routes.append(r)                 // monomorphized, direct field access
let head = net.routes.first          // field read through the label scope
for v in r.a_out.iter() { ... }      // default method under the label
r.destroy()                          // owns cascade: Route's destructor
                                     // fires each refs-relation unlink
```

**The capability bridge — what killed Wave 2** (§7.3). Because the
DirectedGraph surface demands `gen` and DoublyLinked provides `iter` as
a default under each label, wiring intrusive links to the shared
algorithm library is one alias line per slot, with labeled-scope
members and relation back-pointers as legal RHS:

```lyric
impl DirectedGraph<Net, Route, Via> {
    G.nodes          = Net.routes.iter
    N.outgoing_edges = Route.a_out.iter
    N.incoming_edges = Route.a_in.iter
    E.src            = Via.a_src.parent    // back-pointer auto-getter
    E.dst            = Via.a_dst.parent
}

println(net.count_edges())     // default method, fat pointers, chasing
let f = net.max_flow(s, t)     // intrusive links — zero adapter methods,
                               // zero materialized slices
```

No hand-written adapter methods, no `Collection<P,C>` vocabulary
interface, no relation-equivalence syntax. Boxing a participant stamps
out a vtable on demand whose getters read the label-mangled fields
directly; unboxed use keeps DataDraw-grade zero overhead.

### 11.4 Dict<K, V> — generic relations as partial-impl templates

**The classes and the relation.** K and V are Dict's ordinary generic
parameters; the relation line references them:

```lyric
class Dict<K, V> {
    pub func set(self, key: K, value: V) {
        let existing = hash_lookup(self, key.get_hash())
        if !isnull(existing) { existing!.value = value; return }
        hash_insert(self, DictEntry<K, V> { key: key, value: value })
    }
    pub func get(self, key: K) -> DictEntry<K, V>? {
        return hash_lookup(self, key.get_hash())
    }
    pub func has(self, key: K) -> bool { return !isnull(self.get(key)) }
}

class DictEntry<K, V> {
    key:   K
    value: V
    pub func hash_key(self) -> u64 { return self.key.get_hash() }
}

relation HashedList Dict<K, V>:d owns [DictEntry<K, V>:d]
```

**The desugar** (§7.4) — a generic named-impl template, which is
exactly shipped 4w1-d machinery:

```lyric
impl<K, V> HashedList<Dict<K, V>:d, DictEntry<K, V>:d> owns
    where Hashable<K> { }
```

The hint's abstract requirement (`C.hash_key(self) -> u64`) is checked
**generically at the relation line**, under the propagated
`Hashable<K>` constraint: `DictEntry.hash_key` exists and `K.get_hash`
is licensed by the constraint. A bad fit is a hard diagnostic on the
`relation` line — panic-don't-fallback, replacing today's silent skip.

**Instantiation rides the ordinary monomorphization rails.** No
textual injection layer, no type arguments smuggled below the type
system:

```lyric
let counts = Dict<Sym, i32>()       // stamps impl<Sym, i32>: fields
counts.set(`x`, 42)                 //   __d_children: [DictEntry_Sym_i32], …

let weights = Dict<Sym, f64>()      // separate stamp: f64 values stored
weights.set(`route7`, 0.25)         //   UNBOXED in the entry — per-stamp
                                    //   class layout, no boxing (§7.1)

let index = Dict<Sym, Route>()      // class-typed V: the trusted-RC
index.set(`r0`, r)                  //   machinery emits real ref/unref here,
                                    //   and no-ops for the i32/f64 stamps —
                                    //   a per-monomorphized-copy decision
```

Why the historical bug class is unrepresentable now: `Dict<K, V>`'s
type arguments flow parser → checker → monomorphizer as ordinary
generic-impl arguments. There is no per-relation textual expansion to
lose them, so the six-layer `void*`/TypeArgs-propagation lineage (and
the `classRenames` last-writer-wins bug) has no home to live in. Impl
identity is the brand `:d`; a second Dict-shaped relation with a
different label would be a second template with disjoint fields, and a
concrete impl overlapping the template is a compile error at its
declaration site (§7.4).

### Acid test

For implementation: rewrite `testdata/graph.ly` and `testdata/tree.ly`
under this design; both must compile and run, with fewer user-written
lines than under the previous design (see Falsifiable claims).

---

## 12. Migration notes (sketch — not a plan yet)

- Surface syntax of `relation`, labels, dotted scopes, `owns`/`refs`
  is **unchanged**. Existing relation-using code should not change.
- `extends` in existing interfaces → `where`. (Grep says usage is
  small; mostly testdata.)
- `-> [N]` in capability-interface surfaces → `-> gen N`.
- `error` and `any` are unchanged; they were already the Go-style
  special cases and are now just instances of the general model.
- Implementation phasing deliberately deferred until the design is
  approved; candidate order: (a) family types + boxing + structural
  chase for single-param interfaces (unify `error`), (b) multi-param
  erased families + defaults-once, (c) named impls + brands,
  (d) `where` refinement + prefixes, (e) relation-as-impl unification.

---

## 13. Open questions

Decision (2026-07-03 review): these are best resolved **during
implementation**, when real code pressure reveals the answer. Each
carries a **leaning** — what the implementer should try first, and
why. Departing from a leaning is fine; document why in this section
when you do.

1. **Homogeneous-slice ABI** (§9): `(vtable*, [ptr])` vs
   `[fat pointer]` for boxed collections.
   **Leaning: don't build it yet.** The `gen`-based surfaces (§7.3)
   box one element at a time, so graph algorithms may never
   materialize a boxed slice at all. Start with plain `[fat pointer]`
   for the rare cases that need one; add the homogeneous form only if
   profiling shows it matters. Minimum viable.
2. **Alias-RHS grammar**: labeled-scope members and back-pointer
   auto-getters on the RHS (`Net.routes.iter`, `Via.src.parent`);
   signature adaptation rules.
   **Leaning: exact signature match only, no adaptation.** The RHS is
   a name, not an expression — `Concrete.member` or
   `Concrete.label.member`, resolved in the class's scope, signature
   must match the interface slot exactly (after type-var
   substitution). Any adaptation logic belongs in a user-written
   helper method, where it's visible and debuggable. Panic-don't-
   fallback applies: a near-miss signature is an error naming both
   signatures, never a silent coercion.
3. **UFCS tie-breaking**: cross-package free-function candidates;
   auto-boxing when multiple interfaces could box the receiver.
   **Leaning: be strict, loosen later.** Two same-tier candidates
   visible at a call site = compile error requiring qualification
   (package-qualified call). If multiple interfaces could box the
   receiver for the same free-function name, that's the same error.
   Strict is forward-compatible; a clever preference order shipped
   too early is a compatibility trap (C++'s overload-resolution
   lesson).
4. **SoA vtable signatures**: handle-taking vtables and
   `--detect-uaf` interaction.
   **Leaning: vtable functions take `(u32 handle)` exactly as
   ordinary SoA methods do**, so UAF detection works unchanged
   (checks live at slab access, below the vtable). Implement AoS
   first end-to-end; port to SoA as a separate step. Expect no design
   change, just plumbing.
5. **Receiver type-params on external methods** (carried over from
   2026-07-02): free type vars in
   `func FlexNet.all_nodes(self) -> [FlexRoute<W>]`.
   **Leaning: name-matching + two checker diagnostics** — (a) a free
   type var in the signature that is declared by neither the
   receiver class nor the method's own `<...>` list is an error;
   (b) a method-level type param that shadows a receiver-class param
   is an error. No new receiver syntax (`FlexNet<W>.method` stays
   unsupported) unless the diagnostics prove insufficient in
   practice. NOTE: not yet re-confirmed with Bill; the checker rules
   are cheap and reversible, the syntax addition is neither.
6. **Relation-label vs identifier collision policy** — **SETTLED
   (Bill, 2026-07-05): a two-tier namespace.**
   - **Tier 1 — user-written declarations** on a class (fields,
     methods, relation labels the user typed) share one flat
     namespace; a duplicate among these is a hard error at the later
     declaration site. (The checker's existing label-vs-field/method
     collision errors are correct and stay.)
   - **Tier 2 — interface/impl-supplied names** never enter the
     class's namespace at all. An alias binding **erases** the
     interface identifier from being copied to the destination
     class entirely: the vtable slot is filled from the RHS, and no
     member named after the interface slot is ever materialized on
     the class. Likewise, erased-interface defaults live only in the
     vtable. There is no second name in existence — so there is no
     collision to detect and no shadowing/resolution special case to
     carry. (§8's class-method → default → free-function order
     governs *call-site dispatch*, not namespace membership.)
   **Rationale (Bill)**: a library's default surface may grow to
   1,000+ names over time; adding a default method must never break
   existing user code. This is Go's embedding rule and C#'s
   extension-method rule.
   Under v2 this is nearly free: the interface surface never injects
   names into the class at all — `N.outgoing_edges` is a vtable
   slot. The graph.ly Part 3 "collision" (label `outgoing_edges` +
   interface slot `outgoing_edges`) dissolves: the label scope is the
   only occupant of that name on the class; the interface slot exists
   solely in the vtable and serves boxed `Graph.N` dispatch.
   Consequence: a user method whose name+signature matches an
   interface default fills the vtable slot in the structural chase —
   i.e. it overrides the default, and the user's code wins.
7. **Negative assertion** (`!implements`)?
   **Leaning: no.** Add only if accidental structural satisfaction
   produces a real bug in real code. Track occurrences; revisit with
   evidence.

---

## 14. Design principles this honors

- **Panic, don't fall back** — bad hint fit, ambiguous boxing,
  brand mixing, impl contradiction: all hard, well-placed errors.
- **Where does the knowledge naturally live?** — impl selection lives
  in the value (vtable) or the brand (type); never in textual name
  mangling below the type system.
- **Minimum viable** — every section above removed machinery;
  the only new runtime concept is the fat pointer, which June's
  vtable work already prototyped.
