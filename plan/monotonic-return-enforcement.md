# Monotonic Return Enforcement Implementation Plan

## Goal and Scope

Implement monotonic return type check enforcement in HHVM so that a method implementation is checked not only against its own declared return type, but also against every same-name return declaration it inherits from parent classes, interfaces, and abstract ancestors, recursively.

This plan covers:

- `0` = no monotonic inherited return enforcement
- `1` = monotonic inherited return enforcement in soft mode
- `2` = monotonic inherited return enforcement in hard mode

This plan explicitly includes unannotated overrides inheriting return checks. That means a method with no declared return type may still need return verification if it overrides or implements an ancestor declaration with a return type.

This plan also explicitly covers mixed async and non-async override families, which must be normalized carefully so enforcement checks the correct runtime value shape.

This plan assumes the current codebase reality established during investigation:

- HackC only sees one file at a time and cannot compute whole-program inherited contracts.
- Existing return verification for direct declarations is largely driven by emitted `RetC` / `RetM` `VerifyRetKind` plus `VerifyRetTypeTS`.
- Runtime, JIT, and HHBBC already iterate `Func::returnTypeConstraints()` when they decide to perform return verification.
- The current tree appears not to have a live `CheckReturnTypeHints` / `HardReturnTypeHints` implementation, so the new monotonic-return mode must be added as real config plumbing.
- Reflection already distinguishes direct declarations from inherited type constraints via `TypeConstraintFlags::Inherited` and `firstNonInheritedType()`.

## Definitions

- **Direct return contract**: The return type information declared directly on the method in source/HHBC.
- **Inherited return contract**: Return type information coming from any same-name declaration on a parent class, interface, or abstract ancestor, recursively.
- **Effective return contract**: The normalized, deduplicated combination of the direct return contract and all inherited return contracts for a concrete runtime `Func`.
- **Monotonic enforcement mode**: The new config value controlling whether inherited contracts are ignored, soft-enforced, or hard-enforced.
- **Structural return check kind**: Whether the runtime should do no check, full type check, or non-null-only check at a return site. Today this is represented by `VerifyRetKind::{None, All, NonNull}` in bytecode. Under this feature, structural return intent can no longer come only from the bytecode immediate because unannotated overrides may still need checks.
- **Policy mode**: Whether a failing inherited check warns or errors/fatals. This is distinct from the structural check kind.

## Numbered Implementation Steps

1. Add a real generated config entry for monotonic inherited return enforcement.

   Add a new config field through the standard generated config pipeline used by `Cfg`, repo-global-data, and compiler options. The field should be an integer with allowed values `0`, `1`, and `2`, defaulting to `0` unless product requirements specify otherwise.

   Requirements:

   - Make the option available to runtime, JIT, HHBBC, and any compiler-side code that already consumes generated config.
   - Validate the value on load and clamp/reject invalid values.
   - Document semantics in the generated config specification and any user-facing manual files that are still meant to be current.
   - Do not try to revive the old manual-only `CheckReturnTypeHints` / `HardReturnTypeHints` names unless there is an explicit compatibility requirement. If compatibility is required, define exact alias behavior as a separate subtask.

   Output of this step:

   - A live `Cfg::...` integer field visible in runtime/JIT/HHBBC.
   - Repo-global-data serialization for repo-authoritative mode.

2. Add explicit runtime metadata fields for effective monotonic return enforcement.

   Extend runtime function metadata so a `Func` can carry all information needed to enforce inherited return contracts even when bytecode says `VerifyRetKind::None`.

   At minimum, add metadata for:

   - Effective inherited/direct `TypeIntersectionConstraint` for the return value.
   - Effective structural return-check kind derived from that constraint set.
   - Effective inherited reified/type-structure return contract, if any.
   - A fast “has monotonic inherited return checks” bit to avoid overhead on unaffected functions.

   Design rules:

   - Preserve the existing direct declaration as the first non-inherited return type entry.
   - Mark inherited constraints with `TypeConstraintFlags::Inherited`.
   - In monotonic mode `1`, also mark inherited constraints `Soft`.
   - Keep reflection-compatible behavior: source-facing APIs should still treat the direct declaration as the user-visible declaration.

   Output of this step:

   - A `Func` can answer both “what was directly declared?” and “what must be enforced at runtime?”

