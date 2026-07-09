# Parser Module Design

## Executive Summary

The `parser` module is the syntactic heart of the Lyric compiler, responsible for transforming raw source text into a structured Abstract Syntax Tree (AST). It implements a hybrid parsing strategy: a hand-written recursive descent parser for top-level declarations and statements, and a Pratt parser (precedence climbing) for expressions. This dual approach allows the module to handle the LL(1) nature of Lyric's high-level structure while efficiently managing the complex operator precedence and associativity of its expression language. The parser is self-hosted, written in Lyric, and designed for high performance, deterministic output, and precise error reporting with full source span information.

## File Inventory

- [parser.ly](parser.ly): The primary entry point for the module. It defines the `Parser` class and implements the recursive descent logic for top-level declarations (classes, structs, enums, interfaces, relations, and impls) and file-level orchestration.
- [expr_parser.ly](expr_parser.ly): Implements the Pratt parsing engine for expressions and the recursive descent logic for statements (if, for, while, match, spawn, select, etc.) and patterns.
- [parser.ly.lyric](parser.ly.lyric): A metadata and specification file that defines the module's source files, architectural invariants, and design rationale. It serves as a formal bridge between the implementation and the compiler's structural verification tools.

## Architecture and Data Flow

The parser operates as a linear pipeline that ingests a stream of tokens and produces a hierarchical AST. It is initialized with a `Lexer` (from the `[lexer](../lexer/design.md)` module), which provides the token stream. The parser maintains a small, focused state, including the lexer reference, a single-token lookahead buffer (`pushed`), and contextual flags like `no_struct_lit` to resolve syntactic ambiguities.

The data flow follows a strictly defined path:
1.  **Initialization**: The `new_parser` function creates a `Parser` instance and its associated `Lexer`.
2.  **Top-Level Orchestration**: `do_parse_file` initiates the process, handling optional `lyric` block headers and deriving implicit module names from filenames when necessary.
3.  **Declaration Parsing**: The parser uses recursive descent to identify and parse high-level constructs. Each major declaration type (e.g., `parse_class`, `parse_func`) has a dedicated method in `parser.ly`.
4.  **Statement and Expression Dispatch**: When the parser encounters a block of code (e.g., a function body), it hands off control to the statement parser in `expr_parser.ly`. Statements that contain expressions (like `let` or `return`) further delegate to the Pratt parser.
5.  **AST Production**: The final output is an `ast.File` object (defined in the `[ast](../ast/design.md)` module), which contains the complete, structured representation of the source file, ready for desugaring and semantic analysis.

## Interface Implementations

The `parser` module serves as the primary implementation of the compiler's frontend contract. While Lyric's interface system is structural and implicit, the parser effectively implements the "Source-to-AST" transformation interface required by the compiler's main orchestration logic. It consumes the `Token` interface from the `lexer` module and produces the `Node` hierarchy defined by the `ast` module.

## Public API

The parser's public interface is designed for simplicity and ease of integration into the compiler pipeline.

- `new_parser(src_text: string, filename: string) -> Parser`: Initializes a new parser instance with a lexer for the given source text and filename.
- `parse_file(src_text: string, filename: string) -> (File?, error)`: A high-level convenience function that performs a complete parse of a source file and returns the root `File` AST node.
- `Parser.do_parse_file(self) -> (File?, error)`: The core entry point for parsing a full file, handling both explicit and implicit module blocks.
- `Parser.parse_expr(self) -> (Expr?, error)`: Allows for the isolated parsing of a single Lyric expression, useful for sub-parsers or tool integration.
- `Parser.peek(self) -> Token`: Returns the next token in the stream without consuming it, utilizing the internal `pushed` buffer if available.
- `Parser.next(self) -> Token`: Consumes and returns the next token in the stream.
- `Parser.expect(self, kind: TokenKind) -> (Token?, error)`: Asserts that the next token is of a specific kind, consuming it and returning an error if the assertion fails.
- `Parser.expect_ident(self) -> (Token?, error)`: A specialized version of `expect` that handles identifiers and allows certain contextual keywords to be treated as identifiers.


