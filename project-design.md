# Global Scout - Project Synthesis: Lyric

## Executive Summary

The Lyric project is a comprehensive, self-hosting toolchain for a novel systems programming language designed for high performance, safety, and expressiveness. At its core, Lyric introduces a unique "Relations" system for ownership management, distinguishing it from traditional manual memory management or garbage-collected languages. The project is centered around a self-hosted compiler that translates Lyric source code into highly optimized C11 code, which is then compiled by a standard C compiler into a final executable. 

The repository captures a fascinating evolutionary architecture. It contains the current, canonical self-hosted Lyric compiler at the project root, alongside a legacy Go-based compiler toolchain known as "Forge." The Forge toolchain likely served as the initial bootstrap mechanism and structural modeling environment before the language achieved self-hosting capabilities. Today, the project is defined by its strict "fixed-point" requirement: the self-hosted compiler must be capable of recompiling its own source code to produce a byte-for-byte identical C output in a fraction of a second. The ecosystem is rounded out by a lightweight, header-only C runtime and automated documentation verification scripts that ensure pedagogical integrity.

## System Architecture

The architecture of the Lyric toolchain is defined by a strictly layered, unidirectional transformation pipeline. The system is designed to ingest high-level, expressive source code and systematically strip away its complexity through a series of well-defined lowering phases until it reaches a flat, easily translatable intermediate representation.

The pipeline begins with lexical and syntactic analysis, where raw source text is converted into an Abstract Syntax Tree (AST). This AST is not a static data structure; it is immediately subjected to a sophisticated desugaring engine. This engine expands high-level constructs—such as multi-class interfaces and the unique relational ownership declarations—into simpler, lower-level AST forms. This early desugaring is a critical architectural choice, as it significantly reduces the complexity burden on subsequent semantic analysis and code generation stages.

Following desugaring, the semantic heart of the compiler takes over. The type checker performs a multi-phase analysis to resolve symbols, infer types, and enforce the language's strict safety rules, including concurrency lock enforcement and exhaustive pattern matching. The checker annotates the AST in-place, ensuring that every expression is bound to a resolved type.

The annotated AST is then lowered into a Low-level Intermediate Representation (LIR). The LIR is the defining architectural bridge of the system. It flattens all nested expressions into a sequence of Single Static Assignment (SSA)-like temporaries while preserving structured control flow (like loops and conditionals). This hybrid approach—flat expressions with structured control flow—is specifically tailored for emitting idiomatic and readable C code. The LIR undergoes optimization and a crucial monomorphization pass, which resolves all generic types and functions into concrete, specialized instances, completely removing the need for runtime generic dispatch. Finally, the C backend emits the specialized LIR as C11 source code, linking it against the lightweight Lyric runtime.

A parallel architectural narrative exists within the legacy Forge toolchain, which includes a unique "Verifier" module. This verifier acts as a structural integrity engine, performing deep, recursive comparisons between formal `.forge` modeling files and actual Go source code implementations to prevent architectural drift.

## Interface & Contract Map

The Lyric architecture relies on robust internal data structures that act as the primary interfaces and contracts between the various stages of the compilation pipeline.

The **Abstract Syntax Tree (AST)** is the foundational contract between the frontend and the middle-end. Produced by the parser, the AST is a rich, hierarchical representation of the source code. It is consumed by the desugarer, which mutates it into a simpler form, and then by the checker, which annotates it with type information. The AST relies heavily on pointer stability; because the checker annotates nodes in-place via pointers, downstream consumers must iterate over the AST without creating value-type copies to preserve these critical metadata links.

The **Checker Registry** serves as the global symbol table and type contract. It is populated during the early phases of semantic analysis and provides a unified view of all declared types, interfaces, and functions across the entire program. This registry is consumed by the lowerer to resolve cross-block references and ensure that the generated intermediate representation aligns with the validated semantic model.

The **Low-level Intermediate Representation (LIR)** is the strict contract between the middle-end and the backend. It guarantees that all high-level language sugar has been resolved, all generic types have been monomorphized into concrete instances, and all nested expressions have been flattened into temporary variables. The C backend consumes the LIR with the absolute assurance that it will not encounter complex nested logic or unresolved type variables.

