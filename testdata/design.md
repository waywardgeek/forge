# Testdata Module Design

## Executive Summary

The `testdata` module serves as the comprehensive validation suite and living specification for the Lyric programming language. It is not merely a collection of tests but a rigorous integration environment that exercises the entire compiler pipeline—from lexical analysis and parsing to semantic type checking, intermediate representation lowering, and final C code generation. The module consists of over 100 Lyric source files (`.ly`) that demonstrate and verify every feature of the language, including its unique relational ownership model, multi-class generic interfaces, and concurrency primitives.

These tests are the primary defense against regressions in the self-hosting compiler. By compiling these source files into C, executing them, and comparing their output against "golden" reference files, the project ensures that the language's semantics remain stable across iterations. Furthermore, the `testdata` module provides a rich set of pedagogical examples, showing how to implement complex data structures like graphs and trees using Lyric's advanced features.

## File Inventory

The following Lyric source files constitute the core of the test suite. Each file is designed to be a self-contained program that exercises specific language features:

*   [advanced.ly](advanced.ly): Tests advanced language features and complex interactions between various subsystems.
*   [any_type.ly](any_type.ly): Verifies the behavior, type checking, and runtime representation of the `any` type.
*   [arraylist.ly](arraylist.ly): Implements and tests a generic ArrayList data structure.
*   [as_cast.ly](as_cast.ly): Exercises the `as` operator for explicit type casting and conversion.
*   [calculator.ly](calculator.ly): A functional demonstration of a simple expression evaluator using recursive descent.
*   [channels.ly](channels.ly): Tests the core concurrency primitives, specifically synchronous and asynchronous channels.
*   [char_escape.ly](char_escape.ly): Verifies the handling of character escape sequences in strings and character literals.
*   [classes.ly](classes.ly): A comprehensive test for class definitions, methods, and generic class specialization.
*   [collections.ly](collections.ly): Exercises various built-in and user-defined collection types.
*   [concat.ly](concat.ly): Tests string and slice concatenation operations and their memory management.
*   [default_method_emit.ly](default_method_emit.ly): Verifies the generation and dispatch of default methods in interfaces.
*   [demo.ly](demo.ly): A general-purpose demonstration of multiple language features in a single program.
*   [destroy_shared.ly](destroy_shared.ly): Tests the destruction logic for shared and relational objects to ensure no memory leaks.
*   [dict.ly](dict.ly): Exercises the built-in dictionary type, including insertion, lookup, and deletion.
*   [dict_field_typeargs.ly](dict_field_typeargs.ly): Tests dictionaries used as class fields with complex type arguments.
*   [dict_literal.ly](dict_literal.ly): Verifies the syntax and initialization of dictionary literals.
*   [dict_multi_spec.ly](dict_multi_spec.ly): Tests dictionary specialization with multiple type parameters.
*   [dict_perf.ly](dict_perf.ly): A performance-oriented test for dictionary operations and hash collisions.
*   [dll_children_and_multirel.ly](dll_children_and_multirel.ly): Tests complex relational ownership in doubly-linked lists.
*   [empty_list_in_variant.ly](empty_list_in_variant.ly): Verifies the handling of empty lists within variant (union) types.
*   [enum_disambig.ly](enum_disambig.ly): Tests the disambiguation of enum members in various syntactic contexts.
*   [enum_fstring.ly](enum_fstring.ly): Exercises the use of enums within formatted strings.
*   [enums.ly](enums.ly): A basic test for enum definitions and pattern matching on enum variants.
*   [errors.ly](errors.ly): Verifies the language's error handling, `try` mechanics, and error propagation.
*   [features.ly](features.ly): A catch-all test for miscellaneous language features and edge cases.
*   [fstring.ly](fstring.ly): Tests the formatted string (`f"..."`) syntax and expression interpolation.
*   [generators.ly](generators.ly): Exercises the generator and iterator protocols, including `yield` semantics.
*   [generics.ly](generics.ly): A deep dive into generic functions, types, and constraint satisfaction.
*   [global_dict_rc.ly](global_dict_rc.ly): Tests reference counting for dictionaries stored in global variables.
*   [graph.ly](graph.ly): A complex test case implementing a graph data structure with multi-class relational ownership.
*   [guarded_by.ly](guarded_by.ly): Verifies the `guarded_by` annotation for ensuring thread-safe access to data.
*   [guards.ly](guards.ly): Tests pattern matching guards and conditional expressions within `match` blocks.
*   [hashed_list.ly](hashed_list.ly): A test for a list implementation backed by a hash table for O(1) lookups.
*   [hello.ly](hello.ly): A minimalist "Hello" program for basic toolchain verification.
*   [hello_world.ly](hello_world.ly): The canonical "Hello, World!" integration test.
*   [http_router.ly](http_router.ly): A demonstration of a simple HTTP request router using pattern matching.
*   [if_expr.ly](if_expr.ly): Tests `if` statements used as expressions (ternary-like behavior).
*   [if_let.ly](if_let.ly): Exercises the `if let` syntax for safe optional unwrapping.
*   [iface_mangle.ly](iface_mangle.ly): Verifies the name mangling of interface methods in the C backend to avoid collisions.
*   [inference.ly](inference.ly): Tests the compiler's type inference engine across complex expressions.
*   [interfaces.ly](interfaces.ly): A comprehensive test for interface definitions, implementations, and embedding.
*   [io_builtins.ly](io_builtins.ly): Exercises the built-in I/O functions like `print` and `println`.
*   [is_operator.ly](is_operator.ly): Tests the `is` operator for runtime type checking and pattern matching.
*   [lambdas.ly](lambdas.ly): Verifies the syntax, closure behavior, and type inference of lambda expressions.
*   [line_continuation.ly](line_continuation.ly): Tests the handling of multi-line statements and expressions.
*   [lock.ly](lock.ly): Exercises the built-in locking primitives and mutexes for thread synchronization.
*   [method_generator.ly](method_generator.ly): Tests methods that act as generators, yielding values over time.
*   [method_iface.ly](method_iface.ly): Verifies the interaction between methods and interface requirements.
*   [methods.ly](methods.ly): A general test for method declarations, calls, and receiver types.
*   [move_semantics.ly](move_semantics.ly): Exercises the language's move semantics and ownership transfers for non-copyable types.
*   [multi_relation.ly](multi_relation.ly): Tests objects that participate in multiple relational ownerships simultaneously.
*   [mut_params.ly](mut_params.ly): Verifies the behavior and safety of mutable function parameters.
*   [mut_ref.ly](mut_ref.ly): Tests mutable references (`&mut`) and their associated borrow checking rules.
*   [mut_slice.ly](mut_slice.ly): Exercises mutable slices and in-place modifications of slice elements.
*   [nested_match.ly](nested_match.ly): Tests nested pattern matching blocks and exhaustive checking.
*   [nested_try.ly](nested_try.ly): Verifies the behavior of nested `try` and `catch` blocks for error handling.
*   [null_byte.ly](null_byte.ly): Tests the handling of null bytes in strings and character literals.
*   [optional_ctor.ly](optional_ctor.ly): Exercises constructors that return optional types (`T?`).
*   [optional_struct_writeback.ly](optional_struct_writeback.ly): Verifies the write-back behavior of optional struct fields.
*   [optionals.ly](optionals.ly): A comprehensive test for the `T?` optional type and its operations.
*   [owning_list.ly](owning_list.ly): Tests a list implementation that owns its elements via relational links.
*   [positional_struct_lit.ly](positional_struct_lit.ly): Exercises positional initialization of struct literals.
*   [range_gen.ly](range_gen.ly): Tests the built-in range generator and its use in loops.
*   [ref_list.ly](ref_list.ly): A test for a list of references, verifying reference stability.
*   [select.ly](select.ly): Exercises the `select` statement for non-blocking multiplexing of channel operations.
*   [short_circuit.ly](short_circuit.ly): Verifies the short-circuiting behavior of boolean `and` and `or` operators.
*   [slab_test.ly](slab_test.ly): Tests the language's slab allocation features for high-performance memory management.
*   [slice_free.ly](slice_free.ly): Verifies the memory management and automatic freeing of slices.
*   [slice_methods.ly](slice_methods.ly): Exercises the built-in methods for slices, such as `len`, `append`, and `slice`.
*   [slice_rc.ly](slice_rc.ly): Tests reference counting for slices and their underlying buffers.
*   [spawn.ly](spawn.ly): Exercises the `spawn` keyword for creating new concurrent tasks.
*   [stdlib.ly](stdlib.ly): A test suite for the Lyric standard library components and their integration.
*   [string_builder.ly](string_builder.ly): Exercises a `StringBuilder` utility for efficient string construction.
*   [string_conv.ly](string_conv.ly): Tests string conversions between various primitive types.
*   [struct_copy_hooks.ly](struct_copy_hooks.ly): Verifies the behavior of custom copy hooks for structs.
*   [struct_lit.ly](struct_lit.ly): A basic test for struct literal syntax and field initialization.
*   [sym.ly](sym.ly): Exercises the `sym` (symbol) type for efficient string-like identifiers.
*   [test_char_predicates.ly](test_char_predicates.ly): Tests character predicate functions like `is_digit` and `is_alpha`.
*   [test_desugar.ly](test_desugar.ly): A regression test specifically targeting the compiler's desugaring phase.
*   [test_dict_len.ly](test_dict_len.ly): Verifies the `len` function and empty state for dictionaries.
*   [test_impl_type_arg_labels.ly](test_impl_type_arg_labels.ly): Tests type argument labels in interface implementations.
*   [test_lexer.ly](test_lexer.ly): A comprehensive test for the lexer, covering all token types and edge cases.
*   [test_min.ly](test_min.ly): A minimalist test case for basic compiler and runtime functionality.
*   [test_new_error.ly](test_new_error.ly): Verifies the creation and propagation of custom error types.
*   [test_owns_on_impl.ly](test_owns_on_impl.ly): Tests the `owns` relation on interface implementations.
*   [test_parser.ly](test_parser.ly): A comprehensive test for the parser, covering all grammar rules.
*   [test_phase3e_user_namespace.ly](test_phase3e_user_namespace.ly): Tests user-defined namespaces in the semantic analysis phase.
*   [test_return_in_main.ly](test_return_in_main.ly): Verifies the behavior of `return` statements within the `main` function.
*   [test_str_split_n.ly](test_str_split_n.ly): Tests the `split_n` method for strings with various limits.
*   [tree.ly](tree.ly): A complex test case implementing a tree data structure with relational ownership.
*   [trusted_rc.ly](trusted_rc.ly): Exercises "trusted" reference counting for performance-critical sections.
*   [try_loop.ly](try_loop.ly): Tests the use of `try` and `catch` within loops.
*   [try_operator.ly](try_operator.ly): Exercises the `?` operator for concise error propagation.
*   [tuple_match.ly](tuple_match.ly): Tests pattern matching on tuples and nested tuple structures.
*   [tuples.ly](tuples.ly): A basic test for tuple types, literals, and destructuring.
*   [typealias.ly](typealias.ly): Verifies the `typealias` keyword for creating type synonyms.
*   [unions.ly](unions.ly): Exercises union types and their associated pattern matching.
*   [unwrap_class.ly](unwrap_class.ly): Tests the unwrapping of classes from optionals or variants.
*   [user_constraint.ly](user_constraint.ly): Verifies user-defined type constraints in generic declarations.
*   [where_clause.ly](where_clause.ly): Tests the `where` clause for complex generic constraints.

