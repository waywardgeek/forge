// Interface Redesign v2 acid test — §11.2 WeightedDirectedGraph
// Exercises: `where` refinement (requirement-not-copy), family vs value
// parameters (W monomorphized, G/N/E erased), value-param spelling
// WDG<f32>.G, defaults using the parent surface, free vtable-prefix
// upcast WDG<f32>.G -> DirectedGraph.G, free function over a refined
// family.
// STATUS: expected FAIL until v2 Phase 4 lands (where-refinement,
// vtable prefixes, value params). See interface-redesign-v2.md §11.2.

interface DirectedGraph<G, N, E> {
    func G.nodes(self) -> gen N
    func N.outgoing_edges(self) -> gen E
    func N.incoming_edges(self) -> gen E
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

// W appears only in value positions => monomorphized per binding.
// The where clause REQUIRES DirectedGraph — it copies nothing; the
// WDG vtable embeds the DG vtable as a prefix.
interface WeightedDirectedGraph<G, N, E, W>
        where DirectedGraph<G, N, E>, Numeric<W> {
    func E.weight(self) -> W

    // DG's surface (self.nodes, n.outgoing_edges) is in scope via the
    // where clause. Compiled once per W-binding.
    pub func G.total_weight(self) -> W {
        let mut sum: W = W.zero()
        for n in self.nodes() {
            for e in n.outgoing_edges() { sum = sum.add(e.weight()) }
        }
        return sum
    }
}

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
    miles: f32
    pub func src(self) -> Airport { return self.dep }
    pub func dst(self) -> Airport { return self.arr }
    // one added method extends the structural chase to the whole
    // refined surface — no impl block
    pub func weight(self) -> f32 { return self.miles }
}

// Free function over the refined family — note the value-param spelling.
pub func max_weight(g: WeightedDirectedGraph<f32>.G) -> f32 {
    let mut best: f32 = 0.0
    for n in g.nodes() {
        for e in n.outgoing_edges() {
            if e.weight() > best { best = e.weight() }
        }
    }
    return best
}

func build() -> Airline {
    let jfk = Airport { code: "JFK", deps: [], arrs: [] }
    let sfo = Airport { code: "SFO", deps: [], arrs: [] }
    let f1 = Flight { dep: jfk, arr: sfo, miles: 2586.0 }
    let f2 = Flight { dep: sfo, arr: jfk, miles: 2586.0 }
    jfk.deps.push(f1)
    sfo.arrs.push(f1)
    sfo.deps.push(f2)
    jfk.arrs.push(f2)
    return Airline { name: "Lyric Air", airports: [jfk, sfo] }
}

func test_refined_default_method() {
    let al = build()
    // total_weight uses DG's surface via the where clause
    assert_eq(al.total_weight(), 5172.0, "sum of both flight weights")
}

func test_prefix_upcast_is_free() {
    let al = build()
    let wg: WeightedDirectedGraph<f32>.G = al
    // upcast: same pointer, prefix view of the vtable — zero glue
    let g: DirectedGraph.G = wg
    assert_eq(g.count_edges(), 2, "every DG algorithm works on weighted graphs")
}

func test_free_function_over_refined_family() {
    let al = build()
    assert_eq(al.max_weight(), 2586.0, "UFCS over WDG<f32>.G")
}
