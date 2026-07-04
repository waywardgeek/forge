// Interface Redesign v2 acid test — §11.3 DoublyLinked
// Exercises: relations as named impls (labels are the brand), FOUR
// relations on the SAME class pair (Route, Via) as four disjoint field
// bundles, the labeled-scope alias RHS (Net.routes.iter,
// Via.a_src.parent) wiring intrusive links to the shared algorithm
// library — the capability bridge that deleted Wave 2 — plus named
// impls a_side/b_side with brand widening at existential accepting
// sites.
// Uses the stdlib DoublyLinked hint (the full interface, with iter as
// a default method, is listed in interface-redesign-v2.md §11.3).
// STATUS: expected FAIL until v2 Phases 2-3+5 land (erased families,
// brands, labeled-scope alias RHS, relation-as-impl unification).

class Net   { name: string }
class Route { id: i32 }
class Via   { delay: f32 }

relation DoublyLinked Net:routes  owns [Route:net]
relation DoublyLinked Route:a_out refs [Via:a_src]   // same (P, C) pair —
relation DoublyLinked Route:a_in  refs [Via:a_dst]   // four times, four
relation DoublyLinked Route:b_out refs [Via:b_src]   // brands, four disjoint
relation DoublyLinked Route:b_in  refs [Via:b_dst]   // field bundles

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

// Named impls: the same classes participate twice. Each impl is a
// module owning branded types a_side.G / b_side.G. One alias line per
// slot; labeled-scope members and back-pointer auto-getters as RHS —
// zero adapter methods, zero materialized slices.
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

// Accepting site is existential: any brand flows in.
func report(g: DirectedGraph.G) -> i32 {
    return g.count_edges()
}

func build() -> Net {
    let net = Net { name: "n1" }
    let r0 = Route { id: 0 }
    let r1 = Route { id: 1 }
    net.routes.append(r0)
    net.routes.append(r1)

    // a-side wiring: one edge r0 -> r1
    let va = Via { delay: 0.5 }
    r0.a_out.append(va)
    r1.a_in.append(va)

    // b-side wiring: two edges r0 -> r1 and r1 -> r0
    let vb1 = Via { delay: 1.0 }
    let vb2 = Via { delay: 2.0 }
    r0.b_out.append(vb1)
    r1.b_in.append(vb1)
    r1.b_out.append(vb2)
    r0.b_in.append(vb2)
    return net
}

func test_dotted_scope_access() {
    let net = build()
    let head = net.routes.first
    assert(!isnull(head), "list head reachable through label scope")
    assert_eq(head!.id, 0, "first appended route")
    let mut n: i32 = 0
    for _r in net.routes.iter() { n = n + 1 }
    assert_eq(n, 2, "iter default method under the label")
}

func test_brands_count_disjoint_edge_sets() {
    let net = build()
    let ga: a_side.G = net
    let gb: b_side.G = net
    assert_eq(ga.count_edges(), 1, "a_side edge set")
    assert_eq(gb.count_edges(), 2, "b_side edge set")
}

func test_existential_accepting_site() {
    let net = build()
    let ga: a_side.G = net
    let gb: b_side.G = net
    assert_eq(report(ga), 1, "a_side.G widens to DirectedGraph.G")
    assert_eq(report(gb), 2, "b_side.G widens to DirectedGraph.G")
}