## Subdirectories

The `testdata` module is organized to support both flat integration tests and more complex modular scenarios:

*   **[golden/](golden/)**: This directory contains the `.expected` reference files for every integration test. These files represent the "ground truth" for the standard output and error of the compiled Lyric programs. The test runner compares the actual output of a test execution against these files to determine success or failure.
*   **[import_dir/](import_dir/)**: A specialized workspace for testing the Lyric module system. It contains a sample multi-package project structure (including `lyric.mod`) used to verify cross-module imports, symbol visibility, and package resolution logic.
*   **[modules/](modules/)**: Contains legacy `.gk` files and other artifacts used for testing the Forge toolchain's module resolution and symbol export logic.

## Architecture and Data Flow

The architecture of the `testdata` module is centered around the "Golden File" testing pattern. Each `.ly` file is an independent, end-to-end test case that exercises the entire compiler and runtime stack. The module's structure is designed to be consumed by automated test runners like `test_lyric.sh` and `verify_golden.sh`.

The data flow for a test execution follows a strictly defined pipeline. First, the test runner selects a source file and invokes the `lyric` compiler. The compiler transforms the Lyric source into a C11 source file, exercising the lexer, parser, desugarer, type checker, and LIR generator. Next, a system C compiler (such as GCC) compiles the generated C code, linking it against the `lyric_runtime.h` header. The resulting binary is then executed in a controlled environment. Its standard output and standard error are captured and compared byte-for-byte against the corresponding `.expected` file in the `golden/` directory. If the outputs match, the test is marked as passed; otherwise, the differences are reported as a regression.

