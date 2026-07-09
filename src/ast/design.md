# AST Module Design

## Executive Summary

The `ast` module defines the Abstract Syntax Tree (AST) for the Lyric bootstrap compiler. It provides the foundational data structures that represent Lyric source code and implements critical transformations for module resolution and selective standard library integration. As a leaf package in the bootstrap toolchain, it is shared by the parser, checker, desugarer, and lowerer.

The module is designed to support Lyric's self-hosting requirement, leveraging the language's unique relational ownership system to manage the tree's hierarchy. It also implements a "namespace flattening" strategy for module imports and a transitive dependency analysis for standard library merging, ensuring that the final compiled output is both correct and efficient.

## File Inventory

- [ast.ly](ast.ly): Defines the core AST node types (classes and structs), enums for various kinds (expressions, statements, types), and utility functions for merging files and selectively loading the standard library. It contains the complex `merge_stdlib` logic.
- [modules.ly](modules.ly): Implements the module resolution system, which flattens imported packages into a single namespace by prefixing declarations and rewriting qualified references.
- [ast.ly.lyric](ast.ly.lyric): A metadata file containing documentation and source mapping for the module.

## Architecture and Data Flow

The AST is a strict hierarchy rooted in the [File](ast.ly) class. A `File` contains one or more [LyricBlock](ast.ly) nodes, which in turn contain declarations (functions, classes, structs, etc.). Data flows into the AST from the parser; once constructed, the AST becomes the source of truth for all subsequent compiler phases.

The AST supports two primary file formats:
- **.lyric**: Declaration-only files where function bodies are null.
- **.ly**: Full implementation files containing executable blocks.

### Relational Ownership
The AST uses Lyric's `relation ArrayList` to define parent-child ownership (e.g., `File` owns `LyricBlock`s via the `fb` relation). This ensures memory safety and clear lifecycle management without manual intervention. The relations are defined using the `relation` keyword, which the compiler later desugars into field-binds and destructor logic.

### Variant Data Representation
The self-hosted AST uses enums with associated data or nullable fields per variant on class types. For example, [Expr](ast.ly) has a `kind` enum ([ExprKind](ast.ly)) which uses Lyric's enum-with-data feature. This allows for type-safe representation of different expression types (literals, calls, binary ops, etc.) while maintaining a flat structure suitable for the C backend.

## Interface Implementations

The `ast` module defines the data structures that act as the primary contract between compiler phases. While it doesn't implement external interfaces in the traditional sense, it provides the `Expr`, `Stmt`, and `TypeExpr` nodes that are annotated by the checker and lowered by the middle-end.

- **Annotated AST**: The [Expr](ast.ly) class includes `resolved_type` and `inferred_type_args` fields, which are populated by the checker. This allows downstream phases (like the lowerer) to access semantic information directly from the tree.

## Public API

The `ast` module exports the following primary types and functions:

### Core Types
- **File**: The root of the AST for a single source file.
- **LyricBlock**: A container for top-level declarations.
- **Expr**: Represents an expression, annotated with `resolved_type` and `inferred_type_args` by the checker.
- **Stmt**: Represents a statement (variable declaration, assignment, control flow).
- **Pattern**: Represents a pattern used in `match` arms or `if let` / `let else` statements.
- **TypeExpr**: Represents a type reference or definition.
- **ClassDecl / StructDecl / EnumDecl**: Represent type declarations.
- **FuncDecl**: Represents function and method declarations.

### Primary Functions
- `merge_files(files: [File?]) -> File?`: Combines multiple parsed files into a single AST by appending their blocks.
- `resolve_module_imports(module_root: string, root_file: File?) -> (File?, string)`: Flattens the module hierarchy by parsing imports, prefixing names, and rewriting references.
- `merge_stdlib(file: File?, std_file: File?)`: Selectively merges standard library components into the target file using a transitive closure algorithm.
- `find_stdlib_dir() -> string`: Locates the standard library directory on the host system.

## Implementation Details

### Module Resolution (Namespace Flattening)

Because the bootstrap compiler targets a flat compilation model, `resolve_module_imports` (in [modules.ly](modules.ly)) flattens the package hierarchy into a single global namespace. This process occurs in three phases:
1. **Prefixing**: All declarations in an imported package receive a prefix based on the import alias (e.g., `math.sin` becomes `math_sin`).
2. **Internal Rewriting**: References within the imported package are updated to use these prefixed names.
3. **Qualified Access Rewriting**: Qualified references in the calling package (e.g., `math.sin(x)`) are rewritten to use the prefixed names (e.g., `math_sin(x)`).

### Transitive Stdlib Merge

To avoid bloating the final binary with unused code, `merge_stdlib` (in [ast.ly](ast.ly)) uses a transitive closure algorithm to selectively pull in only the necessary parts of the standard library:
1. It collects all type names and function calls used in the user's code.
2. It identifies matching declarations in the standard library.
3. It transitively follows references: if a merged function returns a stdlib class, that class is also merged.
4. It handles primitive extension methods (like `i32.get_hash`) required by generic code (e.g., `Dict`).
5. This process repeats until no new dependencies are discovered.

### Method Merging Invariant
A critical invariant in `merge_stdlib` ensures that a method (a `FuncDecl` with a `receiver_type`) is never merged unless its receiver class is also merged. If a method were merged without its class, the checker would fail to resolve the `self` reference, leading to a compiler panic. Primitive receivers (like `i32`) are exempt as they are handled by a dedicated pass.

### Advanced Metadata
The AST nodes carry specialized metadata to support complex language features:
- **SubScope**: The [ClassDecl](ast.ly) node includes a `css` relation to `SubScope` objects. These record relation-injected members (from `impl` blocks) to help the checker detect name collisions between user-defined methods and relation labels.
- **source_impl**: The [FuncDecl](ast.ly) node carries a `source_impl` pointer. When a default-bodied interface method is deep-copied onto a concrete class during desugaring, this pointer allows the checker to recover the full alias mapping for member resolution within the method body.
- **is_synthesized**: A flag on [FuncDecl](ast.ly) indicating the function was generated by a desugar pass (e.g., interface field getters). The checker uses this to skip certain contract satisfaction checks.

### Position and Spans
Every major AST node carries a `Span` (start and end `Pos`), which includes file, line, and column information. This is essential for generating precise error messages during semantic analysis and code generation.

## Dependencies

- **Parser**: The module resolution logic in [modules.ly](modules.ly) and the stdlib loading logic in [ast.ly](ast.ly) depend on the `parse_file` function from the [parser](../parser/design.md) module to ingest source code.
- **Runtime**: The generated C code for the AST nodes depends on the [runtime](../../runtime/design.md) module for relation management and basic types.

## Technical Debt and Future Work

- **Full TypeExpr Args**: Currently, `InterfaceDecl.extends_args` only supports bare type-variable names. Supporting full `TypeExpr` arguments in interface inheritance is a planned improvement.
- **Namespace Collisions**: While prefixing mitigates most name collisions during flattening, a more robust module system that preserves namespaces without renaming might be desirable in the future.
- **Desugaring Complexity**: The AST is subjected to multiple desugaring passes (InterfaceFields, Relations, Destructors, and DefaultImpls) before type checking. The order of these passes is fragile and must be strictly maintained.
