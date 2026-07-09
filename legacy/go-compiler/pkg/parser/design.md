# Parser Module Design

## Executive Summary

The `parser` module is the frontend of the Forge toolchain, responsible for transforming raw Forge source code into a structured Abstract Syntax Tree (AST). It handles two distinct file types: `.forge` declaration files, which define the architectural structure and safety invariants of a module, and `.fg` implementation files, which contain the full logic, expressions, and statements.

The module employs a two-phase pipeline: a hand-written, stateful lexer that converts source text into a stream of tokens, followed by a hybrid parser. This parser uses recursive descent for top-level declarations and a Pratt parser (precedence climbing) for expressions. The design prioritizes precision in source mapping, robust error reporting, and the ability to handle the full complexity of the Forge language—including its recursive type system, pattern matching, and concurrency primitives—without external parser generators.

## File Inventory

- [lexer.go](lexer.go): Implements the `Lexer`, a stateful scanner that converts raw source text into a stream of `Token` objects. It handles line and column tracking, newline significance, bracket nesting, and complex literals like triple-quoted and interpolated f-strings.
- [parser.go](parser.go): Implements the core `Parser` using recursive descent for top-level Forge declarations (structs, classes, interfaces, etc.) and the recursive type system. It manages the overall parsing lifecycle and handles LL(1) ambiguities via state save/restore lookahead.
- [expr_parser.go](expr_parser.go): Extends the `Parser` with a Pratt parser for expressions and recursive descent for statements. It handles the implementation details of function bodies, including control flow, pattern matching, and concurrency constructs.
- [parser.forge](parser.forge): A Forge declaration file that describes the parser module itself. It serves as the primary architectural specification and a self-referential test case for the parser.
- [lexer_test.go](lexer_test.go): Unit tests for the lexer, covering tokenization of keywords, literals, and edge cases like string escapes and bracket nesting.
- [parser_test.go](parser_test.go): Unit tests for the declaration parser, verifying the correct construction of AST nodes for Forge blocks and top-level items.
- [expr_parser_test.go](expr_parser_test.go): Unit tests for expressions and statements, ensuring correct operator precedence and statement structure.

## Architecture and Data Flow

The parser operates as a linear, unidirectional pipeline that transforms raw text into a rich, annotated AST.

1.  **Lexical Analysis**: Raw source text is fed into the `Lexer`. The lexer scans characters and produces `Token` objects. It maintains internal state to track source positions and handle context-sensitive rules. A critical feature is the suppression of `TNewline` tokens when inside brackets (`()`, `[]`, `{}`), allowing for flexible multi-line expressions while maintaining newline significance for statement separation in other contexts.
2.  **Declaration Parsing**: The `Parser` consumes tokens from the lexer. For top-level constructs, it uses recursive descent. Each major Forge construct (e.g., `struct`, `class`, `func`, `relation`) has a dedicated parsing method. The parser is designed to be largely LL(1), but it uses state save/restore for trial parsing when encountering ambiguities.
3.  **Expression and Statement Parsing**: When the parser encounters a function body or an initializer, it switches to expression and statement parsing. Expressions are parsed using a Pratt parser, which efficiently handles 12 levels of operator precedence. Statements are parsed using recursive descent, dispatching to specific handlers for `let`, `if`, `for`, `while`, `match`, `spawn`, `select`, and `lock`.
4.  **AST Construction**: Throughout the process, the parser instantiates nodes defined in [pkg/ast](../ast/design.md). Every node is assigned a `Span` (start and end positions) for precise error reporting and downstream processing. The final output is an `ast.File` object, which serves as the input for the type checker.

## Interface Implementations

The `parser` module provides the primary entry points for the Forge frontend and implements standard Go interfaces for error handling.

- **`ParseError`**: Implements the standard Go `error` interface. It provides formatted error messages that include the filename, line number, column, and a snippet of the offending source line with a caret pointing to the error location.
- **`Parser`**: While not implementing a formal Go interface, the `Parser` acts as the concrete implementation of the "Parser" concept used by the Forge orchestrator. It is designed to be stateful and copyable, allowing for the lookahead patterns required by the Forge grammar.

## Public API

The module exposes a clean API for parsing Forge source code:

- **`ParseFile(source, filename string) (*ast.File, error)`**: The primary entry point. It creates a lexer and parser, processes the source, and returns the resulting AST or a `ParseError`.
- **`ParseString(source string) (*ast.File, error)`**: A convenience wrapper around `ParseFile` that uses `"<string>"` as the filename, primarily used for testing and small snippets.
- **`NewLexer(source, filename string) *Lexer`**: Creates a new lexer instance, allowing for manual tokenization or integration with other tools.
- **`Token` and `TokenKind`**: Exported types representing the lexical units of the language.
- **`ParseError`**: A struct containing detailed information about syntax errors, including the message, source span, and the offending source line.

