# Lyric Root Module Design

## Executive Summary

The `lyric` module, located at the project root, serves as the orchestration and bootstrap hub for the Lyric programming language toolchain. Lyric is a high-performance systems language that introduces a unique **Relations** system for ownership management, providing safety without the overhead of a garbage collector. The toolchain is fundamentally self-hosting: the compiler is written in Lyric and is capable of compiling its own source code into optimized C11.

The primary artifact of this module is [lyric.c](lyric.c), a monolithic C file (approximately 90,000 lines) that represents the canonical output of the self-hosted compiler. This file serves as the bootstrap mechanism, allowing the entire toolchain to be built from scratch using only a standard C compiler (like GCC or Clang) and the [lyric_runtime.h](runtime/design.md) header. The root module manages the "fixed-point" invariant, ensuring that the compiler remains deterministic and stable by requiring it to produce byte-for-byte identical C output when recompiling itself.

## File Inventory

### Core Toolchain Artifacts
- [lyric.c](lyric.c): The monolithic, self-hosted compiler output in C. It contains the entire compiler pipeline (lexer, parser, checker, LIR, monomorphizer, and C backend) and is the primary bootstrap artifact.
- [lyric](lyric): The compiled binary of the Lyric compiler, used for all compilation and testing tasks.
- [lyric.lyric](lyric.lyric): A Context-Driven Development (CDD) design file that captures the high-level architectural invariants, module maps, and the "why" behind the toolchain's design.
- [project-design.md](project-design.md): The global architectural synthesis for the entire Lyric project, providing context for how the root module interacts with the legacy Forge toolchain and the runtime.

### Build and Orchestration
- [Makefile](Makefile): The primary build orchestration file. It defines targets for building the compiler, running the test suite, and performing the self-hosting "fixed-point" verification.
- [build.sh](build.sh): A minimalist bootstrap script that compiles `lyric.c` into the `lyric` binary using a system C compiler, bypassing the need for `make` in restricted environments.
- [runly](runly): A developer convenience script that compiles and executes a Lyric source file in a single command.
- [runfg](runfg): A specialized script for running the compiler with specific diagnostic flags, often used for debugging the internal pipeline.

### Verification and Testing
- [test_lyric.sh](test_lyric.sh): The main integration test runner, which executes a battery of Lyric programs and verifies their output against expected results.
- [test_self_compile.sh](test_self_compile.sh): A critical verification script that automates the self-hosting loop to ensure the compiler can reproduce its own source code exactly.
- [test_cli.sh](test_cli.sh): A test suite dedicated to verifying the behavior and flags of the `lyric` command-line interface.
- [generate_golden.sh](generate_golden.sh): A utility for updating "golden" reference files used in regression testing.
- [verify_golden.sh](verify_golden.sh): A utility for comparing current compiler output against golden files to detect regressions.

### Documentation and Specification
- [the-lyric-book.md](the-lyric-book.md): The comprehensive language specification and pedagogical guide, serving as the definitive reference for Lyric's syntax and semantics.
- [README.md](README.md): The project's entry point, containing installation instructions, a quick-start guide, and a high-level feature overview.
- [ASSESSMENT.md](ASSESSMENT.md): A critical self-evaluation of the language's design, implementation status, and performance characteristics.
- [IDEAS.md](IDEAS.md): A collaborative space for brainstorming future language features, optimizations, and architectural shifts.
- [TODO.md](TODO.md) / [TODO](TODO): The active project roadmap and task tracking files.

### Examples and Tests
- [foo.ly](foo.ly): A simple "Hello World" style Lyric program demonstrating basic syntax (functions, variables, printing).
- [test_dict.ly](test_dict.ly): A test program for the dictionary implementation in Lyric, demonstrating generics (`dict_new<i32>`) and basic dictionary operations.

### Miscellaneous
- [slab_dev.sh](slab_dev.sh): A development utility for testing and benchmarking the language's slab allocation features.
- [LICENSE](LICENSE): The Apache 2.0 license governing the project.

## Architecture and Data Flow

The root module orchestrates the transformation of Lyric source code into executable binaries through a strictly layered, unidirectional pipeline. While the logic for each stage resides in the `src/` directory, the root module provides the environment and scripts to execute this pipeline. The data flow begins with the `lyric` binary ingesting `.ly` source files. This binary is itself a product of the pipeline, specifically the compiled version of the monolithic `lyric.c`.

The compilation process is a sequence of transformations that systematically lower the high-level Lyric source into low-level C code. It starts with lexical and syntactic analysis, where the source text is tokenized and parsed into an Abstract Syntax Tree (AST). This AST is then subjected to a desugaring phase that expands high-level constructs, most notably the **Relations** ownership system and interface embeddings, into simpler AST nodes such as explicit fields, methods, and destructors.

Following desugaring, the semantic heart of the compiler, the checker, performs multi-phase type inference and symbol resolution. It annotates the AST with resolved type information and enforces safety constraints, such as concurrency lock enforcement and exhaustive pattern matching. The annotated AST is then flattened into a Low-level Intermediate Representation (LIR). This LIR undergoes optimization passes to eliminate redundant temporaries and simplify control flow.