This architecture allows for rapid verification of complex compiler changes. If a change intentionally alters the language's behavior or the compiler's output format, the `generate_golden.sh` script can be used to update the reference files after manual verification of the new output.

## Interface Implementations

As a test suite, the `testdata` module does not implement internal code interfaces in the traditional sense. Instead, it serves as the primary consumer and validator of the interfaces defined by the Lyric language and its runtime. Every `.ly` file is a client of the Lyric language specification and the `lyric_runtime.h` ABI.

The module verifies several critical interface boundaries:
- **Compiler Frontend**: The parser and lexer must correctly handle the syntax demonstrated in the tests.
- **Semantic Analysis**: The type checker must correctly resolve symbols and enforce the rules exercised by the tests.
- **Runtime ABI**: The generated C code must correctly interface with the macros and functions provided by the runtime, such as slice manipulation and channel operations.
- **Standard Library**: The tests verify the behavior and stability of the core modules provided in the `stdlib/` directory.

## Public API

The "Public API" of the `testdata` module consists of the conventions and tools for adding, running, and maintaining tests.

### Adding a New Test
To add a new integration test, a developer creates a new `.ly` file in the `testdata/` directory. The file must contain a `func main()` entry point that exercises the desired functionality and prints its results to standard output. After creating the file, the developer runs `./generate_golden.sh testdata/my_test.ly` to create the initial reference file in the `golden/` directory.