3. Add safe copy-on-write support for mutating per-class `Func` return metadata.

   Before any class-assembly pass rewrites return constraints, ensure `Func` metadata can be detached safely. Investigation showed that cloned/runtime-reused methods can share `SharedData`, so modifying return constraints in place would leak constraints across classes.

   Implement a utility that:

   - Detects whether a `Func` shares mutable `SharedData`.
   - Allocates/copys detached shared data when class-specific metadata must change.
   - Updates all relevant pointers/ownership invariants without breaking existing `Func::clone()` and class build behavior.

   Validation:

   - Two classes that reuse the same inherited method must not see each other’s effective monotonic return contracts unless they are intentionally identical.
   - Trait-imported or inherited methods that require class-specific tightening must not mutate the original parent/trait definition.

   Output of this step:

   - A safe path for later steps to attach effective inherited contracts to individual runtime methods.

4. Define and implement a canonical effective-return-contract normalization algorithm.

   Implement shared helper logic, ideally in runtime type-constraint utilities or class-building helpers, to compute:

   - The effective direct + inherited `TypeIntersectionConstraint`.
   - The effective structural return-check kind (`None`, `All`, `NonNull`).
   - The effective inherited type-structure/reified return contract.

   Inputs:

   - A concrete method implementation `Func`.
   - The class in which it is being materialized.
   - The resolved same-name ancestor declarations from parents/interfaces/abstract ancestors.
   - The monotonic enforcement mode.

   Normalization rules:

   - Deduplicate equivalent constraints.
   - Preserve deterministic order.
   - Keep the direct declaration first if it exists.
   - If the method has no direct declaration, allow an inherited declaration to drive enforcement.
   - Preserve enough information to reconstruct whether a check is inherited-only or direct.

   Edge cases:

   - Multiple interfaces declaring equivalent return types.
   - Multiple interfaces declaring distinct return types that both need enforcement.
   - Recursive interface inheritance.
   - Trait-imported methods and abstract method stubs.
   - Methods with only reified/type-structure return declarations upstream.

   Output of this step:

   - A single reusable implementation of effective return contract computation.

5. Define async/non-async normalization semantics before enforcing anything.

   Add a dedicated design/implementation layer for mixed async and non-async override families. This is a correctness-critical prerequisite.

   The implementation must define which value is checked for each declaration in a family:

   - For non-async declarations, enforcement conceptually applies to the direct returned value.
   - For async declarations, enforcement conceptually applies to the awaited result contract, not just the raw wait-handle object.

   Required work:

   - Audit existing async return-check semantics in bytecode, JIT, HHBBC, and runtime helpers.
   - Define a canonical normalization rule for comparing an async declaration against a non-async implementation and vice versa.
   - Decide whether currently tolerated async/non-async mismatches should:
     - contribute inherited monotonic checks,
     - be ignored for monotonic purposes,
     - or trigger a dedicated incompatibility path.

   This step must produce an explicit compatibility matrix covering:

   - async overrides async
   - non-async overrides non-async
   - async overrides non-async
   - non-async overrides async
   - interface + class mixes where ancestors disagree in async-ness

   Output of this step:

   - A documented and implemented normalization rule used by all later steps.

6. Compute effective inherited return contracts during runtime class assembly.

   Add a post-pass in `hphp/runtime/vm/class.cpp` after final method tables and implemented interfaces are known. This pass should walk the class’s final runtime methods and compute the effective return contract for each method using the helper from Step 4 and the async normalization from Step 5.

   Required behavior:

   - Resolve same-name ancestor declarations from:
     - parent/base method lineage
     - interfaces implemented by the class
     - recursively inherited interface and abstract declarations
   - For each runtime method:
     - compute the effective contract
     - detach/copy shared metadata if needed
     - attach the effective contract and structural enforcement metadata
   - Skip work when monotonic mode is `0`.

   Important constraints:

   - This pass must work for:
     - directly declared methods
     - inherited-but-not-overridden methods
     - unannotated overrides
     - trait-imported methods
   - Reflection should still show the direct declaration only.

   Output of this step:

   - Every runtime `Func` in a concrete class has class-specific effective return enforcement metadata when the feature is enabled.