The **Lyric Runtime (lyric_runtime.h)** provides the external C Application Binary Interface (ABI) contract. It defines the structural layout of core language primitives—such as dynamic slices, length-prefixed strings, optionals, and channels—as C macros and inline functions. The C backend emits code that strictly adheres to these runtime definitions, ensuring that the generated C code can seamlessly interact with the language's built-in memory management and concurrency primitives.

## Module Map

The project is organized into the canonical self-hosted compiler at the root, the legacy Go-based compiler in the `legacy/` directory, and supporting runtime and script utilities.

### Core Toolchain
*   **[lyric](design.md)**: The root module represents the complete, self-hosting Lyric toolchain. It contains the canonical C output of the compiler (`lyric.c`), the primary build system, and the orchestration logic for the entire compilation pipeline. It acts as the command-line interface for compiling Lyric source code into optimized C, managing the self-hosting loop, and running the integration test suite.
*   **[runtime](runtime/design.md)**: A header-only C library (`lyric_runtime.h`) that provides the foundational infrastructure for compiled Lyric programs. It implements core language features such as dynamic slices, length-prefixed strings, optionals, error results, and concurrency primitives (channels and spawning) using highly optimized C macros and inline functions.

### Legacy Go Compiler (Forge)
*   **[legacy/go-compiler/cmd/forge](legacy/go-compiler/cmd/forge/design.md)**: The primary command-line interface for the legacy Forge toolchain. It orchestrates the compilation pipeline, manages the automated synchronization of structural metadata (`.forge` files) with Go source code, and provides tools for formatting, scaffolding, and testing formal models.
*   **[legacy/go-compiler/pkg/parser](legacy/go-compiler/pkg/parser/design.md)**: The frontend of the legacy compiler. It features a hand-written, stateful lexer and a hybrid parser that uses recursive descent for top-level declarations and Pratt parsing (precedence climbing) for expressions. It is responsible for transforming raw source text into a structured AST while maintaining precise source mapping for error reporting.
*   **[legacy/go-compiler/pkg/ast](legacy/go-compiler/pkg/ast/design.md)**: Defines the Abstract Syntax Tree for the legacy compiler. Beyond simple data structures, it implements a sophisticated desugaring engine that flattens interface hierarchies, injects relational state fields, and synthesizes destructor logic. It also handles module resolution and the selective merging of standard library components.
*   **[legacy/go-compiler/pkg/checker](legacy/go-compiler/pkg/checker/design.md)**: The semantic heart of the legacy compiler. It performs comprehensive type checking, generic type inference, and semantic validation across a multi-phase process. It enforces the language's strict safety rules, including concurrency lock enforcement and exhaustive pattern matching, ultimately annotating the AST with resolved type information.
*   **[legacy/go-compiler/pkg/lir](legacy/go-compiler/pkg/lir/design.md)**: The Low-level Intermediate Representation module. It bridges the high-level AST and the C backend by flattening nested expressions into SSA-like temporaries while preserving structured control flow. It is responsible for lowering the AST, optimizing the resulting LIR, monomorphizing generic types into concrete instances, and finally emitting C11 source code.
*   **[legacy/go-compiler/pkg/verifier](legacy/go-compiler/pkg/verifier/design.md)**: A unique structural integrity engine. It performs deep, recursive comparisons between `.forge` understanding files and actual Go source code implementations to detect architectural drift. It bridges the Forge and Go type systems to ensure that the documented mental model remains perfectly synchronized with the codebase.

### Utilities
*   **[scripts](scripts/design.md)**: A collection of automated tools, primarily `verify_book_examples.py`, designed to maintain the pedagogical integrity of the project. It extracts Lyric code examples from Markdown documentation, applies heuristics to wrap snippets into compilable programs, and verifies them against the compiler to prevent documentation bit-rot.

## Integration Patterns & Workflows

The Lyric project relies on several complex, cross-module workflows to achieve its goals of self-hosting, structural verification, and documentation accuracy.

