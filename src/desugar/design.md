# Desugar Module

## Executive Summary

The `desugar` module is a critical transformation layer in the Lyric compiler that operates between the parser and the type checker. Its primary responsibility is to lower high-level, expressive language constructs into a simplified, canonical Abstract Syntax Tree (AST) that the checker and subsequent backend stages can process more easily. By expanding complex features like interface inheritance, relational ownership, and default method implementations into basic fields, methods, and implementation blocks, the desugarer significantly reduces the semantic complexity of the rest of the compiler.

The module implements a strictly ordered, seven-pass pipeline that mutates the AST in-place. Each pass is designed to produce AST structures that subsequent passes rely upon, making the execution order a fundamental invariant of the system. All seven passes must complete before the checker runs, ensuring the checker only ever encounters plain classes, fields, methods, and implementation blocks.

## File Inventory

*   [desugar.ly](desugar.ly): The primary implementation file containing the seven-pass desugaring pipeline, deep-copy utilities, and type parameter substitution logic.
*   [desugar.ly.lyric](desugar.ly.lyric): A metadata and documentation file that defines the module's architecture, invariants, and function mappings for the Lyric toolchain.

## Architecture and Data Flow

The `desugar` module processes a `File` AST node through a sequence of seven transformation passes. This pipeline is orchestrated by the `desugar_all` function, which ensures that each pass runs in the correct order to satisfy internal dependencies.

### The Desugaring Pipeline

The transformation follows a fixed sequence where each stage prepares the AST for the next:

1.  **Interface Extension Materialization** (`desugar_interface_extends`): Resolves interface inheritance by copying members—including methods, fields, and destructors—from parent interfaces into their children. It handles transitive inheritance recursively and performs type parameter substitution. Child members win on name collisions. This pass runs first so inherited fields can be processed by subsequent passes.
2.  **Interface Field Synthesis** (`desugar_interface_fields`): Converts field declarations on interfaces into pairs of synthesized getter and setter method signatures. These accessors are marked as synthesized to distinguish them from user-authored methods during later semantic analysis.
3.  **Field Access Rewriting** (`desugar_field_access`): Traverses method and destructor bodies within interfaces to rewrite shorthand field accesses (e.g., `self.field`) into the corresponding getter or setter method calls.
4.  **Relation Materialization** (`desugar_relations`): A complex multi-stage process handling the language's relational ownership system.
    *   **Phase A (Skeleton Synthesis)**: Creates `ImplBlock` skeletons from `RelationDecl` nodes, capturing per-side labels and ownership kinds.
    *   **Phase B (Ownership Materialization)**: Injects label-prefixed fields into concrete classes and generates `FieldBind` mappings, treating relation-synthesized and user-authored ownership blocks uniformly.
    *   **Phase C (Sub-Scope Metadata)**: Populates `SubScope` records on classes to track labeled relational roles for precise collision detection in the checker.
5.  **Destructor Synthesis** (`desugar_destructors`): Deep-copies interface destructor blocks onto concrete classes for every ownership-bearing implementation. It renames generic method calls to their label-prefixed concrete forms based on the implementation's labels.
6.  **Default Method Specialization** (`desugar_specialize_default_impls`): Creates fully-specialized copies of default-bodied methods on concrete receiver classes for plain implementation blocks. It uses rich substitution to bake in type arguments, simplifying downstream resolution and avoiding complex receiver-only inference in the monomorphizer.
7.  **Default Method Extraction** (`desugar_default_impls`): Moves any remaining interface methods with bodies into top-level generic functions guarded by relational `where` clauses, ensuring they are available to all conforming classes while keeping interface declarations abstract.

## Interface Implementations

The `desugar` module does not explicitly implement external interfaces. Instead, it provides a functional API that operates on the AST types defined in the [src/ast](../ast/design.md) module. It acts as a consumer of the `ast` module's data structures and a producer of the "desugared" AST consumed by the [src/checker](../checker/design.md).

## Public API

The primary entry point for the module is:

*   `func desugar_all(file: File)`: Orchestrates the entire seven-pass desugaring pipeline on a single source file's AST.

