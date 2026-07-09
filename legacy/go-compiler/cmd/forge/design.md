# Forge CLI Module Design

## Executive Summary

The `forge` module is the primary command-line interface for the Forge toolchain, serving as a unified entry point for both structural management and the compilation pipeline. It addresses the critical need for synchronizing formal architectural models (defined in `.forge` files) with their corresponding Go implementations, while also providing a robust path for compiling Forge source files (`.fg`) into optimized C code. By bridging the gap between Go's structural definitions and Forge's formal modeling environment, `forge` ensures that architectural specifications remain a living, verified part of the development lifecycle rather than static documentation.

The module orchestrates a complex set of tasks, from scaffolding new models and pretty-printing existing ones to performing deep semantic analysis and generating executable tests. It acts as the "front door" to the entire Forge ecosystem, coordinating the efforts of the parser, checker, verifier, and LIR modules to provide a seamless developer experience.

## File Inventory

- [main.go](main.go): The central dispatcher for the CLI, responsible for command-line argument parsing, environment discovery (such as locating the standard library and runtime), and orchestrating the high-level logic for all commands.
- [shared.go](shared.go): A collection of common utilities for Go source analysis, including logic for scanning packages, extracting function signatures, and generating the automated sections (index and dependencies) of `.forge` files.
- [fmt.go](fmt.go): Implements the `forge fmt` command, providing a comment-preserving pretty-printer that enforces a consistent style for the manual modeling zones of `.forge` files while maintaining the integrity of automated zones.
- [gen.go](gen.go): Implements the `forge gen` command, which automates the initial creation of `.forge` files by extracting exported symbols from Go packages and mapping them to their Forge equivalents.
- [update.go](update.go): Implements the `forge update` command, the most complex structural management tool, which synchronizes existing `.forge` files with Go source changes by merging new symbols and regenerating automated metadata.
- [update_test.go](update_test.go): Provides unit tests for the update logic, ensuring that nested source paths and function signatures are correctly indexed and preserved across updates.

## Architecture and Data Flow

The `forge` module is structured as a suite of specialized command handlers coordinated by a central dispatcher in `main.go`. The architecture maintains a clear separation between structural management (the "Forge-to-Go" bridge) and the compilation pipeline (the "Forge-to-C" path).

### Structural Management Flow
Commands like `gen`, `update`, and `fmt` focus on the lifecycle of `.forge` files. These files are architecturally divided into three distinct zones: a manual modeling zone where developers add formal specifications (like `why` strings and `pure` annotations), an auto-generated function index, and an auto-generated dependency list. The data flow for these commands typically involves parsing the existing `.forge` file using the internal `parser` package, analyzing the corresponding Go source code using the standard `go/ast` package, and then merging or formatting the results. The `update` command is particularly sophisticated; it must perform a non-destructive merge that adds new Go symbols to the manual modeling zone without disturbing existing developer-added metadata, while completely regenerating the automated zones to ensure they remain a faithful representation of the implementation.

### Compilation and Testing Flow
The compilation pipeline, invoked via `compile` or `test`, follows a strictly linear transformation path. It begins by parsing one or more Forge source files into a unified Abstract Syntax Tree (AST). This AST is then subjected to a series of desugaring passes that expand high-level language constructs—such as interface embedding, relational state injection, and destructor synthesis—into simpler, explicit forms. Following desugaring, the `checker` performs a multi-phase semantic validation to resolve types and enforce safety rules. The validated AST is then handed to the `lowerer`, which flattens nested expressions into a sequence of temporaries and produces the Low-level Intermediate Representation (LIR). The LIR undergoes optimization and monomorphization to resolve generics before being emitted as C11 source code. The `test` command extends this flow by discovering functions with a `test_` prefix, generating a C test runner, and invoking a system compiler (like `gcc`) to produce and execute a test binary.

## Interface Implementations

As a top-level orchestration module, `forge` primarily acts as a consumer of interfaces and data structures defined by its peer packages. It does not implement many internal interfaces itself but strictly adheres to the contracts defined by the underlying toolchain:

- It utilizes the `ast.File` structure as the primary medium for code representation across all parsing and transformation stages.
- It leverages the `checker.Checker` for semantic validation and type annotation of the Forge modeling language.
- It employs the `lir.Lowerer` to bridge the gap between the high-level AST and the low-level representation required for C code generation.
- It uses the `verifier.Verify` interface to perform structural integrity checks against Go source code.

