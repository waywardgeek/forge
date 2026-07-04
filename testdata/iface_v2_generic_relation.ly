// Interface Redesign v2 acid test — §11.4 generic relations
// Exercises: a generic relation desugaring to a partial-impl template
// (impl<K, V> HashedList<Table<K,V>:d, TableEntry<K,V>:d> owns
//   where Hashable<K>),
// hash_key checked generically at the relation line, type arguments
// riding the ordinary monomorphization rails (no textual injection),
// unboxed value params per stamp (i32/f64), and per-stamp RC decisions
// (class-typed V gets real ref/unref; primitives get no-ops).
// Mirrors stdlib Dict<K,V> exactly (§11.4) under the name Table to
// avoid colliding with the stdlib class.
// STATUS: may already pass via 4w1-d machinery; under v2 Phase 5 it
// must KEEP passing with relations unified into named impls.

class Table<K, V> {
    pub func set(self, key: K, value: V) {
        let existing = hash_lookup(self, key.get_hash())
        if !isnull(existing) {
            existing!.value = value
            return
        }
        hash_insert(self, TableEntry<K, V> { key: key, value: value })
    }

    pub func get(self, key: K) -> TableEntry<K, V>? {
        return hash_lookup(self, key.get_hash())
    }

    pub func has(self, key: K) -> bool {
        return !isnull(self.get(key))
    }
}

class TableEntry<K, V> {
    key:   K
    value: V
    // the hint's abstract requirement, checked generically at the
    // relation line under the propagated Hashable<K> constraint
    pub func hash_key(self) -> u64 { return self.key.get_hash() }
}

relation HashedList Table<K, V>:d owns [TableEntry<K, V>:d]

class Widget { name: string }

func test_unboxed_value_params() {
    // stamp 1: i32 values stored unboxed in the entry
    let counts = Table<Sym, i32>()
    counts.set(`x`, 42)
    counts.set(`y`, 99)
    assert(counts.has(`x`), "key present")
    assert_eq(counts.get(`x`)!.value, 42, "i32 stored unboxed")
    counts.set(`x`, 43)
    assert_eq(counts.get(`x`)!.value, 43, "overwrite in place")

    // stamp 2: f64 values — a second, disjoint monomorphization
    let weights = Table<Sym, f64>()
    weights.set(`route7`, 0.25)
    assert_eq(weights.get(`route7`)!.value, 0.25, "f64 stored unboxed")
    assert(!weights.has(`route8`), "missing key")
}

func test_class_valued_stamp_rc() {
    // stamp 3: class-typed V — the trusted-RC machinery emits real
    // ref/unref for this stamp and no-ops for the primitive stamps
    let index = Table<Sym, Widget>()
    let w = Widget { name: "w0" }
    index.set(`w0`, w)
    assert_eq(index.get(`w0`)!.value.name, "w0", "class V survives insert")
}

func test_many_entries_rehash() {
    // push past the 75% load factor to force a rehash through the
    // template-stamped machinery
    let t = Table<Sym, i32>()
    let names = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
                 "k", "l", "m", "n", "o", "p", "q", "r", "s", "t"]
    for name, i in names {
        t.set(sym(name), i)
    }
    for name, i in names {
        assert_eq(t.get(sym(name))!.value, i, "all entries survive rehash")
    }
}