Supporting utilities include:
*   `func deep_copy_block(b: Block?) -> Block?`: Performs a deep, recursive copy of an AST block, ensuring no data pointers are shared.
*   `func substitute_type_params_rich_in_block(block: Block, type_map: Dict<Sym, TypeExpr>)`: Performs type parameter substitution using a "rich" strategy that preserves full type arguments (e.g., `Dict<K, V>`).
*   `func rename_method_calls_in_block(block: Block, renames: Dict<Sym, string>)`: Rewrites method call names within a block, used for mapping generic interface calls to label-prefixed concrete methods.

## Implementation Details

### Substitution Strategies

The module employs two distinct type substitution strategies to handle different levels of complexity:
*   **Simple Substitution**: Replaces type names as strings using a `Dict<Sym, string>`. This is used for field injection and basic rewrites where only the top-level name is relevant.
*   **Rich Substitution**: Uses `TypeExpr` objects for mapping (`Dict<Sym, TypeExpr>`), preserving generic arguments. This is essential for destructors and default method specialization where complex types like `Dict<K, V>` must remain intact across copies. Mixing these strategies (e.g., using simple substitution for destructors) leads to ill-typed AST that the checker will reject.

### Deep Copy and Pointer Stability

To prevent cross-contamination when mutating copied AST nodes (such as renaming methods in a specialized destructor), the module implements a comprehensive deep-copy mechanism. Every node, from blocks and statements to expressions and type arguments, is reconstructed. A critical detail is the cloning of `TypeArgs` slices in call expressions, as rich substitution mutates these in-place. Without this cloning, the last relation processed would incorrectly overwrite the type arguments for all previously processed destructors.

### Relational Materialization Logic

The `desugar_relations` pass bridges the gap between high-level relational declarations and the concrete fields and mappings that implement them.
*   **Impl Merging**: When synthesizing an implementation block, the desugarer attempts to find an existing matching block. Per-side labels are part of the implementation's identity; two relations sharing the same interface and classes but using different labels result in independent implementation blocks.
*   **Field Injection**: Fields injected into classes are mangled with a double-underscore prefix (e.g., `__label_field`) to prevent direct access and avoid collisions with user-defined members. The dotted-scope sugar (e.g., `team.roster.children`) is the intended user-visible path.
*   **Mapping Dedup**: The desugarer generates `FieldBind` mappings but carefully dedupes them against user-authored mappings. User-authored bindings take precedence, allowing developers to override the default mechanical glue.

### Default Method Specialization (Pass 4.5)

This pass handles the specialization of default-bodied methods for multi-class interfaces. By baking in the concrete type bindings at desugar time, it removes the burden of complex type inference from the monomorphizer.
*   **Back-pointers**: Every specialized function is tagged with `fn.source_impl = ib`, allowing the checker to consult the original implementation's alias bindings when resolving references inside the specialized body.
*   **Collision Detection**: If two implementations produce the same `Class.method` specialization (e.g., a class implements two interfaces with the same default method name), the desugarer panics. Users must disambiguate using labels or explicit alias bindings.

### Global Class Lookup

During relation materialization and destructor synthesis, the desugarer performs a global lookup of classes across all blocks in a file. This is necessary because relations often link classes declared in different parts of the source code (e.g., a `Lexer` in one block owning a `Comment` defined in another). A per-block lookup would fail to inject fields or rename methods correctly, leading to downstream errors like missing label-prefixed methods.

## Dependencies

*   **[src/ast](../ast/design.md)**: The desugarer depends heavily on the AST module for all node definitions and the `ArrayList` relations used to traverse and mutate the tree.
*   **[src/parser](../parser/design.md)**: It relies on the parser's `Sym` (symbol) implementation for name comparisons and symbol generation.

## Technical Debt and Future Work

*   **AST Reconstruction Gaps**: The `deep_copy_stmt` and `deep_copy_expr` functions have known limitations due to name collisions in the checker:
    *   **Lock Statements**: Cannot be reconstructed because `Lock()` collides with the `TypeKind.Lock` enum variant.
    *   **Match Expressions**: Cannot be reconstructed because `Match()` collides with the `StmtKind.Match` enum variant.
    While these do not currently affect desugaring (as these constructs are rare or absent in destructor bodies), they must be addressed for the desugarer to support arbitrary code copying.
*   **Sub-Scope Refactor**: The current implementation of sub-scopes (Phase C of `desugar_relations`) is "Tier 1" (metadata only). Future work may involve migrating injected members directly into sub-scope containers to further clean up the class namespace.

Documentation complete.
