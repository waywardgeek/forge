# Checker Module Design

## Executive Summary

The `checker` module is the semantic heart of the Forge compiler. It performs comprehensive type checking, type inference, and semantic validation on the Abstract Syntax Tree (AST) produced by the parser. Its primary responsibility is to transform a raw, untyped AST into a fully annotated AST where every expression has a resolved type, and all semantic rules of the Forge language are enforced. The checker handles complex language features including structural subtyping, generic type inference, numeric widening, concurrency safety via lock enforcement, exhaustive pattern matching, and relational constraints. By catching errors before code generation, it ensures that the resulting C code is both type-safe and semantically correct.

## File Inventory

- [checker.go](checker.go): The core implementation of the type checker, containing the type system definitions, scope management, and the multi-phase checking logic.
- [checker.forge](checker.forge): A Forge-language specification of the checker's own architecture, providing high-level documentation of its design principles and a detailed index of its implementation methods.
- [checker_test.go](checker_test.go): A comprehensive suite of tests covering all aspects of the type system, from basic literal inference to complex generic constraints, module imports, and concurrency safety.

## Architecture and Data Flow

The checker operates as a multi-phase processor that walks the AST and populates `ResolvedType` fields on expression nodes. It maintains a global `Registry` of types and a hierarchical `Scope` for variable and type variable resolution.

### Multi-Phase Checking Process

To handle forward references and cross-file dependencies, the checker executes in several distinct phases when processing a file or a collection of files:

1.  **Phase 0: Type Name Registration**: Scans all blocks to register the names of structs, classes, enums, and interfaces. This allows types to refer to each other regardless of declaration order.
2.  **Phase 1: Signature Registration**: Resolves full type signatures for all declarations. This includes resolving field types, method signatures, and function parameters. For classes and generic functions, type parameters are registered as type variables in a temporary scope to resolve internal references. This phase also checks that classes correctly implement their declared interfaces.
3.  **Phase 2: Body Checking**: Recursively walks through function and method bodies. It performs type inference on expressions and validates statements against the expected types. For generic functions, type parameters are registered in the function's scope.
4.  **Phase 3: Type Resolution Validation**: Ensures that no `TyUnknown` types remain in function signatures, ensuring all types were successfully resolved.
5.  **Phase 4: Expression Resolution Validation**: Ensures that every expression node in the AST has been annotated with a `ResolvedType`.
6.  **Phase 5: Access Validation**: Performs a final pass to ensure all field and method accesses are valid on their receiver types, catching any issues that might have been introduced during desugaring (e.g., label-prefix renaming).

### Data Flow

The primary data flow is from a raw `ast.File` or a collection of `ast.File` objects into the `Checker`. The `Checker` modifies these AST nodes in-place by setting their `ResolvedType` fields (stored as `any` in the AST to avoid circular imports). If errors are encountered, they are collected in the `Checker.errors` slice, allowing the compiler to report multiple errors in a single run. The final annotated AST is then consumed by the `lowerer` module.

## Interface Implementations

The `checker` module provides the core logic for validating that Forge classes correctly implement their declared Forge interfaces. It uses structural subtyping: a class satisfies an interface if it provides all the required methods with matching signatures.

The module also pre-registers the built-in `error` interface, which is satisfied by any class providing a `message(self) -> string` method.

Internally, the `Checker` does not implement any Go interfaces defined in other packages, but it is a primary consumer of the `ast.File` structure.

## Public API

The `checker` module exposes a clean interface for performing type checking:

- **`New() *Checker`**: Initializes a new checker instance. It pre-registers built-in types (like `int`, `string`, `bool`, `any`) and standard library modules (like `fmt`, `strings`, `errors`, `strconv`) to ensure they are available for name resolution.
- **`CheckFile(file *ast.File)`**: Performs full type checking on a single AST file. It runs all phases sequentially for the given file.
- **`CheckFiles(files []*ast.File)`**: Performs type checking across multiple files. This is the preferred entry point for multi-file compilation as it runs Phase 0 and 1 across all files before starting Phase 2, enabling cross-file method and type resolution.
- **`Errors() []error`**: Returns the list of `CheckError` objects encountered during checking. Each error includes a descriptive message and an `ast.Span` for precise source location reporting.
- **`Type`**: A struct representing a resolved type. It includes a `Kind` (e.g., `TyInt`, `TyFunc`, `TyClass`) and associated metadata such as bit width for numeric types, parameter and return types for functions, and type arguments for generic instances.

