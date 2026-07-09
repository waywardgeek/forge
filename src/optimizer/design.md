# Optimizer Module Design

## Executive Summary

The `optimizer` module provides a post-lowering LIR→LIR optimization pass for the Lyric compiler. It simplifies the Low-level Intermediate Representation (LIR) by performing structural transformations and dead-code elimination. Its primary goal is to bridge the gap between the high-level constructs emitted by the `lowerer` and the efficient, idiomatic C code expected by the `c_backend`. It handles tasks like fusing side-effecting expressions, destructuring multi-return values, and eliminating unused temporaries while ensuring that program semantics—especially side effects and process termination—are strictly preserved.

## File Inventory

*   [optimizer.ly](optimizer.ly): The primary implementation of the LIR optimizer, containing the transformation passes, liveness analysis logic, and the recursive descent engine for traversing the LIR tree.
*   [optimizer.ly.lyric](optimizer.ly.lyric): Structural metadata and architectural invariants for the optimizer module, providing the formal model and safety contracts for the implementation.

## Architecture and Data Flow

The optimizer operates on an `LProgram` (defined in `[src/lir](../lir/design.md)`). It iterates through every function declaration (`LFuncDecl`) and applies a sequence of transformation passes to the function body, which consists of a list of `LStmt` nodes.

The optimization pipeline follows a strict "Transform Before Eliminate" invariant. Structural transforms must run to completion before elimination begins, as elimination operates on the rewritten statements and relies on accurate liveness information derived from the final structure.

### The Optimization Pipeline

1.  **Structural Transforms**: These passes rewrite the LIR into a more canonical form. They run in a specific order:
    *   `fuse_side_effect_temps`: Collapses void-context calls bound to throwaway temporaries into bare `StSideEffect` statements.
    *   `destructure_multi_return`: Splits single-temporary multi-return calls into `MultiAssign` statements so downstream stages see explicit names.
    *   `destructure_extract_pairs`: Rewrites `ExtractValue`/`ExtractError` patterns (emitted by the `lowerer` for the `try` operator) into direct field reads on the tuple temporary.
    *   `fix_nil_zero_values`: Replaces `nil` initializers with the proper zero value for value types (e.g., `0` for integers, `false` for booleans) to ensure the backend never encounters a `null` for a non-nullable type.

2.  **Liveness Analysis**: The optimizer walks the transformed statements to build live-set dictionaries for both temporaries and variables. This walk is exhaustive and recursive, visiting every variant of statement, expression, and value.

3.  **Elimination Phase**:
    *   `eliminate_unused_temps_recursive`: Drops `StTempDef` and `StVarDecl` nodes whose identifiers are never read. If the expression being assigned has side effects, it is preserved as an `StSideEffect` statement; otherwise, it is dropped entirely.
    *   `blank_unused_multi_assign_names`: Replaces unused names inside multi-assignment LHSs with `_`, allowing the backend to elide unnecessary stores.

## Interface Implementations

This module does not implement any formal interfaces. It provides a standalone optimization service consumed by the compiler orchestrator.

## Public API

The optimizer exposes a simple procedural API for transforming LIR programs:

*   `func optimize(prog: LProgram)`: The main entry point. It mutates the provided `LProgram` in-place, optimizing the bodies of all functions and methods.
*   `func optimize_func(mut fn: LFuncDecl)`: Performs the full optimization pipeline on a single function declaration.

## Implementation Details

### Side-Effect Safety

The `is_side_effect_expr` function is the single source of truth for which expressions must survive elimination. It whitelists three categories of operations:
1.  **I/O and Mutating Container Ops**: Operations like `append`, `push`, `sort`, and channel communications.
2.  **Diagnostic Builtins**: `println`, `assert`, `panic`, etc.
3.  **Process Termination**: `os_exit`, `exit`, and `abort`. These are critical; if they were eliminated because their return value was unused, a panic site could silently turn into a fallthrough.

### Temp ID Normalization

The optimizer uses `parse_temp_id` to normalize names during liveness analysis. This function strips the `_val` and `_err` suffixes appended during multi-return destructuring, mapping them back to the source temporary's numeric ID. This ensures that the liveness of any part of a destructured result keeps the source expression alive.

### Recursive Descent and Exhaustive Walks

The optimizer employs a recursive descent strategy for both transformations and liveness collection. It explicitly handles all nested block structures, including `if/else`, `while`, `for`, `switch`, `type_switch`, `block`, `defer`, `spawn`, `lock`, and `select`. 

A critical invariant is the **Exhaustive Liveness Walk**. The `collect_used_temps_in_stmt` and `collect_used_var_names_in_stmt` families of functions must visit every variant of `LStmt`, `LExpr`, and `LValue`. Any missed variant would silently drop a live reference, causing the elimination phase to delete a temporary that is still read, leading to miscompiled output.

### Multi-Pass Elimination

The optimizer re-collects live sets after elimination to catch names freed by the first pass. For example, removing a `VarDecl` might make a temporary that was only used in its initializer now unused. This ensures a more thorough cleanup of the LIR.

## Dependencies

*   `[src/lir](../lir/design.md)`: The optimizer is deeply coupled with the LIR data structures, as it performs direct tree-walking and mutation on `LStmt`, `LExpr`, and `LValue` nodes.

## Technical Debt and Future Work

*   **Data-Flow Analysis**: The current implementation is primarily structural and local. A more sophisticated data-flow analysis pass would enable advanced optimizations like constant folding, common subexpression elimination, and better range index coercion.
*   **Optimization Stubs**: Several placeholders exist for future optimizations, such as `coerceForRangeIndex` and `rewriteAppendReassign`. Some of these are currently handled by the `lowerer` or `c_backend` but might be more appropriately placed in the optimizer as the language evolves.
*   **Iterative Fixed-Point**: As transformations become more complex, a formal iterative fixed-point approach for elimination and transformation might be required to ensure all possible optimizations are applied.
