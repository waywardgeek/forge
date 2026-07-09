# Lyric Main Module Design

## Executive Summary

The `main` module serves as the primary entry point and orchestration hub for the Lyric compiler toolchain. It provides a unified command-line interface (CLI) that exposes the compiler's core capabilities, including source code compilation, automated testing, and design file formatting. The module is designed as a high-level driver that coordinates the complex, multi-stage transformation of Lyric source code into optimized C11 code.

By encapsulating the orchestration logic, the `main` module ensures that the compilation pipeline—spanning from lexical analysis and semantic checking to monomorphization and memory management—is executed in a strict, load-bearing order. It also provides essential diagnostic tools, such as Low-level Intermediate Representation (LIR) dumping, which are critical for debugging the internal state of the compiler during development.

## File Inventory

- [main.ly](main.ly): The primary implementation of the Lyric CLI. It contains the command resolution logic, the `compile_pipeline` orchestrator, and the implementation of the `compile`, `test`, and `fmt` subcommands.
- [main.ly.lyric](main.ly.lyric): A Context-Driven Development (CDD) design file that provides a formal specification of the module's architecture, function mappings, and the rationale behind its design.

## Architecture and Data Flow

The architecture of the `main` module is centered around a strictly ordered, unidirectional pipeline. It ingests raw source files and systematically lowers them through various representations until they reach the final C output. The module itself is a thin driver; it contains no top-level classes and relies on free functions to coordinate the work of specialized per-phase modules.

### Command Resolution and Dispatch
The module uses a unique-prefix matching algorithm in `resolve_command` to identify the user's intent. This allows for developer-friendly shortcuts (e.g., `lyric c` for `lyric compile`) while rejecting ambiguous inputs. If a prefix matches multiple commands (such as a hypothetical `compare` and `compile`), the module reports all possibilities and exits. Once a command is resolved, the `main` function dispatches it to the appropriate handler: `cmd_compile`, `cmd_test`, or `cmd_fmt`.

### The Compilation Pipeline
The `compile_pipeline` function is the heart of the module. It orchestrates the following phases in a sequence where each step depends on the validated output of the previous one:

1.  **Frontend**: Raw source text is parsed into an Abstract Syntax Tree (AST) using the [parser](../parser/design.md). Multiple files are then merged into a single program representation by the [ast](../ast/design.md) module.
2.  **Module and Stdlib Resolution**: The orchestrator handles `lyric.mod` files for module-mode compilation and selectively merges the standard library based on transitive usage.
3.  **Desugaring**: The [desugar](../desugar/design.md) module expands high-level language features—such as relations, interface embeddings, and default values—into simpler AST nodes.
4.  **Semantic Analysis**: The [checker](../checker/design.md) performs multi-phase type inference and symbol resolution, annotating the AST with resolved type information.
5.  **Lowering**: The annotated AST is translated into the Low-level Intermediate Representation (LIR) by the [lowerer](../lowerer/design.md).
6.  **Middle-end Optimizations**: The [optimizer](../optimizer/design.md) performs structural transformations and dead-code elimination on the LIR.
7.  **Monomorphization**: The [monomorphizer](../monomorphizer/design.md) specializes all generic types and functions into concrete instances, removing the need for runtime polymorphism.
8.  **Memory Management**: The [memory](../memory/design.md) module performs a critical "slab rewrite" pass. Depending on CLI flags, it injects logic for slab allocation, struct-of-arrays (SoA) layouts, and reference counting (RC) instrumentation.
9.  **Backend**: The final specialized LIR is emitted as C11 source code by the [c_backend](../c_backend/design.md), which is then written to the specified output file.

## Interface Implementations

The `main` module does not implement internal code interfaces. Instead, it defines and implements the **Command Line Interface (CLI)** contract for the entire Lyric toolchain. It acts as the "front door" that exposes the modular compiler logic to users, build systems, and automated test runners.

## Public API

The `main` module exposes its functionality through the following primary functions, which correspond to the CLI subcommands:

