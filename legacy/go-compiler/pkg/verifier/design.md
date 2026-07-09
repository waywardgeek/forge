# Verifier Module Design

## Executive Summary

The `verifier` module serves as the structural integrity engine for the Forge compiler toolchain. Its primary mission is to detect and report architectural drift by performing a deep, recursive comparison between formal `.forge` modeling files and their corresponding Go source code implementations. By bridging the distinct type systems of Forge and Go, the verifier ensures that the developer's high-level mental model—documented in `.forge` files—remains perfectly synchronized with the actual codebase. Beyond simple type checking, the module also acts as a guardian of project-wide architectural invariants, using Go AST analysis to enforce subtle rules that prevent common bugs, such as the accidental range-copying of value types.

## File Inventory

- [verifier.go](verifier.go): The core implementation of the structural comparison engine. It contains the logic for parsing Go source code, extracting type information into a unified registry, and performing the recursive walk of Forge AST nodes against Go implementations.
- [verifier.forge](verifier.forge): The self-documenting Forge specification for the verifier module itself, defining its own public API and internal structures.
- [verifier_test.go](verifier_test.go): A comprehensive suite of unit tests that validate the verifier's ability to detect type drift, handle naming convention mappings, and ensure API completeness.
- [invariants_test.go](invariants_test.go): A specialized enforcement suite that leverages the verifier's AST parsing techniques to programmatically verify cross-cutting project invariants, such as desugaring order and safe iteration patterns.

## Architecture and Data Flow

The verifier is designed as a multi-stage analysis pipeline that operates statelessly between calls while maintaining a comprehensive internal registry during a single execution. The process begins with **Forge Parsing**, where the module delegates to [pkg/parser](../parser/design.md) to transform a `.forge` source file into a structured `forgeast.File`. 

The second stage is **Go Source Discovery**. The verifier inspects the `source:` annotations within each Forge block to identify the relevant Go implementation files or directories. These paths are resolved relative to the directory containing the `.forge` file, ensuring portability across different development environments.

The third stage, **Go Type Extraction**, is the heart of the bridge between languages. Using the standard `go/parser` and `go/ast` packages, the verifier parses the discovered Go source and populates a `goTypeInfo` registry. This registry aggregates all structs, interfaces, functions, and type definitions across all specified source files for a block. This aggregation is a critical architectural choice, as a single Forge block's implementation frequently spans multiple Go files within the same package.

Finally, the verifier performs **Structural Comparison**. It recursively walks the Forge AST and compares every declaration—including structs, classes, enums, interfaces, and functions—against the aggregated Go types. During this walk, it normalizes naming conventions and type expressions on the fly. Any discrepancies discovered are recorded as `Finding` objects, which are collected into a final `Result` for reporting.

## Interface Implementations

The `verifier` module does not explicitly implement external interfaces. Instead, it serves as a high-level consumer of the Forge AST defined in [pkg/ast](../ast/design.md) and the parser output from [pkg/parser](../parser/design.md). It acts as the primary bridge between these Forge-specific data structures and the standard Go AST, providing a unified view of the system's structural health.

## Public API

The primary entry point for the module is the `Verify` function:

- `func Verify(forgePath string) (*Result, error)`: This function orchestrates the entire verification pipeline. It takes the path to a `.forge` file, executes the parsing and discovery phases, performs the structural comparison, and returns a `Result` containing all findings.

The outcome of a verification run is encapsulated in the `Result` type:
- `Findings []Finding`: A collection of drift reports, each specifying a severity level, the relevant files, and a detailed message describing the mismatch.
- `func (r *Result) ErrorCount() int`: A utility method that returns the number of `Error` level findings. This is typically used by CLI tools to determine if the verification should fail a build or CI pipeline.

