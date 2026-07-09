# LIR Module Design

## Executive Summary

The `lir` (Low-level Intermediate Representation) module is the architectural bridge between the high-level, expressive Abstract Syntax Tree (AST) and the backend code generation in the Forge compiler. Its primary mission is to resolve all semantic complexity of the Forge language, transforming a rich, sugared AST into a simplified, flat representation that can be easily emitted as target code (currently C11).

The LIR is defined by two core design principles that balance ease of code generation with the preservation of high-level intent:
1.  **Structured Control Flow**: Unlike many intermediate representations that decompose logic into basic blocks and explicit jumps, LIR preserves structured control flow constructs such as `if`, `while`, `for`, and `switch`. This preservation is critical for generating idiomatic, readable, and maintainable C code that can be easily debugged and optimized by downstream C compilers.
2.  **Flat Expressions**: All nested expressions are systematically flattened into a sequence of Single Static Assignment (SSA)-like temporaries. Every sub-expression is assigned to a unique, named temporary variable, ensuring that backends never encounter nested logic or complex recursive expression trees.

The module implements a comprehensive multi-stage pipeline that includes AST lowering, structural optimization, monomorphization of generics, invariant validation, and C code emission. By the time the IR reaches the backend, all high-level "sugar"—such as the `try` (?) operator, pattern matching, generators, and relational ownership—has been resolved into primitive operations.

## File Inventory