- **cmd_compile(args: [string]) -> bool**: Orchestrates the full compilation of one or more `.ly` files. It supports flags for output path (`-o`), LIR diagnostics (`--lir-dump`), and memory management tuning (`--soa`, `--detect-uaf`, `--rc-free`). It also handles "module mode" if a `lyric.mod` file is present in the input directory.
- **cmd_test(args: [string]) -> bool**: Executes the compilation pipeline and then scans the resulting LIR for functions named with a `test_` prefix. It generates a C test runner that uses `setjmp`/`longjmp` to isolate test failures, compiles it with a system C compiler (like GCC), and executes the tests in a temporary directory.
- **cmd_fmt(args: [string]) -> bool**: Provides a pretty-printing service for `.lyric` design files. It ensures that declarations are ordered by their original source line and that comments are preserved in their correct context.
- **resolve_command(prefix: string) -> (string, bool)**: Implements the unique-prefix matching logic used to map CLI arguments to internal command handlers.

## Implementation Details

### Unique Prefix Matching
The `resolve_command` function implements a robust matching algorithm that first checks for exact matches and then falls back to prefix matching. If a prefix is ambiguous, it reports all possible matches to the user, ensuring clarity and preventing accidental command execution. This is implemented by iterating over the list of valid commands and collecting all that start with the provided prefix.

### Test Discovery and Isolation
The `cmd_test` implementation is a sophisticated integration of the compiler and a runtime test harness. After the LIR is generated, the module performs a discovery pass to identify test functions (those starting with `test_` and having no receiver). The generated C runner is designed for isolation; each test is executed in a way that its failure (e.g., an assertion failure) does not terminate the entire test suite. This is achieved by wrapping test calls in a harness that uses `setjmp` to catch failures triggered by the runtime's error handling logic.

### LIR Diagnostic Dumping
For compiler developers, the `dump_lir_to_file` function provides a human-readable projection of the internal LIR state. It recursively traverses the LIR program, functions, statements, and expressions, producing a text format that clearly shows type annotations, temporary variable assignments, and control flow. This is an invaluable tool for verifying the correctness of the lowering and optimization passes. The dumper handles a wide variety of LIR nodes, including binary operations, calls, casts, and complex memory operations like slab allocations.

### Formatter Logic
The `fmt_file` logic is designed for "pedagogical stability" in `.lyric` files. It uses a `DeclItem` structure to track the original source line of every top-level declaration (imports, structs, enums, interfaces, classes, functions, relations, and type aliases). By sorting these items before emission, the formatter maintains the developer's intended grouping while enforcing a consistent internal style. The `emit_comments_before` helper ensures that source-level comments are not lost during the round-trip through the parser by using line number metadata to re-insert them at the correct locations.

## Dependencies

The `main` module is the primary consumer of the following internal modules:

- **[src/parser](../parser/design.md)**: For initial source ingestion and parsing.
- **[src/ast](../ast/design.md)**: For AST merging, module resolution, and standard library loading.
- **[src/desugar](../desugar/design.md)**: For language feature expansion.
- **[src/checker](../checker/design.md)**: For semantic validation and type annotation.
- **[src/lowerer](../lowerer/design.md)**: For AST-to-LIR translation.
- **[src/optimizer](../optimizer/design.md)**: For LIR simplification and dead-code elimination.
- **[src/monomorphizer](../monomorphizer/design.md)**: For generic specialization and implementation renaming.
- **[src/memory](../memory/design.md)**: For memory safety and allocation instrumentation (slab rewrite).
- **[src/c_backend](../c_backend/design.md)**: For final C code generation.
- **[src/lir](../lir/design.md)**: For the shared intermediate representation data structures used in diagnostics.

It also relies on the **[runtime](../../runtime/design.md)** for the `lyric_runtime.h` header used during the `test` command's C compilation phase.

## Technical Debt and Future Work

- **Incremental Compilation**: The current orchestration logic is designed for whole-program compilation. Future work includes introducing a module-level caching system to enable incremental builds, which would significantly improve developer velocity for large projects.
- **Formatter Expansion**: The formatter is currently specialized for `.lyric` files. Expanding its capabilities to handle full `.ly` source files with the same level of comment preservation and structural stability is a high priority.
- **Parallel Compilation**: The `compile_pipeline` is currently single-threaded. Parallelizing the parsing and checking of independent modules could significantly reduce build times on multi-core systems.
- **Improved Error Reporting**: While the module collects and reports errors from various phases, providing more contextual information (like "error during monomorphization of X") would improve the debugging experience for users.
