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

func test_structural_satisfaction_and_defaults() {
    let al = build()
    // default method: receiver auto-boxes to DirectedGraph.G
    assert_eq(al.count_edges(), 2, "two flights")
    // explicit boxing site — anonymous impl, checked lazily here
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
    // resolution: class method (none) -> default (none) -> free function
    assert(al.has_edges(), "UFCS resolves to free function with auto-box")
    let empty = Airline { name: "empty", airports: [] }
    assert(!empty.has_edges(), "no nodes, no edges")
}
