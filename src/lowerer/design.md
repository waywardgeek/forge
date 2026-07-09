# Lowerer Module Design

## Executive Summary

The `lowerer` module serves as the critical architectural bridge between the high-level, semantically rich Abstract Syntax Tree (AST) and the Low-level Intermediate Representation (LIR). Its primary mission is to "flatten" the expressive, nested structures of the Lyric language into a linear sequence of operations that are easily translatable to C. This transformation process involves stripping away language sugar, resolving complex pattern matching into primitive control flow, and translating high-level type definitions into concrete LIR structures. The `lowerer` ensures that every expression is decomposed into a chain of temporary variables, satisfying the Single Static Assignment (SSA)-like requirements of the LIR while preserving the structured control flow necessary for idiomatic C code generation. By the time the `lowerer` finishes its work, the program has been transformed from a tree of nested expressions into a flat sequence of statements where every intermediate result is explicitly named.

## File Inventory

*   [lowerer.ly](lowerer.ly): The primary implementation file for the module. It contains the `Lowerer` class and the logic for the two-phase translation from AST to LIR, including type resolution, statement lowering, expression flattening, and the complex method-renaming logic required for Lyric's relational interface implementations.

## Architecture and Data Flow

The `lowerer` operates as a two-phase transformation engine, designed to handle the forward-referencing nature of Lyric declarations. In the first phase, known as **Registration**, the module performs a top-level walk of the AST to collect all type declarations—including structs, classes, enums, and interfaces—as well as function signatures. This phase populates internal dictionaries that serve as a comprehensive symbol table for the second phase, ensuring that type references and method calls can be resolved across the entire package regardless of their declaration order.

In the second phase, **Lowering**, the module recursively traverses the AST to emit LIR nodes. This phase is driven by the `lower_file` function, which orchestrates the translation of every declaration and implementation block. As the `lowerer` walks the tree, it maintains a "statement buffer" where it emits flattened LIR statements. When it encounters a nested expression, it recursively lowers it, emits a temporary definition (`StTempDef`) for the result, and returns a temporary value (`LValue`) to the caller. This recursive-descent approach naturally flattens complex expression trees into linear sequences.

Data flows into the `lowerer` from the [checker](../checker/design.md), which provides a fully annotated AST. The `lowerer` consumes these annotations—specifically `resolved_type` and `inferred_type_args`—to make informed decisions about type lowering and monomorphization. The output of the module is an `LProgram` object, which is then passed to the [monomorphizer](../monomorphizer/design.md) or directly to the [c_backend](../c_backend/design.md).

## Interface Implementations

The `lowerer` module does not implement a formal interface defined in another package. Instead, it acts as the primary implementation of the "Lowering" stage of the compiler pipeline. It consumes the `File` and `LyricBlock` structures defined in [src/ast](../ast/design.md) and produces the `LProgram` and `LStmt` structures defined in [src/lir](../lir/design.md). It serves as the definitive translator between the high-level semantic model and the low-level execution model.

## Public API

The public API of the `lowerer` module is centered around the `Lowerer` class and its orchestration functions.

*   **new_lowerer() -> Lowerer**: Constructs a new `Lowerer` instance with initialized symbol tables, temporary ID counters, and empty statement buffers.
*   **Lowerer.lower_file(file: File?) -> LProgram?**: The primary entry point for the module. It accepts a parsed and checked AST and returns a complete LIR program. This function internally manages the transition between the registration and lowering phases.
*   **Lowerer.lower_type(te: TypeExpr?) -> LType?**: A public utility for translating high-level AST type expressions into their LIR equivalents. This is used extensively during both phases to ensure type consistency.
*   **Lowerer.register_block(block: LyricBlock)**: Performs the first phase of lowering for a single block, populating the symbol tables with declarations.

The `Lowerer` class is marked as `permanent`, meaning it is managed by the compiler's global lifecycle and maintains its state throughout the lowering of a single package.

## Implementation Details

### Expression Flattening and Temporaries
The core of the lowering logic is the `emit_temp` method. Whenever an expression needs to be evaluated, the `lowerer` generates a new unique temporary ID, emits an `StTempDef` statement containing the expression's logic, and returns an `LValue` of kind `ValTemp`. This ensures that the LIR never contains nested expressions, which simplifies both optimization and C code generation. For example, a nested call like `f(g(x))` is lowered into a sequence where `temp0` stores the result of `g(x)` and `temp1` stores the result of `f(temp0)`.