## Implementation Details

### Lexical Analysis (Lexer)

The `Lexer` is a hand-written scanner optimized for Forge's specific requirements.

- **Newline Significance**: Forge uses newlines as statement separators. The lexer emits `TNewline` tokens but suppresses them when `bracketDepth > 0`. This allows developers to break long expressions across multiple lines without explicit continuation characters.
- **Contextual Keywords**: Many Forge keywords (like `why`, `doc`, `source`, `field`) are also common identifiers. The lexer identifies them, but the parser can treat them as identifiers in specific contexts (e.g., field names) using `expectIdentLike()`.
- **String Literals**: The lexer supports standard double-quoted strings, triple-quoted strings (`"""..."""`) for multi-line content, and interpolated f-strings (`f"text {expr}"`). F-strings are lexed as a single `TFStringLit`, and the parser later splits them into parts, recursively invoking the expression parser for the interpolated segments.
- **State Restoration**: The `Lexer` struct is designed to be easily copied. This allows the parser to save the lexer state, perform lookahead (trial parsing), and restore the state if the lookahead fails, which is essential for disambiguating complex grammar patterns.

### Declaration Parsing (Recursive Descent)

The core parser in `parser.go` handles the structural elements of Forge.

- **Forge Blocks**: It handles both explicit `forge Name { ... }` blocks and implicit blocks derived from the filename, allowing for flexible project organization.
- **Recursive Types**: The `parseTypeExpr` method handles Forge's rich type system, including sequences `[T]`, tuples `(T, U)`, maps `map[K]V`, optionals `T?`, unions `A | B`, and function types `T -> U`. It uses a "base type" approach to handle precedence (e.g., `?` and `|` are handled after the base type).
- **Token Splitting**: Nested generics like `Dict<Dict<V>>` produce `>>` which lexes as `TShr`. The parser splits this into two `TGt` tokens using a `pushed` token field, ensuring correct parsing of nested generic arguments.

### Expression and Statement Parsing (Pratt Parser)

`expr_parser.go` handles the implementation logic found in `.fg` files using a Pratt parser for expressions.

- **Precedence Climbing**: Expressions are parsed using 12 levels of precedence, from logical OR at the lowest level to postfix operators (field access, calls, indexing) at the highest. This avoids the need for a deeply nested recursive descent grammar for expressions.
- **Statement Dispatch**: `parseStmt` dispatches to specific methods for control flow and concurrency. It handles `let` (variable declaration and destructuring), `if`, `for`, `while`, `match`, `spawn`, `select`, and `lock`.
- **Pattern Matching**: The parser supports complex patterns in `match` arms and `let` statements, including identifiers, variants, literals, wildcards, and tuples.
- **Compound Assignment**: Operators like `+=` and `-=` are desugared directly in the parser into their binary equivalents (`x = x + y`), simplifying the AST for downstream stages.

### Disambiguation and Lookahead

The parser uses several strategies to resolve grammar ambiguities:

- **`noStructLit` Flag**: Conditions in `if`, `for`, `while`, and `match` suppress struct literal parsing via a `noStructLit` flag. This prevents the parser from misinterpreting the start of a block as a struct literal (e.g., in `if x { ... }`).
- **`exprDepth` Counter**: Resolves the ambiguity between `Ident {` as a struct literal vs. a variable followed by a block. Inside parentheses or brackets (`exprDepth > 0`), it is always treated as a struct literal. In statement context (`exprDepth == 0`), the parser uses `isStructLitAhead()` lookahead to check for named field patterns (`ident:`).
- **`isWhyAnnotation()`**: Distinguishes between a `why` annotation (`why: "string"`) and a field named `why` (`why: Type`) by looking ahead for a string literal.

## Dependencies

- [pkg/ast](../ast/design.md): The parser is tightly coupled with the AST definition, as it is responsible for instantiating all AST nodes and maintaining their invariants.

## Technical Debt and Future Work

- **Error Recovery**: The current parser is "fail-fast" and stops at the first error. Implementing synchronization (e.g., skipping to the next top-level declaration or the next `forge` block) would improve the developer experience in IDEs.
- **Multi-line Arrays**: Some constructs like `source: [...]` currently require single-line formatting due to parser limitations.
- **Expression Capture**: Annotations like `requires` and `ensures` currently capture raw text rather than fully parsed expressions, delaying validation until the type checking phase.
- **Lambda Union Types**: Due to the use of `parseBaseType` for lambda parameters (to avoid ambiguity with the closing `|`), union types in lambda parameters are currently not supported directly and require type aliases.
