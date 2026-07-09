# Monomorphizer Module Design

## Executive Summary

The `monomorphizer` module is a critical component of the Lyric compiler's middle-end, responsible for transforming a generic program into a concrete one. Since the Lyric compiler targets C11—a language without native support for generics—the monomorphizer must specialize every generic function, class, and struct into one or more concrete versions based on the actual type arguments used throughout the program. This process, known as monomorphization, eliminates the need for runtime generic dispatch or boxing, enabling the generation of high-performance, specialized C code.

The module operates on the Low-level Intermediate Representation (LIR) and ensures that after its pass, no type variables remain in the program. It employs a multi-phase approach, including transitive discovery of instantiations and iterative specialization to a fixpoint, ensuring that even complex nested generics are fully resolved.

## File Inventory

*   [monomorphizer.ly](monomorphizer.ly): The core implementation of the monomorphization pass. It contains the logic for discovering generic instantiations, generating specialized copies of declarations through deep cloning and type substitution, and rewriting the entire program to use these specialized instances.
*   [monomorphizer.ly.lyric](monomorphizer.ly.lyric): The interface definition and architectural metadata for the module, specifying the phases of the monomorphization process and the invariants that must be maintained.

## Architecture and Data Flow

The monomorphizer is implemented as a series of transformations on the `LProgram` structure. It uses a `MonoPass` class to maintain the state required for tracking instances, managing name mangling, and guiding the specialization process. The transformation follows a strictly defined six-phase pipeline, followed by post-processing and validation.

### The Monomorphization Pipeline

The process begins with an indexing phase where all functions, classes, and structs are mapped by name to facilitate rapid lookup. The pipeline then proceeds as follows:

1.  **Phase 1: Discovery**: The pass traverses the entire program to identify every unique set of concrete type arguments. This includes walking class and struct field types (Phase 1a) and scanning all function bodies for calls, allocations, and casts (Phase 1b).
2.  **Phase 2: Iterative Specialization**: The module enters a fixpoint iteration loop. It generates specialized copies of generic declarations for each unique set of type arguments discovered. Because specializing one function might reveal new instantiations of other generic constructs (e.g., a generic list method calling a generic dictionary), this phase continues until no new instances are found.
3.  **Phase 3: Declaration Filtering**: Once the fixpoint is reached, the original generic declarations are removed from the program. They are replaced by the newly created specialized versions.
4.  **Phase 4: Call Site Rewriting**: The pass performs a comprehensive traversal of all function bodies to update call sites, method calls, and class allocations. These are updated to refer to the mangled names of the specialized instances, and their explicit type arguments are removed.
5.  **Phase 5: Signature and Field Type Update**: The types of function parameters, return values, and class/struct fields are updated. Any surviving type variables are replaced with their concrete bindings, and generic class/struct handles are updated to their mangled counterparts.
6.  **Phase 6: Class Name Resolution**: A final per-function pass applies each function's specific class rename map to resolve any remaining bare generic class names, ensuring that allocations and field accesses point to the correct monomorphized class.

## Interface Implementations

The `monomorphizer` module does not implement a specific external interface. Instead, it provides a functional API consumed by the compiler's orchestration logic. It acts as a mandatory transformation step between the [lowerer](../lowerer/design.md) and the [c_backend](../c_backend/design.md).

## Public API

The module exposes several primary functions for orchestrating the monomorphization process:

*   `monomorphize(prog: LProgram?)`: The main entry point that performs the complete six-phase transformation of the provided `LProgram`.
*   `rewrite_impl_renames(prog: LProgram?)`: A post-processing pass that updates method call names to align with interface implementation requirements in specialized classes. It expands interface-method rename keys to cover every monomorphized variant of the implementing type.
*   `validate_post_mono(prog: LProgram?)`: A critical diagnostic utility that performs a deep walk of the LIR to ensure that no generic type parameters or unresolved type variables remain. It panics if any violations are found, serving as a final invariant check before code generation.

## Implementation Details

### Name Mangling and Type Keys

To ensure that specialized instances have unique and deterministic names, the module employs a sophisticated mangling strategy. The `mangle_name` function combines the base name of a declaration with a serialized representation of its concrete type arguments. Type arguments are converted into C-compatible name fragments (e.g., `i32` remains `i32`, while a class `List` becomes `CList`). These fragments are joined to form a `type_key`, which serves as a stable lookup key in the instantiation dictionaries.

### Type Substitution and Deep Cloning

The specialization process relies on deep cloning of LIR structures combined with type substitution.
*   `subst_type`: Recursively traverses a type structure, replacing type variables with concrete types from a substitution dictionary.
*   `clone_stmts`, `clone_expr`, and `clone_value`: These functions create entirely new copies of LIR nodes. During cloning, they apply `subst_type` to all embedded type information, effectively "baking in" the concrete types for the specialization.

### State Management

The `MonoPass` class manages the complex state of the transformation using several specialized dictionaries:
*   **Instance Tracking**: Maps "name|typekey" composite keys to mangled names for functions, classes, and structs.
*   **Type Argument Storage**: Stores the concrete types associated with each instance to guide the specialization process.
*   **Rename Maps**: Tracks the mapping from generic names to specialized names, ensuring consistency across the program.

### Interface Method Rewriting

The monomorphizer handles the language's "Relations" and interface systems by rewriting method calls. During specialization, `rewrite_impl_method_calls` uses a function's relational constraints to pick the correct concrete method name for interface-dispatched calls. The global `rewrite_impl_renames` pass further ensures that these renames are applied consistently across all monomorphized variants.

## Dependencies

*   **[src/lir](../lir/design.md)**: The monomorphizer operates exclusively on the Low-level Intermediate Representation, depending on its data structures and type definitions.

## Technical Debt and Future Work

*   **Memory Efficiency**: The extensive deep cloning of LIR structures can be memory-intensive. Future versions could explore structural sharing for immutable nodes to reduce the memory footprint.
*   **Identifier Length**: Complex nested generics can lead to very long mangled identifiers. While deterministic, these could potentially hit limits in some C compilers or debuggers.
*   **Incremental Support**: The current pass is global. Supporting incremental monomorphization would require tracking dependencies between specializations and potentially caching results across compiler runs.