### The Compilation Pipeline Workflow
The journey from source code to executable binary is a highly orchestrated sequence of transformations. When a user invokes the compiler via the CLI, the orchestrator first directs the parser to scan and structure the source text into an Abstract Syntax Tree. This raw AST is immediately passed to the desugarer, which expands complex relational ownership models and interface embeddings into simpler, explicit fields and methods. The type checker then consumes this desugared AST, performing a multi-phase semantic analysis to resolve cross-file dependencies, infer generic types, and enforce concurrency locks, leaving behind a fully annotated AST. This annotated tree is handed to the lowerer, which flattens all nested expressions and translates the high-level constructs into the Low-level Intermediate Representation (LIR). The LIR undergoes a critical monomorphization pass to eliminate all generics by generating specialized, concrete versions of functions and classes. Finally, the C backend traverses this specialized LIR to emit optimized C11 code, which is then compiled by a system C compiler (like GCC or Clang) alongside the `lyric_runtime.h` header to produce the final executable.

### The Self-Hosting Loop
The most critical workflow in the project is the self-hosting loop, which ensures the compiler's stability and correctness. The compiler is written in Lyric and must compile itself. The process begins with a bootstrap phase, where a checked-in, canonical `lyric.c` file is compiled by a standard C compiler to produce the initial `lyric` binary. Developers then make changes to the Lyric source code. The existing `lyric` binary is used to compile this modified source, producing a new `lyric.c` file. To verify the integrity of the changes, this new `lyric.c` is compiled into a new binary, which is then used to compile the Lyric source code one more time. If the resulting C code is byte-for-byte identical to the previous iteration, the compiler has reached a "fixed-point." This strict invariant guarantees that the compiler's logic is deterministic and stable.

### The Structural Verification Workflow (Legacy)
Within the legacy Forge toolchain, the verifier module orchestrates a unique workflow to prevent architectural drift. When invoked, the verifier first parses a `.forge` formal modeling file to build a structural AST. It then reads the `source:` annotations within the file to locate the corresponding Go implementation files. Using the standard Go parser, it extracts the actual Go type information and aggregates it into a unified registry. The verifier then performs a deep, recursive walk of the Forge AST, comparing every declared struct, interface, and function against the aggregated Go types. It applies sophisticated name mapping and type normalization to bridge the two languages. Any discrepancies—such as missing fields, mismatched signatures, or undocumented Go exports—are reported as drift, ensuring the formal model and the implementation remain in perfect lockstep.

### The Documentation Verification Workflow
To ensure that the project's documentation remains accurate as the language evolves, the scripts module orchestrates an automated verification loop. The `verify_book_examples.py` script parses the Markdown manuscript of *The Lyric Book*, extracting all fenced Lyric code blocks. It evaluates each block, distinguishing between complete programs and partial snippets. For snippets, it applies heuristics to wrap the logic in a valid `func main()` entry point. The script then writes these transformed examples to a temporary workspace and invokes the Lyric compiler. It monitors the exit codes and standard error output to ensure that every pedagogical example successfully compiles into C code, providing immediate feedback on the health of the documentation.

## Dependency Overview

The dependency graph of the Lyric project is strictly hierarchical, reflecting its unidirectional data flow. At the very top sits the CLI orchestrator (either the root `lyric` binary or the legacy `forge` CLI), which acts as the primary consumer and coordinator of all underlying modules. 

The frontend modules—the parser and the AST—form the foundation of the pipeline. The parser depends heavily on the AST module to instantiate the nodes that represent the parsed source code. The AST module itself is designed as a low-level leaf package with minimal internal dependencies, ensuring its data structures can be safely consumed by the rest of the system.

The middle-end is dominated by the checker, which depends on both the AST and the parser. It consumes the AST to perform semantic analysis and relies on the parser to resolve imported module files during its multi-phase registration process. 

The backend is encapsulated by the LIR module, which depends on the AST for its input and the checker's registry for resolved type information. The LIR module is entirely responsible for the final stages of the pipeline, including lowering, optimization, monomorphization, and C code emission.

Finally, the generated C code has a strict, singular dependency on the `runtime` module. The `lyric_runtime.h` header provides the essential C macros and inline functions required to execute the compiled logic, acting as the final bridge between the Lyric language semantics and the host operating system.