## Implementation Details

The `parser` module's implementation is characterized by its handling of complex language features and syntactic ambiguities through specific architectural choices.

### Hybrid Parsing Strategy
The division between `parser.ly` and `expr_parser.ly` reflects the language's grammar. Top-level declarations are handled via recursive descent, which is natural for the LL(1) structure of modules, classes, and functions. For expressions, the Pratt parser in `expr_parser.ly` uses a precedence-climbing algorithm with 12 distinct levels (from `PREC_OR` to `PREC_POSTFIX`). This approach avoids the deep recursion of traditional descent and makes the addition of new operators straightforward. Postfix operations, such as field access (`.`), method calls, and indexing (`[]`), are handled in a tight loop within `parse_postfix_expr` to ensure high performance.

### Resolving Struct Literal Ambiguity
A significant challenge in Lyric's grammar is the ambiguity of the `Ident {` sequence, which could represent a struct literal or a variable followed by a block (e.g., in an `if` statement). The parser resolves this using a `no_struct_lit` flag, similar to the approach taken by Rust. When parsing condition expressions for `if`, `while`, `for`, or `match`, the flag is set to true, instructing the expression parser to ignore potential struct literals. This forces developers to use parentheses if they truly intend to use a struct literal in a condition, e.g., `if (Point { x: 0, y: 0 }).is_origin() { ... }`.

### Lookahead and State Restoration
For constructs that are not strictly LL(1), the parser employs a "trial parse" strategy. It saves the entire state of the `Lexer` using `lex.save_state()`, attempts to parse a specific construct, and restores the state if the attempt fails. This is used for:
- **Generic Call Disambiguation**: Distinguishing between a comparison (`a < b`) and a generic call (`func<T>(args)`).
- **Struct Literal Detection**: Peeking ahead to see if a `{` is followed by field-like patterns.
- **Paren-Lambda Detection**: Determining if a parenthesized list is the start of a lambda expression (`(a: i32) -> ...`).

### F-String Sub-Parsing
Lyric supports interpolated strings (f-strings). The parser handles these by splitting the raw string token into literal segments and expression segments. For each expression segment (enclosed in `{}`), the parser instantiates a *new* sub-parser to process the Lyric expression within the braces. This recursive design allows for arbitrary nesting of expressions and even nested f-strings.

### Advanced Language Constructs
The parser includes specialized logic for Lyric's unique features:
- **Relations**: The `parse_relation` method handles the complex syntax for ownership relations, including hints, parent/child sides, and `owns`/`refs` annotations.
- **Multi-Class Interfaces**: The `parse_impl` method supports per-type-variable labels (e.g., `impl Iface<T: label>`) and ownership-bearing impls (`impl Iface owns for ConcreteType`).
- **Pattern Matching**: The `parse_pattern` method handles a wide range of patterns, including wildcards, literals, identifiers, and variant patterns with bindings.

## Dependencies

The `parser` module is a foundational component with a strictly hierarchical dependency profile:

- `[src/lexer](../lexer/design.md)`: Provides the `Lexer` and `Token` stream. The parser relies on the lexer's state-saving capabilities for lookahead.
- `[src/ast](../ast/design.md)`: Defines the target data structures for the parser's output. The parser is responsible for instantiating and populating these nodes.
- `stdlib`: Utilizes standard library features for string manipulation, symbol management (`sym`), and error reporting.

## Technical Debt and Future Work

- **Error Recovery**: The current implementation is largely "fail-fast." Implementing a "panic mode" recovery strategy (skipping to the next semicolon or brace) would allow the parser to report multiple errors in a single pass, improving the developer experience.
- **Incremental Parsing**: To support high-performance IDE features, the parser could be adapted to re-parse only modified blocks rather than entire files.
- **Formal Grammar**: While the `parser.ly.lyric` file provides some formal invariants, a complete EBNF or PEG specification would serve as a valuable reference for the language's evolution and for building alternative tools.
- **Performance Optimization**: Further optimization of token buffering and AST node allocation could yield performance gains, particularly for very large source files.
