# AST Module Design

## Executive Summary

The `ast` module defines the Abstract Syntax Tree (AST) for the Forge language, serving as the foundational data model for the entire compiler toolchain. It provides a comprehensive set of data structures that capture the semantics of both Forge declaration files (`.forge`) and implementation files (`.fg`). The module is designed as a leaf package with minimal internal dependencies, ensuring that the data structures can be safely consumed by the parser, type checker, and code generator.

Beyond simple data definition, the `ast` module implements a sophisticated desugaring engine. This engine transforms high-level Forge constructs—such as multi-class interfaces, ownership relations, and interface embedding—into simpler, lower-level AST forms. This transformation simplifies the subsequent type checking and code generation stages. The module also handles module resolution by flattening imported packages into a single namespace and selectively merging required components from the standard library using transitive reachability analysis.

## File Inventory

- [ast.go](ast.go): Defines the core top-level AST nodes, including `File`, `ForgeBlock`, and declarations for classes, interfaces, functions, enums, structs, and constants. It also contains the `TypeExpr` system for representing Forge's rich type language.
- [ast.forge](ast.forge): The Forge specification file for the `ast` module itself. It contains high-level architectural documentation and defines the structure of the AST in Forge's own declaration language, serving as the primary source of architectural truth.
- [expr.go](expr.go): Contains the definitions for all expression types (`Expr`), statement types (`Stmt`), and patterns (`Pattern`), along with their respective kinds and data payloads. It defines the building blocks of function bodies and control flow.
- [modules.go](modules.go): Implements the module system's resolution logic. It handles parsing imported packages, prefixing names to avoid collisions, and rewriting qualified references (e.g., `pkg.Name`) into flattened names (e.g., `pkg_Name`).
- [desugar.go](desugar.go): The heart of the AST transformation engine. It contains multiple passes that flatten interface hierarchies, inject fields based on relations, generate getter/setter methods for interface fields, and synthesize destructor logic.
- [stdlib.go](stdlib.go): Provides functionality to selectively merge declarations from the Forge standard library into the user's AST. It uses transitive reachability analysis to ensure only used components (and their dependencies) are included, preventing AST pollution.
- [validate.go](validate.go): Implements post-transformation invariant checks. It verifies that desugaring passes have correctly flattened the AST and injected required fields, ensuring the AST is in a valid state for the type checker.
- [desugar_test.go](desugar_test.go): Contains comprehensive tests for the desugaring logic, ensuring that complex transformations like relation-based field injection and destructor generation work as expected.

## Architecture and Data Flow

The AST is a strict hierarchy rooted in the `File` node. A `File` contains one or more `ForgeBlock` nodes, each representing a logical grouping within a `forge { ... }` block. This structure allows a single source file to contain multiple architectural modules or namespaces.

The typical data flow involving this module is as follows:

1.  **Parsing**: The parser (external to this module) reads `.forge` and `.fg` files and populates the `File` and `ForgeBlock` structures.
2.  **Module Resolution**: `ResolveModuleImports` in [modules.go](modules.go) is called. It traverses the import graph, parses dependencies, and merges them into the root `File`. It performs name mangling to flatten the package hierarchy into a single global namespace.
3.  **Stdlib Merging**: `MergeStdlib` in [stdlib.go](stdlib.go) identifies which standard library components (like `Dict` or `ArrayList`) are referenced by the user's code or relations and merges their declarations into the AST.
4.  **Desugaring**: A sequence of five ordered passes in [desugar.go](desugar.go) is executed:
    - **DesugarInterfaceEmbeds**: Flattens the interface hierarchy by copying methods, fields, and destructors from embedded interfaces into the embedding interface, substituting type parameters.
    - **DesugarInterfaceFields**: Converts abstract interface fields into concrete getter and setter method signatures.
    - **DesugarRelations**: Processes `relation` declarations. It injects the necessary state (fields) into the participant classes and generates `impl` blocks that map interface methods to these fields.
    - **DesugarDestructors**: Synthesizes `destroy` methods for classes, incorporating cleanup logic defined in interface `destructor` blocks.
    - **DesugarDefaultImpls**: Moves method bodies defined directly in interfaces into top-level functions with appropriate `where` clauses.
5.  **Validation**: `ValidatePostDesugar` in [validate.go](validate.go) runs a series of sanity checks to ensure the desugaring passes didn't leave the AST in an inconsistent state.
6.  **Type Checking**: The transformed and validated AST is passed to the type checker for semantic analysis.

## Interface Implementations

The `ast` module primarily defines data structures and does not implement many external interfaces. However, it defines the core types that almost every other module in the compiler must interact with. The `File` structure is the primary "document" passed between compiler stages.

## Public API

