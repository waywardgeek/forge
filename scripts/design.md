# Scripts Module Design

## Executive Summary

The `scripts` module serves as the utility belt for the Lyric project, providing automated tools that bridge the gap between the language implementation and its documentation. The primary mission of this module is to maintain the "pedagogical integrity" of the project by ensuring that every code example presented to users is technically accurate and compatible with the current state of the compiler. By automating the extraction and verification of code blocks from Markdown manuscripts, the module prevents documentation bit-rot and provides a continuous validation loop for the language's core concepts as they are taught in *The Lyric Book*.

## File Inventory

*   [verify_book_examples.py](verify_book_examples.py): The primary verification engine that extracts, transforms, and compiles Lyric code examples from Markdown documentation.

## Architecture and Data Flow

The architecture of the `scripts` module is centered around a linear processing pipeline implemented in the `verify_book_examples.py` tool. This pipeline begins with an extraction phase where the script parses a Markdown manuscript, typically `the-lyric-book.md`, to locate fenced code blocks tagged with the `lyric` language identifier. During this phase, the script maintains context by tracking chapter headings and line numbers, ensuring that any subsequent errors can be traced back to their exact location in the documentation.

Once extracted, each code example flows into a classification and transformation stage. The script evaluates the content of the example to determine its "compilability." Examples marked with explicit error indicators or those that are purely illustrative fragments are set aside. For snippets that represent partial logic, the script applies a series of heuristics to wrap them in a valid `func main()` entry point, effectively promoting a code fragment into a complete, compilable program.

The final stage of the pipeline is the verification phase. The script manages a temporary workspace where it writes the transformed Lyric code to disk. It then orchestrates a two-step compilation process: first invoking the `lyric` compiler to translate the source into C code, and then invoking the system's C compiler to produce a final executable. The results of these operations are aggregated into a comprehensive report, providing developers with immediate feedback on the health of the project's documentation.

## Interface Implementations

This module does not implement any internal Lyric interfaces defined in the core compiler or runtime. Instead, it acts as a consumer of the Lyric system's external command-line interface. It treats the `lyric` binary as a black-box component, relying on its exit codes and standard error output to determine the success or failure of the verification process.

## Public API

The `scripts` module is designed for command-line interaction rather than programmatic integration. Its primary entry point is the `verify_book_examples.py` script.

### verify_book_examples.py

This script is invoked from the terminal and accepts an optional path to a Markdown manuscript. If no path is provided, it defaults to a hardcoded location (`~/singularity/lyric-book/manuscript.md`), though in practice it is frequently used with the [the-lyric-book.md](../the-lyric-book.md) file found in the project root. The script's primary output is a detailed log of the verification process, culminating in a summary table that categorizes examples as complete programs, wrapped snippets, or skipped fragments. It adheres to standard Unix conventions by returning a non-zero exit code if any compilable example fails to build, making it suitable for use in automated CI/CD pipelines.

## Implementation Details

The core logic of the verification engine relies on sophisticated heuristics to handle the variety of code examples found in a technical book. The classification logic uses regular expressions to distinguish between "complete" programs (those already containing a `func main()`) and "snippets" (partial logic). It also identifies "fragments" which are intentionally broken or purely declarative and should not be compiled.

The snippet wrapping logic is particularly nuanced. It must decide whether to wrap the entire code block in a `main` function or to append a dummy `main` function to the end. It makes this decision by scanning for top-level declarations such as `struct`, `class`, or `func`. If such declarations are found, the script assumes the snippet contains definitions that must reside at the top level of a Lyric file, and it simply adds an empty `main` to satisfy the compiler's requirement for an entry point. If no such declarations are found, it treats the snippet as a sequence of statements and wraps them in a standard `func main() { ... }` block.

The compilation process itself is a coordinated effort between the Lyric compiler and `gcc`. The script ensures that the C compiler is provided with the correct include paths for the [runtime](../runtime/design.md) and linked against necessary system libraries like `math` and `pthread`. This ensures that the environment used for verification matches the intended execution environment for Lyric programs.

## Dependencies

The `scripts` module is a high-level consumer of several project components and external tools:

*   **Lyric Compiler**: The module depends on the `lyric` binary being present in the project root. It uses the `compile` subcommand to generate C source code.
*   **Lyric Runtime**: Successful compilation of the generated C code requires the headers and logic defined in the [runtime](../runtime/design.md) module.
*   **C Toolchain**: The module relies on `gcc` (or a compatible C11 compiler) to perform the final stage of the build process.
*   **Python 3**: The verification script is written in Python 3 and requires a standard interpreter environment.

## Technical Debt and Future Work

While the current implementation provides robust verification of compilation, it does not yet verify the *execution* of the resulting binaries. A significant future improvement would be the ability to run the compiled examples and verify their output against expected results, perhaps by embedding expected output in the Markdown comments.

Additionally, the current reliance on regex-based heuristics for wrapping and classification can be brittle. As the Lyric language grows in complexity, these heuristics may need to be replaced with a more formal parsing approach. There are also some hardcoded paths and environment-specific defaults in the script that should be generalized to make the tool more portable across different developer setups. Finally, as the manuscript grows, the sequential nature of the verification process may become a bottleneck, suggesting a need for parallel execution of the compilation tasks.
