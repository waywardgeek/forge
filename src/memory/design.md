# Memory Module Design

## Executive Summary

The `memory` module is a critical component of the Lyric compiler's middle-end, responsible for transforming the high-level, abstract memory model of the language into a concrete, efficient implementation. It performs a comprehensive memory management pass that runs after monomorphization and before the C backend emission.

The module's primary mission is to automate memory management while maintaining high performance. It achieves this through a combination of three key strategies:
1.  **Slab Allocation**: It rewrites class allocations to use a high-performance slab allocator, which provides pointer stability and reduced fragmentation compared to general-purpose `malloc`.
2.  **Reference Counting (RC)**: It injects explicit reference counting operations (`StRefIncr` and `StRefDecr`) for class handles, ensuring that objects are freed exactly when they are no longer reachable.
3.  **Escape Analysis and Scope-Exit Cleanup**: It performs escape analysis to identify locally-created slices and strings that do not escape their scope, allowing them to be safely deallocated at scope exit (e.g., via `StSliceFree`).

By the end of this pass, the program's Intermediate Representation (IR) is fully annotated with the low-level operations required for the C backend to generate code that adheres to Lyric's memory safety and performance guarantees.

## File Inventory

*   `[memory.ly](memory.ly)`: The sole source file for the module. It contains the entire logic for the memory management pass, including escape analysis, slab rewriting, reference counting injection, move semantics optimization, and scope-exit cleanup.

## Architecture and Data Flow

The `memory` module operates as a transformation pipeline on the `LProgram` structure, which represents the Low-level Intermediate Representation (LIR) of the entire program. The transformation is primarily orchestrated by the `slab_rewrite` function.

The data flow through the module follows these logical stages:

1.  **Escape Analysis**: The process begins with `compute_escape_map`, which performs a fixed-point iteration over all functions. It identifies which function parameters might cause slice or string data to "escape" (be stored in a long-lived structure like a class field). This information is crucial for deciding which local allocations can be safely cleaned up at the end of a block.
2.  **Class Infrastructure Preparation**: The module ensures that every non-permanent class has a `destroy` method. It also identifies "finalizer" functions (user-defined cleanup logic) and prepares to inject calls to them.
3.  **Function Body Rewriting**: The core of the module is the recursive traversal of function bodies. As it walks the IR, it performs several simultaneous transformations:
    *   **Allocation Rewriting**: High-level `ExClassAlloc` expressions are lowered into `ExSlabAlloc` (which performs the raw allocation) followed by a series of `StSlabSet` statements to initialize fields.
    *   **Reference Count Injection**: The module tracks the ownership of class handles. When a handle is copied, it injects a retain operation. When a handle variable goes out of scope or is reassigned, it injects a release operation.
    *   **Cleanup Injection**: At every scope exit (end of a block or a `return` statement), the module injects the necessary cleanup code for all tracked local variables, including slice frees and class handle releases.
4.  **Optimization Passes**: After the primary rewriting, the module performs post-processing to refine the generated code:
    *   **Temporary Release**: `insert_temp_releases` ensures that intermediate results from function calls (which return owned handles) are properly released after their last use if they weren't assigned to a named variable.
    *   **Delta Folding**: `delta_fold` identifies and removes redundant, adjacent retain/release pairs on the same object, reducing runtime overhead.

## Interface Implementations

The `memory` module does not implement external interfaces in the traditional sense. Instead, it acts as a consumer and transformer of the `LProgram` contract. It relies on the structural definitions of the LIR (such as `LStmt`, `LExpr`, `LType`, and `LValue`) to perform its analysis and mutations.

## Public API

The module exposes a focused API for use by the compiler orchestrator:

*   `func slab_rewrite(prog: LProgram)`: This is the primary "front door" to the module. It performs the complete memory management transformation on the provided program in-place.
*   `func compute_escape_map(prog: LProgram) -> Dict<Sym, bool>`: While primarily used internally, this function can be called to perform escape analysis independently, returning a mapping of escaping function parameters.

## Implementation Details

### Escape Analysis Algorithm
The escape analysis uses a fixed-point iteration to handle transitive escapes. In the first pass, it marks parameters that are directly stored into class or struct fields. In subsequent passes, it marks parameters that are passed as arguments to other functions at positions already known to escape. This continues until no new escapes are discovered. The analysis is used to determine if a local slice or string can be safely freed at the end of its scope.

### Slab Allocation Model
Lyric employs an "Array of Structures" (AoS) slab model. The `memory` module transforms class allocations into pointers into these stable slab blocks. This ensures that pointers to objects remain valid even as the slab grows, and it allows for extremely fast allocation and deallocation. The module also injects `StSlabFree` calls into the `destroy` methods of classes.

### Reference Counting and Move Semantics
The module implements a sophisticated reference counting system. To minimize the overhead of RC, it employs "move semantics." When the compiler detects that a variable is being assigned to another and will never be used again (it is "dead"), it transfers ownership of the reference without incrementing or decrementing the count. This is particularly effective for returning values from functions. The liveness analysis is performed by `count_var_uses` and `var_is_live_after`.

### Struct and Tuple RC
One of the more complex aspects of the module is handling reference counting for class handles embedded within value types like structs and tuples. The module generates recursive cleanup logic (`emit_struct_field_rc`) that traverses these structures to ensure all nested references are properly retained on copy and released on destruction.

### Slice RC
When a slice contains elements that are reference-counted (class handles or structs with RC fields), the module injects `StSliceRcRelease` before the `StSliceFree`. This ensures that all elements in the slice are properly released before the slice's backing array is deallocated.

### Temp Last-Use Release
Intermediate results from function calls that return owned class handles must be released if they are not assigned to a variable. The `insert_temp_releases` pass scans flat blocks to find the last use of such temporary IDs and injects `StRefDecr` immediately after.

### Delta Folding
The `delta_fold` optimization identifies and removes redundant, adjacent retain/release pairs on the same object. For example, if a variable is incremented and then immediately decremented, both operations are removed.

## Dependencies

The `memory` module is deeply integrated with the compiler's IR and the language's runtime:

*   **[LIR (Low-level Intermediate Representation)](../lir/design.md)**: The module is entirely defined in terms of the LIR structures. It depends on the stability and correctness of the monomorphization pass that precedes it.
*   **[Lyric Runtime](../../runtime/design.md)**: The low-level statements injected by this module (like `StSlabAlloc`, `StRefIncr`, `StRefDecr`, and `StSliceFree`) are direct precursors to calls into the Lyric runtime library (`lyric_runtime.h`). The memory module must remain in perfect sync with the runtime's ABI.

## Technical Debt and Future Work

*   **Granular Escape Analysis**: The current escape analysis is relatively coarse-grained. Future improvements could include more precise tracking of data flow to allow even more local allocations to be stack-allocated or scope-freed.
*   **Advanced Delta Folding**: The `delta_fold` optimization currently only looks at very local patterns. A more global data-flow analysis could identify and eliminate more distant redundant RC operations.
*   **Parallelism Safety**: The use of a global counter for generating internal temporary IDs (`_rc_temp_counter`) may need to be revisited if the compiler moves toward a more parallel architecture.
