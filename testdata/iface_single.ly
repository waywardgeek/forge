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

  func main() {
    let d = Dog { name: "Rex" }
    assert_eq(print_it(d), "Rex", "Dog dispatch")
    let c = Cat { lives: 9 }
    assert_eq(print_it(c), "meow x9", "Cat dispatch")

    // Variable initialization boxing
    let p: Printable = d
    assert_eq(p.to_string(), "Rex", "interface variable boxing")
  }
}
