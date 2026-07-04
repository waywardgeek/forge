lyric iface_single_test {
  interface Printable<T> {
    pub func T.to_string(self) -> string
  }

  class Dog {
    name: string
  }

  impl Printable<Dog> {
    T.to_string = Dog.bark
  }

  func Dog.bark(self) -> string {
    return self.name
  }

  class Cat {
    lives: i32
  }

  impl Printable<Cat> {
    T.to_string = Cat.meow
  }

  func Cat.meow(self) -> string {
    return f"meow x{self.lives}"
  }

  func print_it(p: Printable) -> string {
    return p.to_string()
  }

  func identify(p: Printable) -> string {
    match p {
      Dog => { return "dog" }
      Cat => { return "cat" }
      _ => { return "unknown" }
    }
  }

  func main() {
    let d = Dog { name: "Rex" }
    assert_eq(print_it(d), "Rex", "Dog dispatch")
    let c = Cat { lives: 9 }
    assert_eq(print_it(c), "meow x9", "Cat dispatch")

    // Variable initialization boxing
    let p: Printable = d
    assert_eq(p.to_string(), "Rex", "interface variable boxing")

    // Return boxing
    assert_eq(make_printable().to_string(), "Rex", "return boxing")

    // Heterogeneous slices
    let animals: [Printable] = [d, c]
    assert_eq(len(animals), 2)
    assert_eq(animals[0].to_string(), "Rex", "slice element 0 dispatch")
    assert_eq(animals[1].to_string(), "meow x9", "slice element 1 dispatch")

    // Type switch on interface
    assert_eq(identify(d), "dog", "type switch Dog")
    assert_eq(identify(c), "cat", "type switch Cat")
  }

  func make_printable() -> Printable {
    let d = Dog { name: "Rex" }
    return d
  }
}
