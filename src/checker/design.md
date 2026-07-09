# Checker Module Design

## Executive Summary

The `checker` module is the semantic heart of the Lyric compiler. It performs a sophisticated, multi-phase analysis of the Abstract Syntax Tree (AST) to ensure type safety, resolve symbols, and enforce the language's unique architectural invariants. Its primary output is a fully annotated AST where every expression is bound to a resolved type, creating a strictly typed contract for the downstream lowerer.

The checker is deeply integrated with Lyric's **Relations** ownership system. It validates relational hint shapes, enforces interface satisfaction, and implements "dotted-scope" access resolution for relational sub-scopes. By the end of the checking process, the AST has been transformed from a purely syntactic tree into a complete semantic model.

## File Inventory

- [checker.ly](checker.ly): The monolithic implementation of the Lyric type checker. It defines the internal type system, the multi-phase checking orchestration, and the detailed logic for expression-level type inference and validation.
- [checker.ly.lyric](checker.ly.lyric): A Context-Driven Development (CDD) design file that captures the architectural invariants, the "why" behind the checker's design, and the formal definitions of its internal structures.
- [design.md](design.md): This documentation file, providing a high-level architectural overview and technical narrative of the module.

## Architecture and Data Flow

The checker operates as a strictly ordered sequence of passes over the AST. It maintains a global `Registry` of types and a hierarchical `Scope` for variable resolution. The data flow is unidirectional: it ingests a desugared AST and produces a fully annotated AST.

### The Multi-Phase Pipeline

The checker performs a three-phase pass over the AST to ensure that all references, including cross-file and forward references, are correctly resolved.

1.  **Phase 0: Preregistration (`preregister_type_names`)**: The checker walks all blocks in the program to register stub `TypeInfo` entries for every named type (structs, classes, enums, interfaces). This "name-only" pass ensures that cross-block type references can be resolved in subsequent phases.
2.  **Phase 1: Registration (`register_lyric_block`)**: The checker performs a detailed walk of all declarations, populating the `Registry` with full field and method information. It also registers top-level functions, constants, and type aliases into the global scope.
3.  **Phase 1.5: Interface Linking (`register_interface_methods`)**: This phase links `impl` blocks to concrete types. It handles the registration of interface methods on concrete classes, including the complex logic for labeled methods injected by relational ownership declarations.
4.  **Phase 1.6: Relational Hint Validation (`validate_relation_hints`)**: This pass enforces structural invariants on interfaces used as relational hints. It ensures they have exactly two type parameters (parent and child) and that all members are correctly annotated with a side.
5.  **Phase 1.7: Interface Satisfaction (`validate_impl_satisfies_abstract`)**: The checker verifies that every `impl` block provides implementations for all abstract members of its target interface, either through explicit mappings or existing class members.
6.  **Phase 2: Body Checking (`check_lyric_block_bodies`)**: The checker walks all function bodies, performing type inference and validation for every statement and expression. This is where the bulk of the semantic logic resides.
7.  **Invariant Validation**: After all phases complete, the checker runs a series of validators (`validate_all_exprs_resolved`, `validate_field_and_method_access`) to ensure the integrity of the annotated AST.

CRITICAL: `check_file` runs Phase 0 across ALL blocks, then Phase 1 across ALL blocks, then Phase 2 across ALL blocks. This ensures cross-file type references and cross-file method calls all resolve correctly.

## Interface Implementations

The `checker` module does not implement external interfaces. Instead, it defines the internal `Type` and `TypeInfo` structures that act as the semantic model for the entire compiler. It consumes the AST nodes defined in the [src/ast](../ast/design.md) module.

## Public API

The primary entry point to the module is the `check_file` function:

- `check_file(file: File) -> Checker`: Orchestrates the entire multi-phase checking process for a given file (which may contain multiple blocks). It returns a `Checker` instance containing the results of the analysis.

### The Checker Class

The `Checker` class maintains the state of the semantic analysis:

- `errors: [string]`: A list of semantic errors encountered during checking, each prefixed with source location information.
- `registry: Registry`: The global symbol table for all named types.
- `scope: Scope`: The current resolution scope, which manages variable bindings and parent-scope lookups.
- `current_func: FuncDecl?`: The function currently being checked, used to resolve `self` and `impl` aliases.

## Implementation Details

### Internal Type System

The checker uses a rich internal representation for types, defined by the `Type` class and the `TypeKind` enum. This system supports:
- **Primitives**: `Int`, `Uint`, `Float` (with bit-widths), `Bool`, `String`.
- **Composites**: `Optional`, `Sequence`, `Map`, `Tuple`, `Func`, `Channel`, `Generator`.
- **Named Types**: `Struct`, `Class`, `Enum`, `Interface`, `Module`.
- **Generics**: `TypeVar` for unresolved type parameters.

### Assignability and Inference

The `is_assignable(src, to)` method implements Lyric's subtyping rules. It handles interface satisfaction (structural subtyping), numeric widening (e.g., `i32` to `i64`), and the unique "Nil-assignable-to-everything" rule. Generic inference is handled by `match_type_vars`, which compares concrete argument types against function parameter patterns to bind type variables.

### Relations and Sub-Scopes

The checker implements "labels-as-scopes" resolution. When it encounters a field access or method call like `obj.label.member`, and `label` is a relational sub-scope, the checker rewrites the AST in-place to use the mangled internal name (e.g., `obj.__label_member`). This allows the relations system to provide a clean, scoped syntax while maintaining a flat, efficient implementation.

### Expression Annotation

The "contract" between the checker and the lowerer is the `resolved_type` field on every `Expr` node. The `annotate(expr, type)` function converts the internal `Type` representation back into an AST `TypeExpr` and attaches it to the node. The lowerer relies exclusively on these annotations to generate correctly typed C code.

## Dependencies

- **[src/ast](../ast/design.md)**: The checker depends on the AST for its input and for the `TypeExpr` nodes used in annotations.
- **[src/desugar](../desugar/design.md)**: The checker requires a desugared AST where high-level constructs like `relation` have been expanded.
- **[runtime](../../runtime/design.md)**: The checker's built-in function registration (e.g., `len`, `append`) aligns with the primitives provided by the Lyric runtime.

## Technical Debt and Future Work

- **Constraint Validation**: Full structural validation of generic constraints (e.g., `where T: Hashable`) is partially implemented and currently relies on hard-coded built-ins.
- **Incremental Compilation**: The checker currently processes the entire program at once. Implementing incremental checking at the module level is a key goal.
- **Error UX**: Enhancing error messages with better source span highlighting and actionable suggestions.