## Implementation Details

### Type System

The Forge type system is represented by the `Type` struct and `TypeKind` enumeration. It supports:
- **Primitive Types**: Integers of various widths (`i8` to `i256`), unsigned integers, floats, booleans, and strings.
- **Composite Types**: Lists (`[T]`), maps (`map[K]V`), tuples (`(T, U)`), and optionals (`T?`).
- **Named Types**: Structs, classes, enums, and interfaces.
- **Advanced Types**: Functions, channels, generators, and union types (`T | U`).
- **Special Types**: `any` (empty interface), `nil` (nullable literal), `TyModule` (imported modules), and `TyError` (error sentinel for suppressing cascading errors).

Type equality is structural via the `Equal()` method. The `assignableTo()` method extends equality to handle interface subtyping, numeric widening (e.g., `i32` to `i64`), and optional wrapping (e.g., `T` to `T?`).

### Type Inference and Substitution

The checker performs sophisticated type inference for both literals and generic function calls. When a generic function is called without explicit type arguments, `inferTypeArgs` walks the parameter types and actual argument types in parallel to bind type variables. `substituteType` then applies these bindings to the function's return type and any remaining parameters.

For literals, the checker infers the most specific type (e.g., `42` is `i32` by default, but can be coerced to other integer widths). `nil` literals require an explicit type annotation or context to be resolved.

### Concurrency Safety

A unique feature of the Forge checker is its enforcement of the `guarded_by` annotation. If a class field is marked as `guarded_by(mu)`, the checker tracks the set of held locks (via `lock(mu) { ... }` statements) in the `heldLocks` map. It reports an error if the field is accessed without the corresponding lock being held.

### Pattern Matching and Exhaustiveness

The checker validates `match` statements for both enums and union types. For enums, it ensures that every variant is covered or a wildcard (`_`) is present. For union types, it narrows the type of the matched value within each arm's scope. In union matching, `PatIdent` names are resolved as type references, and the resolved type is stored in the pattern for use by the code generator.

### Relational Constraints

The checker supports relational constraints via `where` clauses (e.g., `where Graph<G, N, E>`). These constraints grant methods to type variables based on the specified interface. The checker maps interface type parameters to the actual type variables used in the constraint, allowing for multi-class interface validation. This is handled by `resolveRelationalConstraint` which populates the `typeVarMethods` map.

### Try and Is Operators

The `?` (try) operator is validated to ensure it is used on `(T, error)` tuples within functions that return an error type. The `is` operator is validated for use with enum variants, ensuring the variant exists on the operand's enum type and returning a boolean.

### Lambdas

Lambda expressions are checked by creating a new scope for parameters and validating the body against the inferred or declared return type. The checker supports both single-expression and block-bodied lambdas.

## Dependencies

- **[pkg/ast](../ast/design.md)**: The checker consumes and annotates AST nodes defined in this package. It relies on the `Expr.ResolvedType` field for annotation.
- **[pkg/parser](../parser/design.md)**: Used to parse imported `.fg` module files during Phase 1 if they haven't been processed yet.

## Technical Debt and Future Work

- **Monomorphization Support**: The checker currently annotates the AST with generic types; the actual generation of concrete instances (monomorphization) is handled by the `lir` module. The checker could provide more metadata to assist this process.
- **Circular Dependencies**: While basic cycle detection exists for imports, complex circular dependencies between types across many files may still trigger edge cases.
- **Advanced Relational Constraints**: Further refinement of relational constraints may be needed for more complex multi-class interface scenarios, particularly involving deep inheritance.
- **Exhaustiveness Warnings**: Currently, non-exhaustive matches are reported as warnings; these could be upgraded to errors or made configurable.
