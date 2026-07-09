# LIR Module Design

## Executive Summary

The `lir` module defines the Low-level Intermediate Representation (LIR) for the Lyric compiler. It serves as the critical bridge between the high-level, annotated Abstract Syntax Tree (AST) and the final C11 code generation. The LIR is designed to simplify the backend's task by flattening complex, nested expressions into a sequence of Single Static Assignment (SSA)-like temporary variables while maintaining the structured control flow (such as `if`, `while`, and `for` blocks) of the original source code. This hybrid approach ensures that the generated C code remains idiomatic and readable while eliminating the semantic complexity of the high-level language.

The LIR is not just a passive data structure; it also incorporates metadata and operations for memory management, including slab allocation and reference counting. It supports a wide range of Lyric features, from basic primitives and structs to complex types like channels, maps, and tagged unions.

## File Inventory

*   [lir.ly](lir.ly): The primary source file defining the LIR data structures, including types, values, expressions, statements, and top-level program declarations. It also includes utility functions for resolving class references within the LIR.

## Architecture and Data Flow

The LIR is the target of the [lowerer](../lowerer/design.md) module, which transforms the type-annotated [AST](../ast/design.md) into a flat, linear sequence of operations. Data flows into the LIR from the lowerer and is subsequently consumed by the [c_backend](../c_backend/design.md) for code emission.

Before reaching the backend, the LIR may undergo optimization passes in the [optimizer](../optimizer/design.md) and a mandatory monomorphization pass in the [monomorphizer](../monomorphizer/design.md) to resolve generics into concrete C types. Additionally, a memory management pass may inject reference counting or slab allocation logic into the LIR.

The internal structure of the LIR is defined by four primary sum types:

1.  **LType**: Represents the Lyric type system at the intermediate level. It includes primitives (I8-U64, F32-F64, Bool, String), unit and error types, and complex types like structs, class handles, tuples, slices, maps, channels, generators, and tagged unions.
2.  **LValue**: Represents operands, such as variables, temporaries, literals (int, uint, float, string, bool, null), and references (index references, class field references).
3.  **LExpr**: Represents functional operations that produce values. These are "flat," meaning they take `LValue` operands rather than nested `LExpr` nodes. Examples include binary/unary operations, casts, field/index access, calls, allocations, and variant construction.
4.  **LStmt**: Represents side-effecting operations and control flow. It includes assignments, declarations, loops (`while`, `for`), conditionals (`if`, `switch`, `type_switch`), and concurrency primitives (`spawn`, `lock`, `send`, `select`). It also includes memory management statements like `StRefIncr`, `StRefDecr`, and `StSlabFree`.

## Interface Implementations

The `lir` module does not implement external interfaces in the traditional sense; rather, it defines the data contract that the [lowerer](../lowerer/design.md) must satisfy and the [c_backend](../c_backend/design.md) must consume. It is a "passive" module consisting primarily of data structures.

## Public API

The public API consists of the `LProgram` class and its constituent parts.

*   **LProgram**: The root container for a compiled Lyric package. It holds all top-level declarations:
    *   `structs`: [LStructDecl](lir.ly) instances.
    *   `classes`: [LClassDecl](lir.ly) instances.
    *   `enums`: [LEnumDecl](lir.ly) instances.
    *   `interfaces`: [LInterfaceDecl](lir.ly) instances.
    *   `functions`: [LFuncDecl](lir.ly) instances.
    *   `globals`: [LVarDeclData](lir.ly) instances.
    *   `type_defs`: [LTypeDef](lir.ly) instances.
    *   It also tracks metadata like `package_name`, `imports`, and various compiler flags (`slab_mode`, `slab_mode_soa`, `rc_free`, `unsafe_mode`, `detect_uaf`). It maintains maps for class and method renames (`class_renames`, `impl_method_renames`) and tracks which classes are subject to ownership rules (`owned_classes`).