### Core Data Structures
- **`File`**: The root node of the AST, containing a collection of `ForgeBlock`s and comments.
- **`ForgeBlock`**: A logical grouping of declarations (classes, interfaces, functions, etc.).
- **`TypeExpr`**: A recursive structure representing any Forge type, from simple named types to complex function and union types.
- **`Expr` and `Stmt`**: The building blocks of function bodies, using a `Kind`/`Data` pattern for type-safe polymorphism.
- **`Annotations`**: Captures safety and concurrency metadata: `pure`, `spawns`, `RequiresLock`, `ExcludesLock`, `GuardedBy`, `requires` (preconditions), and `ensures` (postconditions).

### Primary Functions
- **`ResolveModuleImports(moduleRoot string, rootFile *File, parseFn func(path string) (*File, error)) (*File, error)`**: Resolves the entire import tree for a module.
- **`MergeStdlib(file *File, stdFile *File)`**: Selectively merges the standard library into the provided AST.
- **`DesugarRelations(file *File)`**: A complex desugaring pass handling the core of Forge's relational state management.
- **`ValidatePostDesugar(file *File) []InvariantViolation`**: Returns a list of any invariant violations found in the AST after desugaring.
- **`MergeFiles(files []*File) *File`**: Merges multiple parsed AST files into a single file for multi-file compilation.
- **`FindStdlibDir() string`**: Locates the standard library directory based on environment variables or relative paths.

## Implementation Details

### The Kind/Data Pattern
To represent polymorphic nodes like expressions and statements in Go, the module uses a "Kind/Data" pattern. Each `Expr`, `Stmt`, or `TypeExpr` has a `Kind` field (an enum) and a `Data` field (an `any`). Consumers type-assert `Data` based on `Kind`. This avoids deep interface hierarchies while supporting recursive structures.

### Pointer Stability and Checker Annotations
`Expr` and `Stmt` are value types (structs), not pointers. However, the type checker annotates these nodes in place via pointers (e.g., `Expr.ResolvedType`). It is critical that AST nodes are not copied by value after they have been annotated, as this would break the link between the node and its metadata. When iterating over slices of expressions or statements, always use index-based loops (`for i := range slice`) and take the address of the element (`&slice[i]`) to ensure pointer stability.

### Deep Copying and Substitution
Desugaring often involves copying code blocks (e.g., destructor bodies) from one part of the AST to another. To prevent accidental shared state, the module implements a robust `deepCopyBlock` mechanism in [desugar.go](desugar.go). This is paired with "rich" type parameter substitution (`substituteTypeParamsRichInBlock`), which replaces type parameters with full `TypeExpr` nodes, preserving generic arguments (e.g., replacing `P` with `Dict<V>`).

### Relational Desugaring
The `DesugarRelations` pass is a key innovation. When a relation like `relation DoublyLinked Parent:p owns [Child:c]` is encountered, the pass:
1.  Looks up the `DoublyLinked` interface.
2.  Identifies the fields required by the interface (e.g., `first`, `last`, `next`, `prev`).
3.  Injects these fields into the `Parent` and `Child` classes, prefixing them with the provided labels (`p_`, `c_`) to avoid collisions.
4.  Generates an `impl` block that binds the interface's abstract methods to these newly injected fields.

### Stdlib Merging Invariants
`MergeStdlib` uses transitive reachability to pull in only necessary declarations. It must exclude primitive types (e.g., `string`, `i32`) from type-name collection to avoid pulling in the entire standard library for programs that only use built-in types. The `primitiveTypes` map in [stdlib.go](stdlib.go) serves as this exclusion filter.

## Dependencies

The `ast` module is designed to be a low-level component with minimal internal dependencies.

- **Standard Library**: `fmt`, `os`, `path/filepath`, `strings`.
- **Internal**: This module is a leaf in the dependency graph and does not depend on other `pkg/` modules. It is consumed by:
    - [pkg/parser](../parser/design.md) (to populate the AST)
    - [pkg/checker](../checker/design.md) (to validate and annotate the AST)
    - [pkg/lowerer](../lowerer/design.md) (to convert the AST to LIR)

## Technical Debt and Future Work

- **Semantic Validation**: The AST currently lacks checks for circular interface inheritance or duplicate fields at the data structure level.
- **Serialization**: There is no built-in support for serializing the AST (e.g., to JSON or Protobuf), which limits external tooling and incremental compilation caching.
- **Visitor Pattern**: As the number of node types grows, the traversal logic in consumers (like the checker and lowerer) becomes unwieldy. Implementing a generic walker or visitor pattern would improve maintainability.
- **Incremental Compilation**: The current design assumes a full-world view for desugaring and stdlib merging. Supporting incremental compilation would require a more modular approach to transformation passes.