A critical step in the pipeline is monomorphization, where generic types and functions are specialized into concrete instances. This is essential for generating efficient C code without the overhead of runtime polymorphism. Finally, the C backend translates the specialized LIR into C11 code that targets the [Lyric runtime](runtime/design.md).

### The Self-Hosting Loop and Fixed-Point Invariant

The most critical architectural feature of the root module is the self-hosting loop. This loop ensures the compiler's integrity by requiring it to be its own first customer. The process is defined by the "fixed-point" requirement: if the compiler compiles its own source code (located in `src/`), the resulting C code must be byte-for-byte identical to the `lyric.c` file used to build the compiler itself. This guarantees that the compiler's logic is deterministic and that no regressions have been introduced into the core transformation logic. This invariant is enforced by the `test_self_compile.sh` script and the `make self-test` target.

## Interface Implementations

The root module does not implement internal code interfaces in the traditional sense; instead, it defines and implements the **Command Line Interface (CLI)** for the entire toolchain. It acts as the "front door" to the compiler's functionality, exposing the underlying modular logic to the user and the build system. The CLI is the primary contract between the developer and the compiler, providing commands for compilation, testing, and debugging.

## Public API

The `lyric` binary provides a unified CLI for all toolchain operations. The primary entry point is the `compile` command, which translates Lyric source code into C. It accepts one or more `.ly` files and produces a single `.c` output file. For example, `./lyric compile <input.ly> -o <output.c>` is the standard usage pattern.

In addition to compilation, the CLI includes a `test` command that executes the internal test suite. This suite includes both unit tests for individual compiler components and integration tests that verify the behavior of generated code. The CLI also supports a `help` command for discovering available flags and subcommands.

For developers, the CLI provides numerous diagnostic flags that allow for deep inspection of the compilation pipeline. Flags like `--dump-ast` and `--dump-lir` emit the state of the program at various stages, which is invaluable for debugging the compiler's internal logic. These flags expose the internal data structures (AST and LIR) in a human-readable format.

## Implementation Details

### Bootstrap Process
The bootstrap process is designed for maximum portability. By checking in the generated `lyric.c`, the project eliminates the "chicken-and-egg" problem of needing a Lyric compiler to build a Lyric compiler. A developer only needs a C11-compliant compiler and the `lyric_runtime.h` header to produce a working `lyric` binary. This design allows the toolchain to be easily ported to new platforms and environments.

### Monolithic C Output (`lyric.c`)
The `lyric.c` file is a massive, monolithic projection of the modular Lyric source code. It includes all necessary type definitions, the full compiler logic, and the standard library components required for the compiler to function. The structure of `lyric.c` follows the order of the compilation pipeline, starting with standard includes and the runtime contract, followed by forward declarations of all internal compiler data structures. Function implementations are emitted in a topological order that minimizes the need for forward function declarations, and the file concludes with the `main` entry point that handles CLI argument parsing.

### Invariant Management
The root module's scripts are responsible for enforcing the project's most important invariants. Beyond the fixed-point requirement, these scripts verify pointer stability (ensuring that AST annotations remain valid through the pipeline), monomorphization correctness (verifying that all generic instances are correctly specialized and named), and relational integrity (confirming that the desugaring of relations produces the correct ownership and lifetime logic).

## Dependencies

The root module integrates and depends on the following internal components:

- [src/ast](src/ast/design.md): The foundational data structures for the program representation.
- [src/lexer](src/lexer/design.md) & [src/parser](src/parser/design.md): The frontend stages that ingest source text.
- [src/desugar](src/desugar/design.md): The engine for expanding high-level language features.
- [src/checker](src/checker/design.md): The semantic heart of the compiler.
- [src/lowerer](src/lowerer/design.md): The stage that flattens the AST into LIR.
- [src/lir](src/lir/design.md): The intermediate representation and its associated optimizer.
- [src/monomorphizer](src/monomorphizer/design.md): The engine for specializing generics.
- [src/c_backend](src/c_backend/design.md): The final stage that emits C11 code.
- [runtime/](runtime/design.md): The header-only C runtime required by all compiled Lyric programs.
- [stdlib/](stdlib/design.md): The Lyric standard library, which is partially embedded into the compiler during the bootstrap process.

## Technical Debt and Future Work

- **Incremental Compilation**: The current toolchain requires a full re-compilation of the entire project for any change. Implementing incremental compilation at the module level is a high-priority goal to improve developer velocity.
- **Error Reporting UX**: While functional, the compiler's error messages could be enhanced with better source span highlighting and actionable suggestions.
- **LLVM Backend**: To achieve peak performance, a future LLVM-based backend is planned to complement the existing C backend.
- **Language Server (LSP)**: Providing an LSP implementation would enable modern IDE features like go-to-definition and real-time type checking, significantly improving the developer experience.
