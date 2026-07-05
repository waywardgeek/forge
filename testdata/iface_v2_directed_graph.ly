// Interface Redesign v2 acid test — §11.1 DirectedGraph
// Exercises: erased type families (DirectedGraph.G/.N/.E), structural
// satisfaction via signature chasing (Level 0, no impl block), default
// methods compiled once over fat pointers, free functions over
// interface types + UFCS with auto-boxing.
// STATUS: expected FAIL until v2 Phases 1-2 land (family types, erased
// families, signature chase). See cr/docs/interface-redesign-v2.md §11.1.

interface DirectedGraph<G, N, E> {
    // abstract surface — demands iteration, never storage
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

// Level 0: member names match the surface exactly — no impl block.
// The chase: Airline.nodes => N = Airport; Airport.outgoing_edges
// => E = Flight; Flight.src/dst return Airport — the loop closes.

class Airline {
    name: string
    airports: [Airport]
    pub func nodes(self) -> gen Airport {
        let mut i: i32 = 0
        while i < len(self.airports) {
            yield self.airports[i]
            i = i + 1
        }
    }
}

class Airport {
    code: string
    deps: [Flight]
    arrs: [Flight]
    pub func outgoing_edges(self) -> gen Flight {
        let mut i: i32 = 0
        while i < len(self.deps) {
            yield self.deps[i]
            i = i + 1
        }
    }
    pub func incoming_edges(self) -> gen Flight {
        let mut i: i32 = 0
        while i < len(self.arrs) {
            yield self.arrs[i]
            i = i + 1
        }
    }
}

class Flight {
    dep: Airport
    arr: Airport
    pub func src(self) -> Airport { return self.dep }
    pub func dst(self) -> Airport { return self.arr }
}

// External algorithm: plain function over interface types. Compiled
// once, third-party-writable, callable via UFCS.
pub func has_edges(g: DirectedGraph.G) -> bool {
    for n in g.nodes() {
        for _e in n.outgoing_edges() { return true }   // gen is lazy — O(1)
    }
    return false
}

func build() -> Airline {
    let jfk = Airport { code: "JFK", deps: [], arrs: [] }
    let sfo = Airport { code: "SFO", deps: [], arrs: [] }
    let f1 = Flight { dep: jfk, arr: sfo }
    let f2 = Flight { dep: sfo, arr: jfk }
    jfk.deps.push(f1)
    sfo.arrs.push(f1)
    sfo.deps.push(f2)
    jfk.arrs.push(f2)
    return Airline { name: "Lyric Air", airports: [jfk, sfo] }
}

func test_vtable_generator_iteration() {
    let al = build()
    // Manually box into DirectedGraph.G to test vtable generator iteration
    let g: DirectedGraph.G = al
    // Call has_edges through the fat pointer — exercises vtable dispatch,
    // generator _next/_value wrapper functions, and nested interface iteration
    assert(has_edges(g), "vtable generator iteration works")

    let empty = Airline { name: "empty", airports: [] }
    let g2: DirectedGraph.G = empty
    assert(!has_edges(g2), "empty graph has no edges")
}

// NOTE: The following tests require default method dispatch (auto-boxing,
// vtable default method wiring) which is Phase 2 Sprint 2 work.

func test_structural_satisfaction_and_defaults() {
    let al = build()
    assert_eq(al.count_edges(), 2, "two flights")
    let g: DirectedGraph.G = al
    assert_eq(g.count_edges(), 2, "same answer through the fat pointer")
}

func test_default_method_on_n() {
    let al = build()
    for a in al.nodes() {
        assert_eq(a.out_degree(), 1, "each airport has one departure")
    }
}

func test_free_function_ufcs() {
    let al = build()
    assert(al.has_edges(), "UFCS resolves to free function with auto-box")
    let empty = Airline { name: "empty", airports: [] }
    assert(!empty.has_edges(), "no nodes, no edges")
}
