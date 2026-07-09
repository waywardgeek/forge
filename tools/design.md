# Tools Module Design

## Executive Summary

The `tools` module provides essential utility programs that support the Lyric ecosystem beyond the core compiler. Its primary component is `extract_api.ly`, a specialized tool designed to perform static analysis on Lyric source files to extract their public API. By transforming raw source code into a structured, machine-readable JSON format, this module enables a wide range of downstream applications, including automated documentation generation, IDE support (such as autocomplete and hover information), and structural verification tools that ensure architectural consistency across the project.

## File Inventory

*   **[extract_api.ly](extract_api.ly)**: The sole source file for the API extraction utility. It implements the logic for parsing Lyric files, traversing the resulting Abstract Syntax Tree (AST), resolving extension methods, and serializing the public interface into a comprehensive JSON manifest.

## Architecture and Data Flow

The `extract_api` utility is designed as a linear transformation pipeline that converts high-level Lyric declarations into a flat, queryable data structure. The process begins with **Input Acquisition**, where the tool consumes one or more source file paths from the command line. These files are read and passed to the core compiler's parser.

The **Parsing and Merging** phase utilizes the built-in `parse_file` function to generate an AST for each input. These individual trees are then unified into a single `File` node using `merge_files`, allowing the tool to treat multiple source files as a single logical module.

The core of the tool is the **Semantic Extraction** engine, which performs a two-pass traversal of the merged AST. In the first pass, it scans all function declarations to identify extension methods—functions that specify a `receiver_type`. These are indexed in a global dictionary for later association. In the second pass, the engine iterates through all top-level blocks, extracting definitions for structs, classes, interfaces, free functions, and enums.

Finally, the **JSON Serialization** phase converts these extracted entities into a string. Because Lyric's self-hosting environment may not yet have a full-featured JSON library, the tool implements its own robust emission logic using a `StringBuilder`. This includes specialized handling for escaping strings and a recursive formatter that translates complex internal type expressions into human-readable strings.

## Interface Implementations

As a standalone utility, this module does not implement interfaces defined elsewhere in the project. Instead, it acts as a high-level consumer of the core compiler's internal data structures. It relies on the stability of the AST nodes defined in the compiler's frontend and the behavior of the built-in parsing orchestration functions.

## Public API

The `extract_api` tool is a command-line utility invoked with a list of Lyric source files. It outputs a single, minified JSON object to standard output.

### JSON Schema

The output object follows a structured schema:
- **name**: The module name, derived from the first `lyric` block encountered.
- **structs**: A map where keys are struct or class names. Each value contains:
    - `fields`: A map of field names to their type strings.
    - `methods`: A map of method names to their function signatures.
    - `is_class`: A boolean flag indicating if the entity is a class.
    - `file` and `line`: Source metadata for the declaration.
- **interfaces**: A map of interface names to their method signatures and source metadata.
- **functions**: A map of free-standing functions (excluding extension methods) to their parameter lists and return types.
- **typedefs**: A map currently used to represent enums, providing an `underlying` string representation of the enum variants and their fields.

## Implementation Details

### Type Expression Formatting
The `type_expr_to_string` function is a critical recursive component that translates the compiler's internal `TypeExpr` representation into the syntax familiar to Lyric developers. It handles the full breadth of the Lyric type system, including named types with generics (e.g., `Map<String, Int>`), optionals (`T?`), sequences (`[T]`), tuples, function types, and advanced primitives like channels, generators, and union types.

### Extension Method Resolution
Lyric allows extension methods to be defined anywhere in a module, separate from the type they extend. To ensure these methods are correctly attributed in the JSON output, `extract_api` uses a dictionary-based caching strategy. During the initial AST walk, it maps receiver type names to their respective `FuncDecl` nodes. When the tool later emits the JSON for a struct or class, it performs a lookup in this dictionary to merge the extension methods into the entity's `methods` map.

### Manual JSON Construction
To maintain a zero-dependency footprint and ensure compatibility with the self-hosting compiler, the tool implements its own JSON emission logic. The `json_escape` function ensures that string literals, such as type names or file paths, are safely encoded by handling quotes, backslashes, and control characters like newlines and tabs. The use of `StringBuilder` ensures that the construction of large JSON manifests remains performant.

## Dependencies

The `tools` module is deeply integrated with the Lyric ecosystem:
- **Core Compiler**: It depends on the AST definitions and the parser entry points. While these are often built-in to the compiler binary, the logic corresponds to the structures found in the compiler's frontend.
    - **[src/ast](../src/ast/design.md)**: Provides the `File`, `FuncDecl`, `StructDecl`, and `TypeExpr` structures.
    - **[src/parser](../src/parser/design.md)**: Provides the `parse_file` entry point.
- **Standard Library**: The tool makes extensive use of the Lyric standard library for operating system interaction (`os_args`), file I/O (`read_file`), and core data structures (`StringBuilder`, `Dict`, `append`).
    - **[stdlib](../stdlib/design.md)**: The foundational Lyric library.

## Technical Debt and Future Work

- **Visibility Filtering**: The tool currently extracts all top-level declarations. Future iterations should implement strict filtering to only include entities marked with the `public` modifier.
- **Docstring Extraction**: To fully support documentation generation, the tool should be updated to extract and include comments or docstrings associated with declarations.
- **Standard JSON Library**: Once the Lyric standard library includes a native JSON encoding module, the manual emission logic should be replaced to improve maintainability and reduce code complexity.