### Interface and Impl Lowering
One of the most complex responsibilities of the `lowerer` is handling `impl` blocks. Lyric's relations system allows classes to implement interfaces through renaming and field binding. The `lower_impl_block` function handles this by generating wrapper functions that forward interface method calls to the appropriate class methods or fields. It populates an `impl_method_renames` dictionary, which the `lowerer` uses during method call resolution to rewrite high-level method names to their concrete, mangled implementation names. This mechanism supports alias-based mapping, inline function implementations, and direct field binding (getters and setters).

### Special LValue Kinds
While most expressions are flattened into `ValTemp`, the `lowerer` uses specialized `LValue` kinds to handle mutation and references. `ValIndexRef` is used for index expressions passed as mutable arguments, allowing the backend to emit direct pointer references (e.g., `&collection.data[index]`). Similarly, `ValClassFieldRef` is used when calling mutating methods on slice headers stored within class fields. This ensures that mutations like `push` or `pop` are applied to the actual field rather than a temporary copy of the slice header.

### Builtin and Method Specialization
The `lowerer` specializes many high-level method calls into LIR builtins. String, slice, and map methods (like `len`, `push`, `append`, `contains`) are translated into dedicated `ExBuiltin` expressions. A notable specialization occurs with the `append` function when used on a class field: the `lowerer` automatically emits the necessary `ExClassGet`, performs the append, and then emits a `StClassSet` to write the updated slice header back to the field, preventing silent data loss.

### Pattern Matching Resolution
The `lowerer` provides sophisticated support for Lyric's `match` statement. It analyzes the patterns and determines the most efficient lowering strategy. Enum matches are typically lowered to an `StSwitch` on the variant tag, while union or `any` matches are lowered to an `StTypeSwitch` that checks the runtime type of the value. For complex nested patterns, the `lowerer` generates nested switch statements, carefully extracting and binding values at each level. Simple literal or identity matches are lowered to efficient `StIf` chains.

### Concurrency and Memory Management
The `lowerer` translates Lyric's high-level concurrency primitives into LIR operations. `spawn` blocks are lowered to `StSpawn`, and `select` statements are decomposed into `LSelectCase` structures. Channel operations like `send` and `receive` are translated into dedicated LIR statements. Additionally, the `lowerer` handles explicit memory management hints by translating `ref` and `unref` expressions into `StRefIncr` and `StRefDecr` statements, which the backend uses for reference counting. It also manages the lowering of `lock` blocks into `StLock` statements, ensuring thread-safe access to shared resources.

### Variable and Assignment Lowering
Variable declarations are lowered to `StVarDecl`, with support for multi-variable destructuring. The `lowerer` propagates declared types to empty or untyped slice initializations to ensure type safety in the LIR. Assignments are handled by `lower_assign`, which distinguishes between simple identity assignments, field accesses (both for structs and classes), and index-based assignments. It specifically handles the `slice[i].field = val` pattern by emitting an `StIndexSet` with a field name, avoiding unnecessary copies.

## Dependencies

*   **[src/ast](../ast/design.md)**: The `lowerer` depends on the AST for its input data structures. It relies on the pointer stability of AST nodes to access checker annotations.
*   **[src/lir](../lir/design.md)**: The `lowerer` depends on the LIR module for its output data structures. It is the primary consumer of the `LStmt`, `LExpr`, and `LType` definitions.
*   **[src/checker](../checker/design.md)**: The `lowerer` depends on the semantic analysis performed by the checker. It specifically requires that all expressions have their `resolved_type` field populated.

## Technical Debt and Future Work

*   **Monomorphization Integration**: Currently, some monomorphization logic is interleaved with lowering. A cleaner separation between the initial lowering and the subsequent specialization pass would improve maintainability and allow for more advanced optimizations.
*   **Short-Circuiting Complexity**: The current implementation of short-circuiting `&&` and `||` involves manual variable allocation and assignment. This could be simplified if the LIR supported a native "short-circuit" expression kind.
*   **Duplicate Renames**: The `impl_method_renames` map can become quite large in programs with many relations. Optimizing the storage and lookup of these renames would improve compiler performance for large codebases.
*   **Capture Analysis**: The `captures` list in `LSpawnData` is currently empty. Implementing a proper capture analysis to identify which variables from the outer scope are used within a `spawn` block would enable more efficient closure handling.