- [lir.go](lir.go): Defines the core data structures for the Low-level Intermediate Representation, including the type system (`LType`), operands (`LValue`), expressions (`LExpr`), and structured statements (`LStmt`).
- [lower.go](lower.go): Implements the `Lowerer`, the engine responsible for converting a type-checked AST into an `LProgram`. It handles expression flattening, sugar resolution, and the transformation of high-level constructs into structured LIR.
- [monomorphize.go](monomorphize.go): Performs an LIR-to-LIR pass that specializes generic declarations into concrete versions based on their usage. This pass is essential for the C backend, which does not support native generics.
- [optimize.go](optimize.go): Provides post-lowering optimizations to simplify the LIR and fix semantic issues, such as side-effect temporary elimination, multi-return destructuring, and unused variable removal.
- [validate.go](validate.go): Contains invariant checkers that verify the integrity of the LIR after lowering and monomorphization, ensuring that no illegal types (like `LTyAny` or unresolved `LTyTypeVar`) remain.
- [c_backend.go](c_backend.go): The primary code generator that emits C11 source code from a monomorphized LIR program. It handles complex features like generators (via Duff's device), channels (via pthreads), and vtable-based interface dispatch.
- [lir.forge](lir.forge): A Forge specification file providing deep architectural insights, invariant definitions, and historical context for the module's design.
- [c_backend_test.go](c_backend_test.go): Comprehensive tests for the C backend, ensuring correct code emission and runtime behavior across various language features.
- [lower_test.go](lower_test.go): Tests for the lowering pass, verifying the correct transformation from AST constructs to LIR statements and expressions.
- [lower_extra_test.go](lower_extra_test.go): Additional tests covering complex lowering scenarios, including nested pattern matching and relational constraints.

## Architecture and Data Flow

The LIR module operates as a strictly ordered transformation pipeline that progressively simplifies the program representation.

1.  **Lowering**: The process begins with the `Lowerer`, which consumes a type-checked `ast.File` and a `checker.Registry`. Lowering is performed in three distinct phases to handle cross-block references and circular dependencies. Phase 0 pre-registers all class names to distinguish heap-allocated classes from value-type structs. Phase 1 registers all types (enums, structs, classes, interfaces, aliases) across all blocks, populating field and variant information. Phase 2 performs the actual lowering of declarations and function bodies. During this phase, nested expressions are flattened into `LStmtTempDef` statements, and high-level constructs like `try` (?), `match`, and generators are desugared into simpler LIR equivalents.
2.  **Optimization**: The `Optimize` pass runs on the resulting `LProgram`. It performs structural transformations that are easier to handle on flat LIR than during initial lowering. This includes fusing void-context calls into bare statements (`LStmtSideEffect`), destructuring multi-return values into individual variables (`LStmtMultiAssign`), and eliminating unused temporaries and variables. It also fixes nil-to-zero-value conversions for value types to ensure C compatibility.
3.  **Monomorphization**: Since the C backend does not support native generics, the `Monomorphize` pass identifies all unique instantiations of generic types and functions. It generates specialized, mangled versions (e.g., `Stack[i32]` becomes `Stack_i32`) and rewrites all call sites. This pass is iterative, as specializing one function may reveal new instantiations of other generic types or functions.
4.  **Validation**: Validation passes (`ValidatePostLower`, `ValidatePostMono`) act as a safety net. They ensure that no illegal types, such as `LTyAny` (which would emit as `void*`) or unresolved `LTyTypeVar` nodes, remain in the program before it reaches the backend.
5.  **C Emission**: The `EmitC` function performs a final walk of the monomorphized `LProgram` to generate C11 code. It handles the emission of composite types (slices, optionals, results, tuples), vtable setup for interfaces, and state-machine transformations for generators.

## Interface Implementations

The `lir` module acts as a consumer of the [pkg/ast](../ast/design.md) and [pkg/checker](../checker/design.md) modules. It does not implement external interfaces but rather defines the `LProgram` structure as the primary contract between the compiler's middle-end and backend.

The `Lowerer` relies heavily on the `checker.Registry` to resolve type information and read annotations from the AST. It implements the logic for bridging the high-level semantic model of Forge to the low-level execution model of C.

## Public API

The `lir` module exposes a set of core data structures and transformation functions that define the compilation pipeline.

### Core Data Structures
- `LProgram`: The root container for a lowered program, holding all declarations (structs, classes, enums, interfaces, functions, globals) and metadata for monomorphization.
- `LType`: A recursive structure representing the LIR type system. It includes primitive types, composite types (slices, maps, channels, optionals), and user-defined types. It also tracks `TypeArgs` for generic specialization.
- `LValue`: Represents an operand, such as a variable, an SSA temporary, a literal, or a reference to a collection index.
- `LExpr`: Represents a right-hand side expression. Expressions are always bound to a temporary via `LStmtTempDef` and reference only `LValue` operands.
- `LStmt`: Represents a structured statement. Statements form a tree that preserves the program's control flow.

### Primary Transformation Functions
- `NewLowerer() *Lowerer`: Initializes a new AST-to-LIR lowerer.
- `(l *Lowerer) Lower(file *ast.File) *LProgram`: The primary entry point for converting a type-checked AST into a lowered LIR program.
- `Optimize(prog *LProgram)`: Applies the suite of structural and cleanup optimizations to an `LProgram`.
- `Monomorphize(prog *LProgram)`: Specializes all generic declarations in the program, producing a concrete IR suitable for C emission.
- `ValidatePostLower(prog *LProgram) []ast.InvariantViolation`: Checks for illegal types (like `LTyAny`) immediately after lowering.
- `ValidatePostMono(prog *LProgram) []ast.InvariantViolation`: Verifies that no type variables or generic declarations remain after monomorphization.
- `EmitC(prog *LProgram) string`: Generates the final C11 source code from a monomorphized LIR program.

## Implementation Details

### Expression Flattening and SSA Temporaries

The `Lowerer` maintains a monotonic `nextTemp` counter that is reset for each function. When lowering an AST expression, the `Lowerer` recursively lowers all sub-expressions first. Each sub-expression is emitted as an `LStmtTempDef` which binds the result of an `LExpr` to a new temporary ID. The lowering function then returns an `LValue` of kind `LValTemp` referencing that ID. This recursive process ensures that every `LExpr` node in the final LIR only references `LValue` operands (temporaries, variables, or literals), never other `LExpr` nodes. This flattening significantly simplifies the backend by removing the need for complex expression tree traversal and ensuring that evaluation order is explicitly encoded in the statement sequence.

### Structured Control Flow

LIR preserves the high-level tree structure of control flow, which is essential for generating idiomatic C. A notable example is the `LStmtWhile` statement. Instead of a simple boolean condition, it contains a `CondBlock` (a slice of statements) and a `CondVar` (the boolean result). This allows the `Lowerer` to emit the logic for complex conditions—which might themselves require multiple statements to evaluate—directly inside the loop. The C backend then emits a `while(1)` loop where the `CondBlock` is executed at the top, followed by a conditional `break` if the `CondVar` is false. This approach avoids the code duplication often seen in basic-block-based IRs where the condition logic must be repeated before the loop and at the end of the loop body.

### Monomorphization and Specialization

Monomorphization is a multi-phase, iterative process that eliminates generics. It begins by collecting all concrete instantiations of generic functions and types by walking the entire program. It then enters a specialization loop where it creates concrete, mangled versions of these declarations (e.g., `Dict<i32>` becomes `Dict_i32`). Because specializing one function might reveal new instantiations (e.g., a specialized `Map` might call a specialized `Hash`), the process continues until no new instantiations are discovered. Finally, the pass rewrites all call sites and type references to point to the specialized versions and removes the original generic declarations. A critical "Phase 6" pass, `ResolveClassNames`, uses per-function rename maps to fix bare generic class names that might have been missed by the initial type substitution.

### Optimization Strategy

The `Optimize` function applies several targeted passes to refine the LIR. The "Side-effect temp elimination" pass identifies temporaries that are assigned the result of a void-context builtin (like `println`) but are never used; these are fused into bare `LStmtSideEffect` statements. "Multi-return destructuring" handles the mismatch between Forge's tuple-based multi-return and C's lack thereof by splitting single-temporary multi-return calls into `LStmtMultiAssign` statements. The optimizer also performs "Unused temp/var elimination" by performing a global scan of the function body to identify and remove SSA temporaries and variables that are never read, which is particularly effective at cleaning up the results of complex desugaring.

### C Backend Patterns

The C backend employs several sophisticated patterns to map Forge's high-level features to C11:
- **Generators**: These are transformed into state machines using a Tatham/Duff's device pattern. A state struct tracks the current execution point, and `yield` statements are converted into state updates followed by a return. The next call to the generator resumes execution at the appropriate label via a `switch` statement at the function entry.
- **Channels**: Forge channels are implemented as pthreads-based blocking queues. The backend emits per-type macros that define the necessary structures and functions for thread-safe sending, receiving, and closing, utilizing mutexes and condition variables for synchronization.
- **Spawn and Concurrency**: Goroutines (spawned blocks) are implemented by hoisting the block body into a static function. Variable capture is handled via "capture-by-reference": a context struct is created containing pointers to the captured variables in the parent scope. This ensures that the spawned thread and the parent thread share the same memory for captured variables, matching Go's concurrency semantics.
- **Interfaces and Vtables**: Interfaces are implemented using a boxed structure containing a `void*` data pointer and a pointer to a vtable. The backend statically initializes a vtable for every (class, interface) pair discovered in the program, enabling efficient dynamic dispatch.

## Dependencies

- [pkg/ast](../ast/design.md): Provides the Abstract Syntax Tree definitions and the initial program structure.
- [pkg/checker](../checker/design.md): Provides the type-checking registry and the resolved type information necessary for lowering.

## Critical Invariants

### Three-Phase Lowering
To handle cross-block references correctly (e.g., a class in one file referencing an enum in another), the `Lowerer` follows a strict three-phase process:
1.  **Pre-registration**: All class names across all blocks are registered. This allows the type resolution logic to distinguish between classes (heap-allocated) and structs (value-types) regardless of their definition order.
2.  **Type Registration**: All types (enums, structs, classes, interfaces, aliases) are registered for all blocks, populating field and variant information.
3.  **Lowering**: All blocks are lowered. Since all types are already registered, cross-references are safe.

### AST Pointer Stability
The `Lowerer` reads checker annotations directly from AST nodes. It is critical to avoid value-type copies of AST nodes during iteration, as the checker's annotations are bound to the original pointer addresses. The `Lowerer` uses index-based iteration (e.g., `&slice[i]`) rather than range-copy iteration to ensure it always operates on the original nodes.

### TypeArgs Propagation
The `LType` structure includes a `TypeArgs` field which must be meticulously preserved through the checker, lowerer, and monomorphizer. This field is essential for distinguishing between different instantiations of the same generic type (e.g., `Dict<i32>` vs `Dict<string>`) and ensuring correct name mangling during monomorphization.

## Technical Debt and Future Work

- **Memory Management**: The C backend currently lacks a garbage collector. Future plans include implementing a combination of Structure of Arrays (SoA), arenas, and deterministic destruction to provide safe and efficient memory management.
- **Advanced Optimizations**: While the current optimizer handles structural cleanup, future work includes adding constant folding, dead code elimination, and function inlining at the LIR level to further improve performance.
- **Source Maps**: Implementing source maps is a priority to allow developers to debug the original Forge source code while running the generated C binary.
- **Type Resolution**: Some type resolution logic currently resides in the C backend (e.g., `inferExprType`). This logic should ideally be moved entirely into the `checker` or `lowerer` to keep the backend as a pure syntax emitter.