## Public API

The "public API" of the `forge` module is its command-line interface, which provides a set of distinct operations for managing the Forge lifecycle:

- **Verification (`verify`)**: Checks `.forge` files against their Go implementations, reporting any discrepancies in types, signatures, or missing exports as errors or warnings.
- **Synchronization (`update`)**: Keeps `.forge` files in sync with Go source code. It can optionally prune stale declarations that no longer exist in the Go package, ensuring the model remains accurate.
- **Scaffolding (`gen`)**: Creates a baseline `.forge` file for a Go package, facilitating the start of the formal modeling process by extracting all exported types and functions.
- **Formatting (`fmt`)**: Enforces a consistent style for `.forge` files while preserving developer comments and the logical grouping of declarations.
- **Compilation (`compile`)**: Transforms Forge source files into C, supporting both single-file and module-based projects. It handles the full pipeline from parsing to code emission.
- **Testing (`test`)**: Provides an integrated workflow for compiling and running Forge-based unit tests, automating the generation of a test runner and the invocation of the system compiler.

## Implementation Details

### Go-to-Forge Type Mapping
The module implements a robust mapping between Go's type system and Forge's modeling language, located primarily in `shared.go`. Basic Go types (e.g., `int32`, `float64`) are mapped to their Forge equivalents (`i32`, `f64`). Go pointers are transformed into Forge's optional types (`T?`), while slices and maps are mapped to Forge's sequence and map constructs. This mapping is essential for the `gen` and `update` commands, ensuring that the structural headers accurately reflect the Go implementation.

### .Forge File Zone Management
To support both automated updates and manual modeling, `.forge` files are managed in three zones. Zone 1 contains the `forge` blocks where developers add formal specifications. Zone 2 is a function index providing a Go-syntax reference for all exported functions, including their source locations. Zone 3 lists internal package dependencies. The `update` command uses a `splitAtMarker` strategy to isolate Zone 1 for non-destructive updates while completely replacing Zones 2 and 3.

### Compilation Pipeline Orchestration
The compilation process is a multi-stage pipeline managed by `cmdCompile` and `cmdTest`. It involves merging multiple input files and the standard library into a single compilation unit. This unit passes through five desugaring stages: `DesugarInterfaceEmbeds`, `DesugarInterfaceFields`, `DesugarRelations`, `DesugarDestructors`, and `DesugarDefaultImpls`. Invariant checks are performed at critical boundaries (post-desugar, post-lower, and post-monomorphization) to ensure internal consistency. The pipeline also handles module resolution by looking for `forge.mod` files to determine project roots and resolve internal imports.

### Test Runner Generation
The `test` command implements a lightweight test discovery mechanism. It scans the generated LIR for top-level functions starting with the `test_` prefix that have no receiver. It then generates a C `main` function that invokes each of these tests in sequence, reporting success or failure. This allows developers to write unit tests directly in Forge and execute them within a C environment, complete with the necessary runtime headers.

## Dependencies

The `forge` module is the primary consumer of the Forge internal packages:

- [pkg/ast](../../pkg/ast/design.md): For AST definitions, merging logic, and desugaring passes.
- [pkg/parser](../../pkg/parser/design.md): For parsing `.fg` and `.forge` files.
- [pkg/checker](../../pkg/checker/design.md): For semantic analysis and type checking.
- [pkg/lir](../../pkg/lir/design.md): For intermediate representation, optimization, and C code generation.
- [pkg/verifier](../../pkg/verifier/design.md): For structural verification against Go source.

It also relies on the Go standard library's `go/ast` and `go/parser` for analyzing Go code, and `os/exec` for invoking the system C compiler (typically `gcc`).

## Technical Debt and Future Work

- **Incremental Compilation**: The current implementation recompiles the entire unit for every change. Future versions could benefit from a build cache or incremental compilation to improve performance on large projects.
- **Enhanced Error Reporting**: While functional, error reporting could be improved with better source snippets and colorized output to help developers quickly identify and fix modeling errors.
- **Advanced Go Type Extraction**: The current type mapping is relatively simple and may need to be expanded to handle more complex Go constructs or provide more fine-grained control over how Go types are represented in Forge.
- **C Compiler Portability**: The `test` command currently assumes `gcc` is available in the system path. Supporting other compilers or providing a more configurable compilation environment would improve portability.