7. Change interpreter return handling to combine opcode intent with function metadata.

   Update the interpreter return path in `hphp/runtime/vm/bytecode.cpp` so return verification no longer depends only on the `RetC` / `RetM` `VerifyRetKind` immediate.

   New behavior:

   - Compute an effective structural check kind from:
     - the bytecode’s direct declaration check kind
     - the `Func`’s monotonic inherited enforcement metadata
   - If bytecode says `None` but the function has inherited-only monotonic checks, still perform the required check.
   - If bytecode already says `All` or `NonNull`, preserve direct declared behavior and additionally enforce inherited constraints.
   - Apply the configured policy mode:
     - mode `1`: inherited failures behave as soft
     - mode `2`: inherited failures behave as hard

   Reified/type-structure behavior:

   - Add an interpreter path equivalent to `VerifyRetTypeTS` when inherited type-structure checks exist but bytecode has no emitted `VerifyRetTypeTS`.
   - Do not double-check when direct bytecode already emitted the required type-structure verification.

   Output of this step:

   - Interpreted execution enforces inherited return contracts for unannotated overrides.

8. Change JIT return lowering to use effective function-level return enforcement metadata.

   Update JIT return emission and lowering so it mirrors interpreter behavior.

   Required changes:

   - In `irgen-ret.cpp`, compute the effective structural return-check kind from both opcode and current `Func` metadata.
   - In `irgen-types.cpp`, iterate the effective return constraints, not just the assumption implied by bytecode.
   - Thread policy mode into the existing hard/soft decision instead of relying only on `Cfg::Repo::Authoritative && !tc.isSoft() && !tc.isThis()`.
   - Ensure inherited-only checks are emitted even when bytecode has `VerifyRetKind::None`.
   - Add a JIT path equivalent to `VerifyRetTypeTS` for inherited type-structure/reified checks that HackC could not emit.

   Validation requirements:

   - JIT must not become less strict than the interpreter.
   - Hard-fail IR semantics must remain consistent with the terminal/non-terminal contracts of the relevant IR instructions.
   - Async dropthrough behavior must match interpreter semantics after normalization.

   Output of this step:

   - JIT-compiled returns enforce the same effective monotonic contract as interpreted returns.

9. Update runtime failure-policy helpers so monotonic mode controls inherited failures correctly.

   Audit and adjust the runtime helpers used for return failures, including ordinary type constraints and reified/type-structure paths.

   Requirements:

   - Inherited failures in mode `1` must behave like soft return checks even if the original ancestor declaration was hard.
   - Inherited failures in mode `2` must behave like hard return checks.
   - Direct source-declared checks should preserve their existing semantics unless product explicitly requires monotonic mode to alter them too.
   - Ensure ordinary type-constraint failures and reified/type-structure failures do not diverge in warning/error behavior.

   Output of this step:

   - One consistent policy layer for inherited return check failures.

10. Extend HHBBC to model effective inherited return contracts from whole-program metadata.

   HHBBC already has whole-program inheritance information, so add effective monotonic return metadata there instead of trying to change HackC emission.

   Required work:

   - Extend the inheritance/method-family layer in `hphp/hhbbc/index.cpp` to compute/store effective inherited return contracts for method contexts.
   - Make sure unannotated overrides can still receive inherited return contracts in HHBBC metadata.
   - Update return-type seeding, return modeling, and method-family return lookup to use the effective contract rather than only `php::Func::retTypeConstraints`.

   The HHBBC model must include:

   - effective `TypeIntersectionConstraint`
   - effective structural check kind
   - any inherited type-structure/reified return contract
   - async-normalized semantics from Step 5

   Output of this step:

   - Whole-program optimization sees the same effective return contracts that runtime class assembly computes.

11. Update HHBBC `RetC` / `RetM` / `VerifyRetTypeTS` simplification logic to respect inherited-only checks.

   HHBBC currently reduces return checks based largely on bytecode immediates and direct constraints. That is no longer sufficient.

   Required changes:

   - When bytecode says `VerifyRetKind::None`, HHBBC must still check whether the current function context has inherited monotonic return checks.
   - `All -> NonNull` and `All -> None` reductions must only occur if they remain valid against the effective inherited contract.
   - Inherited-only type-structure/reified return checks must be modeled even when no `VerifyRetTypeTS` instruction was emitted by HackC.

   Validation:

   - Optimized code must not erase checks that runtime would perform.
   - Interface dispatch and method-family return inference must remain monotonic when object types become more specific.

   Output of this step:

   - HHBBC-generated code preserves required monotonic return verification.