Findings are classified by `Severity`:
- `Error`: Represents a fundamental mismatch, such as a missing type, a wrong field type, or a parameter count mismatch.
- `Warning`: Indicates minor drift, such as extra Go fields not documented in `.forge` or naming convention inconsistencies.
- `Info`: Provides contextual information, such as additional Go methods that are not part of the formal Forge interface.

## Implementation Details

### Deep Type Comparison

The core of the drift detection logic resides in the `forgeTypeToGoString` function. This function recursively converts Forge `TypeExpr` nodes into a Go-compatible string format, allowing for direct comparison with the output of `typeExprString`, which processes Go AST expressions.

The mapping handles several key transformations:
- **Optional Types**: Forge's `T?` notation is mapped to Go's pointer type `*T`.
- **Sequences**: Forge's `[T]` sequence is mapped to Go's slice type `[]T`.
- **Maps**: Forge's `map[K]V` maps directly to the Go `map[K]V` syntax.
- **Primitives**: Forge primitive names are translated to their Go equivalents, such as `i32` becoming `int32` and `any` becoming `interface{}` (or `any` in Go 1.18+).
- **Package Stripping**: The `stripPackagePrefix` function heuristically and recursively removes Go package qualifiers (e.g., `ast.File` becomes `File`). This is essential because `.forge` files typically use unqualified type names, while Go source often uses qualified names for cross-package references.

### Name Mapping and Normalization

To bridge Forge's `snake_case` convention with Go's `PascalCase` (for exported symbols) or `camelCase` (for unexported symbols), the verifier employs a multi-try strategy. When searching for a Go field or method corresponding to a Forge name, it checks the `PascalCase` version, the `camelCase` version, and the exact match. This flexibility allows developers to use the most natural naming convention for each language while maintaining the link between them.

### Verification Rules and Completeness

The verifier applies specific rules based on the type of declaration:
- **Structs and Classes**: It checks for field existence and type matches. For classes, it also verifies method signatures, including parameter counts, positional types, and return types.
- **Interfaces**: It ensures that every method declared in the Forge interface exists in the Go implementation with a matching signature.
- **Enums**: It validates the existence of a matching Go type, checking for common patterns like `type X int` or `type XKind int`.
- **Completeness Check**: After verifying all declared symbols, the verifier performs a "reverse check" by walking all exported Go symbols in the source files. If an exported Go type or function is not documented in the `.forge` block, it reports an error. This ensures that the `.forge` file remains a complete and accurate specification of the public API.

### Architectural Invariants

A unique and powerful feature of the verifier module is its enforcement of architectural invariants, primarily located in `invariants_test.go`. These tests use Go AST parsing to enforce rules that the Go type system cannot catch:
- **Value Type Safety**: It ensures that `ast.Expr` (a value type) is never copied in a `range` loop, which would cause the loss of checker annotations. It mandates index-based iteration instead.
- **Desugaring Order**: It verifies the call order of desugaring passes in the compiler entry point, ensuring that transformations like interface embedding occur before relation injection.
- **State Management**: It checks that critical functions, such as `MergeStdlib`, only affect the root block of the program, preventing accidental global state corruption.

## Dependencies

- [pkg/ast](../ast/design.md): Provides the foundational Forge AST definitions used for comparison.
- [pkg/parser](../parser/design.md): Used to parse `.forge` files into the Forge AST.
- **go/ast, go/parser, go/token**: Standard Go library packages used for the deep analysis of Go source code.

## Technical Debt and Future Work

- **Expression Verification**: Currently, `requires` and `ensures` clauses are treated as raw strings and are not verified against the implementation logic.
- **Complex Pointer Indirection**: While basic optional types are handled, deeply nested pointer structures in Go may occasionally lead to false positives.
- **Performance Optimization**: The verifier currently re-parses Go source files for every Forge block. Implementing a caching layer for parsed Go ASTs would significantly improve performance in large-scale projects.
- **Function Type Limitations**: Complex function types, such as maps of functions, are difficult to represent in Forge and are often treated as `any`, which skips detailed comparison.
