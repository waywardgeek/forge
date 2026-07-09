# Lexer Module Design

## Executive Summary

The `lexer` module is the foundational component of the Lyric compiler pipeline, responsible for transforming raw source text into a stream of classified tokens. It is a stateful, linear scanner designed for high performance and precision. Every token produced by the lexer carries a detailed source span, enabling accurate error reporting and source mapping throughout the subsequent stages of the compiler. The lexer handles a variety of complex language features, including multiple string literal forms, f-string interpolation with escaped brace sentinels, and sophisticated line continuation rules that allow expressions to span multiple lines based on operator context and bracket nesting.

## File Inventory

- [lexer.ly](lexer.ly): The primary implementation of the Lyric lexer, written in Lyric. It defines the `TokenKind` enum, the `Token` class, and the `Lexer` state machine.
- [lexer.ly.lyric](lexer.ly.lyric): The formal model of the lexer, providing architectural invariants and detailed documentation of the lexer's behavior and constraints.

## Architecture and Data Flow

The lexer operates as a stateful scanner that walks the source text byte-by-byte. It maintains an internal pointer (`pos`) along with line and column tracking to generate source metadata. The core of the module is the `Lexer` class, which encapsulates the scanning state and provides the interface for token consumption.

The data flow is strictly unidirectional:
`Source String` → `Lexer.scan()` → `Token` → `Parser`

The [parser](../parser/design.md) drives the lexer by calling `next()` to consume tokens or `peek()` to look ahead. To support the parser's need for backtracking—essential for disambiguating constructs like struct literals from blocks—the lexer provides a `LexerState` mechanism. This allows the parser to save a snapshot of the lexer's position and internal counters and restore them if a speculative parse path fails.

## Interface Implementations

The `lexer` module does not implement any external interfaces defined in other packages. It serves as a standalone provider of the token stream and state management API consumed by the compiler frontend. It relies on the `Pos` and `Span` structures defined in [src/ast](../ast/design.md) for its source mapping metadata.

## Public API

The public interface of the lexer is centered on the `Lexer` class and its lifecycle methods:

- **Construction**: The `new_lexer(src_text: string, filename: Sym) -> Lexer` function initializes a new scanner. It populates a keyword lookup table and sets the initial source position.
- **Token Consumption**:
    - `Lexer.next() -> Token`: Consumes and returns the next token from the stream, updating the `last_kind` tracker for line continuation logic.
    - `Lexer.peek() -> Token`: Returns the next token without advancing the scanner's position.
- **State Management**:
    - `Lexer.save_state() -> LexerState`: Captures a value-type snapshot of the current position, line, column, bracket depth, and any peeked token.
    - `Lexer.restore_state(state: LexerState)`: Reverts the lexer to a previously saved state, ensuring that backtracking is side-effect free.
- **Metadata**: `Lexer.current_pos() -> Pos` provides the current source position, used by the parser when it needs to anchor errors or AST nodes to specific locations.

## Implementation Details

### Keyword Recognition
The lexer distinguishes between "hard" keywords and "contextual" keywords. Hard keywords, such as `func`, `class`, and `let`, are recognized via a high-performance `Dict<Sym, TokenKind>` lookup during identifier scanning. These are emitted as specific `TokenKind` variants. Contextual keywords, such as `field`, `lock`, and `implements`, are emitted as standard identifiers (`LIdent`). The parser is responsible for resolving these based on their grammatical position, allowing them to remain usable as ordinary identifiers in other contexts.

### Line Continuation and Newline Suppression
Lyric uses a newline-sensitive grammar where newlines typically terminate statements. To allow expressions to span multiple lines without explicit continuation characters, the lexer implements two suppression mechanisms:
1. **Bracket Nesting**: The `bracket_depth` counter tracks open `(` and `[` characters. While this depth is greater than zero, newline characters are consumed but not emitted as `SNewline` tokens. Note that curly braces `{}` do not affect `bracket_depth` as they delimit blocks.
2. **Operator Continuation**: If the last token consumed by the parser was a binary operator (e.g., `+`, `&&`, `->`, or a comma), the lexer suppresses the following newline. This is determined by the `is_binary_op` helper, which identifies operators that naturally expect a following expression.

Additionally, the lexer automatically collapses multiple consecutive newlines into a single `SNewline` token, simplifying the parser's job of handling statement boundaries.

### Literal Scanning
The lexer supports several distinct literal forms:
- **Standard Strings**: Double-quoted strings (`"..."`) supporting standard backslash escapes.
- **Triple-Quoted Strings**: Multi-line raw text blocks (`"""..."""`) where leading and trailing whitespace lines are automatically trimmed.
- **F-Strings**: Interpolated strings (`f"..."`). The lexer scans the raw content and encodes escaped braces `{{` and `}}` as sentinel bytes (`\x01` and `\x02`). This allows the parser to distinguish literal braces from interpolation boundaries (`{expr}`) during its own secondary scanning phase.
- **Backtick Symbols**: Backtick-enclosed identifiers (`` `name` ``) are lexed as `LBacktickSym`, which the parser typically desugars into symbol literals.
- **Character Literals**: Single-quoted characters (`'a'`) supporting escapes.
- **Numeric Literals**: Both integer and floating-point literals are supported, with underscores allowed as digit separators for readability.

### Comment Handling
Line comments (`//`) are scanned and collected into an `ArrayList` relation on the `Lexer` instance. They are not emitted as tokens in the stream, ensuring the parser receives a clean sequence of functional tokens while still allowing the comments to be preserved for tools like documentation generators or formatters.

### Token Splitting
The lexer does not perform contextual token splitting. For example, the sequence `>>` is always emitted as a single `OShr` (shift right) token. If the parser encounters this while expecting a closing `>` for a generic argument list (e.g., `List<List<i32>>`), it is the parser's responsibility to split the token and push the remainder back into the stream.

## Dependencies

- [src/ast](../ast/design.md): Provides the `Pos`, `Span`, and `Comment` types used for token metadata and comment collection.
- **Lyric Runtime**: The lexer relies on core runtime types including `Sym`, `Dict`, `StringBuilder`, and `ArrayList` for its internal state and lookup tables.

## Technical Debt and Future Work

- **Unicode Support**: The current bootstrap lexer is limited to ASCII. Full UTF-8 support is required for the production compiler to handle international characters in identifiers and strings.
- **Block Comments**: Support for `/* ... */` multi-line comments is defined in the formal model but is not yet implemented in the source code.
- **Error Recovery**: The lexer currently falls back to treating unknown characters as identifiers; introducing a dedicated `SError` token would allow for more robust error recovery in the parser.
- **Static Keyword Table**: The keyword dictionary is currently re-initialized for every lexer instance. This should be moved to a global constant once the language supports static initialization of complex types to improve performance.
