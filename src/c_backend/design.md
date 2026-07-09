# C Backend Module

## Executive Summary

The `c_backend` module is the final stage of the Lyric compiler pipeline. It is responsible for translating a monomorphized Low-level Intermediate Representation (LIR) program into optimized, human-readable C11 source code. This module bridges the high-level semantics of the Lyric language—including relational ownership, concurrency primitives, and generators—with the low-level execution environment provided by a standard C compiler and the lightweight Lyric runtime.

The backend operates on the "fixed-point" principle: it must produce deterministic C output that, when compiled and run, can reproduce itself. It handles complex transformations such as lowering generators into state machines, hoisting lambdas into top-level functions, and implementing a sophisticated slab allocator for memory management.

## File Inventory

*   [c_backend.ly](c_backend.ly): The primary implementation of the C code generator. It contains the `CGen` class and the logic for emitting C code from LIR constructs.
*   [c_backend.ly.lyric](c_backend.ly.lyric): Metadata and architectural documentation for the module, defining invariants and the structure of the `CGen` state.

## Architecture and Data Flow

The `c_backend` module follows a strictly linear emission process orchestrated by the `CGen` class. The entry point is the `emit_c` function, which accepts a monomorphized `LProgram` and returns a single string containing the complete C source code.

### The CGen State Machine

The `CGen` class maintains the global state of the emission process. It tracks:
*   **Type Registries**: Dictionaries that map Lyric composite types (slices, optionals, results, channels, and tuples) to their generated C names. This ensures that each unique type is defined only once in the output.
*   **Symbol Lookups**: Maps for interfaces, classes, structs, and functions to facilitate vtable generation and method dispatch.
*   **Emission Buffers**: A primary `StringBuilder` for the main program and temporary buffers for hoisted constructs like lambdas and spawn functions.
*   **Contextual State**: Flags and counters for indentation, unique ID generation (for lambdas, spawns, and selects), and generator state tracking.

### Emission Order

To ensure dependency-safe C code that avoids "incomplete type" errors, the module adheres to a specific emission sequence:
1.  **Forward Declarations**: All structs, classes, and enums are declared first.
2.  **Composite Type Definitions**: Slices and channels are defined (as they are pointer-based and can precede full struct definitions).
3.  **Struct Definitions**: Topologically sorted to ensure that nested structs are defined before their containers.
4.  **Optional and Result Definitions**: Defined after structs but before classes, as they may wrap structs.
5.  **Class Definitions**: Includes the slab allocator infrastructure (AoS or SoA mode).
6.  **Interface Infrastructure**: Vtable structures and static vtable instances for every class implementation.
7.  **Function Forward Declarations**: All functions are declared to allow mutual recursion.
8.  **Function Bodies**: The actual implementation of functions, including hoisted lambdas and spawn blocks.

## Interface Implementations

While the `c_backend` does not implement a formal Lyric interface, it fulfills the implicit contract of the compiler's backend: it consumes the `LProgram` produced by the [LIR](../lir/design.md) module and produces a valid C11 program that links against `lyric_runtime.h`.

## Public API

The primary public interface is a single function:

*   `pub func emit_c(prog: LProgram?) -> string`: Transforms a monomorphized LIR program into a C11 source string.
*   `pub func emit_test_runner(test_funcs: [string]) -> string`: Generates a C `main` function that orchestrates the execution of a suite of test functions.

## Implementation Details

### Type Mapping

The `c_type` method is the central authority for mapping Lyric types to C.
*   **Primitives**: Mapped to standard `stdint.h` types (e.g., `TyI32` → `int32_t`).
*   **Class Handles**: Emitted as pointers to structs (AoS) or `uint32_t` handles (SoA).
*   **Optionals**: Class handle optionals are optimized as raw pointers where `NULL` (or `0` in SoA) represents `none`. Non-class optionals are emitted as tagged structs (`LyricOpt<T>`).
*   **Tuples**: Emitted as named structs (e.g., `LyricTuple_0`) with fields named `_0`, `_1`, etc.
*   **Generators**: Reaching `c_type` with a `TyGenerator` is an invariant violation; generators must be handled by specific emitters that derive the proper `{base}_gen_t*` type.

### Memory Management: The Slab Allocator

The backend supports two modes for class memory management:
*   **Array of Structures (AoS)**: Each class is a C struct. Allocation uses a block-based slab allocator with a free-list (`lyric_next` pointer).
*   **Structure of Arrays (SoA)**: Fields are stored in parallel arrays. Handles are `uint32_t` indices into these arrays. This mode is often used for performance and cache locality.

### Reference Counting

Reference counting (RC) is implemented for non-permanent, non-owned classes.
*   `StRefIncr` and `StRefDecr` statements emit the corresponding increment/decrement logic.
*   When a reference count hits zero, the generated `{ClassName}_destroy` function is called.
*   **UAF Detection**: If enabled, freeing a class sets its RC to `UINT32_MAX`, and subsequent accesses trigger a panic.

### Generator Lowering

Generators are transformed into state machines using a technique similar to Duff's Device.
*   A `{base}_gen_t` struct is generated to hold the generator's state, including local variables and the current execution point (`_state`).
*   The generator body is emitted as a `switch` statement that jumps to the appropriate label based on `_state`.
*   `yield` statements save the state and return `true`; the next call to the generator's `next` function resumes from the saved state.

### Concurrency and Spawning

*   **Spawn**: The `StSpawn` statement hoists the spawned block into a top-level function. A context struct is generated to pass captured variables by pointer.
*   **Channels**: Channel operations (`send`, `receive`, `select`) are mapped to runtime calls (`lyric_chan_send_*`, etc.).
*   **Select**: Implemented as a polling loop that tries each case and sleeps briefly if no case is ready.

### Interface Dispatch

Interfaces are implemented using vtables. Each interface has a vtable struct containing function pointers. Each class that implements an interface has a static vtable instance. Interface values are emitted as structs containing a `void* _data` pointer and a pointer to the vtable.

## Dependencies

*   **[LIR](../lir/design.md)**: The module depends heavily on the LIR data structures (`LProgram`, `LStmt`, `LExpr`, etc.) defined in the `lir` module.
*   **[Runtime](../../runtime/design.md)**: The generated C code has a hard dependency on `lyric_runtime.h`, which provides the implementation for strings, slices, channels, and the slab allocator base.

## Technical Debt and Future Work

*   **Map Support**: Maps are currently stubs in the C backend and are not yet supported.
*   **Slice RC Retain**: Explicit slice RC retention is currently a no-op; slices rely on scope-exit freeing.
*   **Optimization**: Further optimizations for SoA mode and vtable dispatch could be explored.