12. Update verification, reflection-adjacent tooling, and debug/disassembly output.

   Audit any code that assumes runtime return constraints exactly match source/HHBC return constraints.

   Required updates:

   - Runtime-vs-HHBC consistency verifiers should ignore inherited entries or compare declared and effective forms separately.
   - Reflection should continue to expose the direct declaration only.
   - Debug/disassembly output that prints all return constraints should either:
     - filter inherited constraints in user-facing contexts, or
     - explicitly label them as inherited/effective to avoid confusion.

   Output of this step:

   - Tooling remains understandable and does not flag intentional effective-contract augmentation as corruption or repo mismatch.

13. Add targeted tests for direct, inherited-only, and mixed async return enforcement.

   Add runtime and HHBBC coverage for:

   - annotated child overriding annotated parent
   - unannotated child overriding annotated parent
   - unannotated class implementing annotated interface
   - inherited-but-not-overridden methods that still need effective checks
   - multiple interfaces declaring the same method with equivalent return types
   - multiple interfaces declaring the same method with distinct return types
   - trait-imported methods
   - recursive interface inheritance
   - inherited-only type-structure/reified returns
   - each monotonic mode: `0`, `1`, `2`
   - mixed async/non-async override families using the compatibility matrix from Step 5

   Execution coverage:

   - interpreted execution
   - JIT-compiled execution
   - HHBBC-optimized execution

   For every test, assert both:

   - user-visible behavior (warning/error/fatal or success)
   - absence/presence of verification under the correct mode

14. Run final validation and perform a cross-engine consistency audit.

   Before considering the feature complete, run a targeted audit comparing:

   - runtime class-assembly effective contracts
   - interpreter enforcement behavior
   - JIT lowering/runtime-helper behavior
   - HHBBC effective-contract reasoning

   The acceptance condition is:

   - the same method in the same class sees the same effective monotonic return contract everywhere,
   - unannotated overrides inherit checks correctly,
   - async/non-async mixes follow the chosen normalization rule consistently,
   - and no engine becomes weaker than another.

## Design Notes, Open Questions, and Comments

### A. HackC limitation and resulting design boundary

HackC cannot know the effective inherited return contract because it processes one file at a time. Therefore:

- HackC must not be treated as the place that decides inherited-only return verification.
- Inherited monotonic enforcement for unannotated overrides must come from runtime/whole-program metadata.
- Any implementation that tries to solve inherited-only checks solely by changing emitted `RetC` / `RetM` bytecode is incomplete.

### B. Direct-declaration checks vs inherited-only checks

This plan intentionally separates:

- direct declared return verification that HackC can emit today
- inherited-only verification that must be driven by runtime/whole-program metadata

If future product requirements want a fully unified mechanism, that would require a larger redesign of how return verification is encoded than this plan currently assumes.

### C. Reified/type-structure inherited checks are likely the hardest subproblem

Ordinary inherited `TypeConstraint` checks can be attached as effective runtime metadata fairly naturally. Inherited reified/type-structure checks are harder because today they are tied to emitted `VerifyRetTypeTS`.

If implementation complexity is too high, it may be reasonable to stage this internally as:

1. ordinary inherited type-constraint monotonic enforcement
2. inherited reified/type-structure monotonic enforcement

However, the final feature should not be considered complete until both behave consistently.

### D. Async/non-async normalization must be made explicit before coding deeply

This is not an implementation detail. If the project does not explicitly define how mixed async/non-async families should contribute inherited monotonic checks, different subsystems will make inconsistent assumptions.

Do not proceed with broad implementation until the compatibility matrix from Step 5 is written down and agreed on.

### E. Possible implementation shortcut to avoid

Do not simply append inherited constraints into `returnTypeConstraints()` and assume everything works automatically. That is only safe after:

- class-specific `Func` metadata detachment exists
- inherited-only return sites are actually triggered even when bytecode says `VerifyRetKind::None`
- inherited type-structure/reified checks have an execution path
- HHBBC has been updated to understand the same effective contract

Without those pieces, the feature will be incomplete and engines will diverge.