*   **LFuncDecl**: Represents a function or method. It includes:
    *   `name`, `type_params`, `params`, `return_type`.
    *   `body`: A list of [LStmt](lir.ly) nodes.
    *   `receiver` and `receiver_type_params`: For methods.
    *   `relational_constraints`: For enforcing ownership rules.
    *   `is_exported`, `is_final`, `is_trusted`.
    *   `class_rename_map`: Handles name mapping for monomorphized or renamed classes within the function scope.
*   **resolve_class_types(self)**: A method on `LProgram` that performs a post-lowering or post-monomorphization pass to wire up `LType` nodes with their corresponding `LClassDecl` definitions. This is essential for the backend to know the layout and properties (like permanence or ownership) of classes. It recursively walks the entire program structure, including function parameters, return types, and all statements and expressions.

## Implementation Details

### Sum Type Encoding
The LIR uses a specific encoding for sum types due to the bootstrap compiler's lack of a native `any` type or tagged union dispatch. Each sum type (like `LExpr` or `LStmt`) consists of a `kind` enum and a set of nullable fields—one for each possible variant. Only the field corresponding to the `kind` is non-null. For example, an `LExpr` with `kind: ExBinOp` will have its `bin_op` field populated and all other variant fields set to null. This pattern is consistent with the AST implementation and allows for efficient, type-safe dispatch in the bootstrap environment.

### Expression Flattening
Expressions in LIR are "flat," meaning they do not contain nested `LExpr` nodes. Instead, complex expressions are broken down into a series of `StTempDef` statements that assign the result of a single operation to a temporary `LValue`. These temporaries are then used as operands for subsequent operations. This transformation is performed by the [lowerer](../lowerer/design.md). For example, `a + b * c` becomes:
1. `t1 = b * c`
2. `t2 = a + t1`

### Structured Control Flow
Unlike many intermediate representations that use basic blocks and jumps, the Lyric LIR preserves structured control flow. `LStmt` variants like `StIf`, `StWhile`, and `StFor` contain blocks of statements, preserving the high-level logic of the program. This makes the LIR an ideal representation for emitting C code, as it maps directly to C's block-structured syntax.

### Memory Management
The LIR includes explicit support for Lyric's unique memory management features:
*   **Slab Allocation**: `ExSlabAlloc`, `ExSlabGet`, `StSlabSet`, and `StSlabFree` support high-performance memory management for specific class types.
*   **Reference Counting**: `StRefIncr` and `StRefDecr` are used for managing the lifecycle of shared objects. `StSliceRcRelease` handles releasing reference counts for elements within a slice before the slice itself is freed.
*   **Ownership**: The `is_owned` flag on `LType` and `LClassDecl` tracks whether a value is subject to Lyric's relational ownership rules.

### Type Resolution
The `resolve_class_types` function and its helpers (`resolve_type`, `resolve_stmts`, `resolve_stmt`, `resolve_expr`, `resolve_value`) are critical for maintaining the integrity of the LIR. They ensure that every `LType` that refers to a class is correctly linked to its declaration, allowing the backend to access class-specific metadata like field layouts and interface implementations.

## Dependencies

*   **[src/ast](../ast/design.md)**: The LIR is conceptually derived from the AST, though it uses a separate set of data structures optimized for code generation.
*   **[src/checker](../checker/design.md)**: The LIR relies on the semantic information (types, symbols) resolved by the checker.
*   **[src/lowerer](../lowerer/design.md)**: The lowerer is the primary producer of LIR.
*   **[src/monomorphizer](../monomorphizer/design.md)**: Resolves generic types and functions into concrete LIR instances.
*   **[src/optimizer](../optimizer/design.md)**: Performs transformations on the LIR to improve performance.
*   **[src/c_backend](../c_backend/design.md)**: The C backend is the primary consumer of LIR.

## Technical Debt and Future Work

*   The current LIR is heavily tailored for the C backend. Future backends (like LLVM or WASM) might require a more traditional SSA form with basic blocks and PHI nodes.
*   The "nullable variant fields" pattern, while effective for bootstrap, is verbose. A more ergonomic tagged union system in the language would simplify these definitions.
*   The `resolve_class_types` pass is currently manual and must be called at specific points in the pipeline. Automating this or making it more robust would reduce the risk of stale references.