### Running the Suite
The entire test suite can be executed using the root `Makefile` via the `make test` command. Individual tests can be run using the `./test_lyric.sh` script, which provides detailed output and allows for debugging specific failures.

## Implementation Details

The tests within the module are categorized into several functional groups to ensure comprehensive coverage:

### Feature Verification
These tests are designed to prove the correctness of specific language features. For example, `channels.ly` and `spawn.ly` verify the concurrency model, while `generics.ly` and `interfaces.ly` exercise the type system. These tests often serve as the first implementation of a feature during development.

### Regression and Edge Case Testing
Tests like `test_lexer.ly` and `test_parser.ly` are specifically designed to catch regressions in the compiler's internal phases. They contain exhaustive lists of tokens and grammar rules, as well as edge cases discovered during development, such as null bytes in strings or complex nested expressions.

### Complex Data Structures
Tests like `graph.ly` and `tree.ly` demonstrate the power of Lyric's relational ownership model. They implement complex, pointer-heavy data structures that would be difficult to manage safely in other systems languages, proving the viability of the language's core innovations.

### Error Handling and Safety
The `errors.ly` and `guarded_by.ly` tests verify that the language's safety guarantees are enforced both at compile-time and runtime. They ensure that errors are propagated correctly and that concurrent access to data is properly synchronized.

## Dependencies

The `testdata` module has a fundamental relationship with the core components of the Lyric project:

- **[lyric](../design.md)**: The tests depend on the `lyric` compiler to be translated into C.
- **[runtime](../runtime/design.md)**: The compiled tests depend on the `lyric_runtime.h` header for their execution environment.
- **[stdlib](../stdlib/design.md)**: Many tests import and use modules from the Lyric standard library to perform I/O and other common tasks.

The `lyric` compiler itself depends on the `testdata` module for its own verification, particularly during the self-hosting process where the compiler must successfully compile the entire test suite to be considered stable.

## Technical Debt and Future Work

- **Negative Testing**: The current suite primarily focuses on "positive" tests (code that should compile and run). Expanding the suite to include "negative" tests (code that should fail to compile with specific, helpful error messages) would significantly improve the compiler's diagnostic quality.
- **Performance Benchmarking**: While some tests like `dict_perf.ly` exist, a more formal benchmarking suite could be integrated into `testdata` to track the performance of the compiler and the generated code over time.
- **Parallel Execution**: As the number of tests grows, the time required to run the full suite increases. Implementing parallel test execution in the test runner would improve developer velocity.
- **Exhaustive Generic Testing**: Further testing of the interaction between generics, relational ownership, and interface embedding is needed to ensure that all edge cases in the monomorphization pass are covered.
