# Lyric Standard Library (stdlib)

## Executive Summary

The `stdlib` module provides the foundational data structures, utility functions, and interfaces that form the Lyric standard library. Unlike traditional libraries that are linked as separate binaries, the Lyric standard library is designed for selective merging. The compiler's `MergeStdlib` pass analyzes user code to identify which standard library components are actually used and injects only those declarations into the program's AST. This approach ensures that the final generated C code remains lean while providing a rich set of high-level abstractions, including relational data structures (ArrayList, DoublyLinked, HashedList), generic collections (Dict), and string manipulation utilities.

## File Inventory

*   [std.ly](std.ly): The core standard library file. It defines the primary relational interfaces (ArrayList, DoublyLinked, HashedList), the interned symbol system (Sym), the Hashable interface, the generic Dict collection, basic parsing utilities (parse_int, str_to_float), the error handling infrastructure, and the StringBuilder utility.
*   [string.ly](string.ly): A collection of string utility functions that operate on Lyric's byte-slice strings. It includes functions for searching, splitting, trimming, case conversion, replacement, and joining strings.
*   [stdlib.lyric](stdlib.lyric): A documentation and architectural metadata file written in Lyric. It describes the merging logic, lists the primary identifiers, and captures critical invariants for the standard library's interaction with the compiler.

## Architecture and Data Flow

The `stdlib` module is not a standalone executable but a source-level library. Its "data flow" is defined by the compiler's compilation pipeline. The process begins with source analysis, where the compiler reads the user's source code and identifies references to standard library types and functions. 

Following this, the `MergeStdlib` pass (located in the compiler's AST module) performs a transitive closure search. It starts with the explicitly used names and pulls in their definitions from `std.ly` and `string.ly`. If a pulled function itself depends on other standard library components, those are also pulled. The selected declarations are then injected into the first block (block 0) of the user's AST. This ensures they are available for type checking and subsequent lowering.

Finally, once merged, the standard library code is treated identically to user code. It is lowered to the Low-level Intermediate Representation (LIR), monomorphized if generic, and emitted as C code linked against the `lyric_runtime.h`.

## Interface Implementations

The `stdlib` module defines and implements several key interfaces that provide the backbone for Lyric's relational and collection systems:

*   **ArrayList<P, C>**: Implements an array-backed parent-child relation. It provides `array_append` and `array_remove` functions, along with `owns` and `refs` destructor pairs that are selected during desugaring.
*   **DoublyLinked<P, C>**: Implements an intrusive doubly-linked list relation. It provides `dll_append`, `dll_remove`, and a `children` generator for iteration.
*   **HashedList<P, C>**: Implements a hash table relation using open addressing and linear probing. It provides `hash_insert`, `hash_lookup`, and `hash_remove`.
*   **Hashable**: A fundamental interface for types that can be used as keys in a hash-based collection. It requires a `get_hash(self) -> u64` method. Standard types like `i32`, `u64`, and `Sym` implement this interface.
*   **error**: The standard interface for error handling, requiring a `message(self) -> string` method. The `Error` class provides a default implementation.

## Public API

The standard library exports a wide range of types and functions that are auto-imported into the global namespace of Lyric programs:

*   **Relational Interfaces**: `ArrayList`, `DoublyLinked`, and `HashedList`. These are used in `relation` declarations to manage ownership and lifetime.
*   **Collections**: `Dict<K, V>` (a generic hash map) and `SymTable` (an internal symbol intern table).
*   **Types**: `Sym` (interned symbols), `Error` (standard error), and `StringBuilder` (mutable string buffer).
*   **String Utilities**: A comprehensive suite of functions including `str_contains`, `str_split`, `str_trim`, `str_join`, `str_concat`, and `str_repeat`.
*   **Parsing and Conversion**: `parse_int` and `str_to_float`.
*   **Generators**: `range(start, end)` for integer iteration.

## Implementation Details

### Relational Destructors

A unique feature of the Lyric standard library is the use of `destructor owns` and `destructor refs` blocks within interfaces. When a user declares a relation like `relation ArrayList Parent owns [Child]`, the compiler's desugarer selects the `owns` destructor pair from the `ArrayList` interface and injects the logic into the `destroy` methods of the `Parent` and `Child` classes. This allows the standard library to define complex ownership behaviors, such as cascade deletion, in a generic and reusable way.

### HashedList and Dict

The `HashedList` interface implements a robust hash table with linear probing. It handles collisions and automatically rehashes the table when the load factor exceeds 75%. The `Dict<K, V>` class leverages `HashedList` to provide a high-level mapping API. It uses the `Hashable` interface to support any type as a key, provided it can produce a `u64` hash. The `Dict` implementation ensures that values are properly referenced when stored and unreferenced when removed or replaced.

### Sym and SymTable

The `Sym` class represents an interned symbol. It stores a string name and a pre-computed FNV-1a hash. Symbols are created via the `sym(name: string)` function, which uses a global `SymTable` (implemented via `HashedList`) to ensure that multiple calls with the same string return the exact same `Sym` instance. This allows for efficient $O(1)$ equality checks and hash table lookups using symbols as keys.

### StringBuilder

The `StringBuilder` class provides efficient string construction. It uses the `append` builtin, which the C backend implements with doubling growth and `memcpy`. This avoids the $O(n^2)$ performance and memory fragmentation issues associated with repeated string concatenation in many other languages.

### Trusted Functions

Many core standard library functions are marked as `trusted`. This keyword indicates that the function is allowed to perform low-level operations, such as explicit `ref` and `unref` calls, which are necessary for implementing manual reference counting within the relational data structures.

## Invariants

The standard library's interaction with the compiler is governed by several critical invariants that ensure correct merging and type resolution:

*   **Block 0 Merging**: The `MergeStdlib` pass merges declarations into block 0 of the user's file only. In multi-file compilation, each file is merged independently before blocks are combined, preventing duplicate definitions.
*   **Exhaustive Collection**: The functions responsible for collecting used names (`collectFuncCallNamesStmt` and `collectFuncCallNamesExpr`) must handle all statement and expression kinds. Missing a case can lead to standard library functions being silently omitted from the merged output.
*   **Primitive Type Filtering**: The `collectTypeNames` function must exclude primitive types (like `string`, `i32`, `bool`) to prevent false-positive dependencies that could transitively pull in the entire standard library.
*   **Generator Functions**: Functions like `range()` are implemented as standard generator functions in `std.ly`, not as compiler builtins. This ensures they are subject to the same merging and monomorphization rules as user-defined generators.

## Dependencies

The `stdlib` module has no external dependencies. It is a leaf in the Lyric ecosystem, providing the primitives that all other modules, including the compiler itself, depend on. It relies on the `lyric_runtime.h` for low-level operations like memory allocation and basic string/slice manipulation, which are exposed via compiler builtins.

## Technical Debt and Future Work

*   **Unicode Support**: Current string utilities operate on raw bytes. Future versions should include UTF-8 aware functions for character-based indexing and manipulation.
*   **More Collections**: The library currently lacks common structures like sets, deques, or priority queues.
*   **Standard I/O**: While `print` and `println` are builtins, a more comprehensive I/O library for file streams or network sockets is needed.
*   **Module System Integration**: As the Lyric module system evolves, the standard library should be organized into proper sub-modules (e.g., `std/collections`, `std/io`, `std/net`) rather than being a flat collection of files.
