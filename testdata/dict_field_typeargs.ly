// Regression test: generic class type args on a class field must be preserved
// so method calls through the field substitute type vars correctly.
// Previously: checker: validateAllExprsResolved: TypeVar leak 'V'
// (resolve_named_type dropped explicit type args when the generic class's
// registry entry was still a Phase-0 stub during field registration).
class VarTable {
    vars: Dict<Sym, f64>
}

func main() {
    let t = VarTable { vars: Dict<Sym, f64>() }
    t.vars.set(`pi`, 3.14159)
    t.vars.set(`e`, 2.71828)
    let e = t.vars.get(`pi`)
    if !isnull(e) {
        println(f"pi = {e!.value}")
    }
}
