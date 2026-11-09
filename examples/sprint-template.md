# T1 · Sprint <NAME>: <one-line goal>

**Goal:** what is true when this lands.
**Scope:** about N lines. **Touches:** the files it may change. **Not touched:** the files it may not.
**Base:** <commit SHA> or a descendant.

## What is already known
- A fact the plan rests on, with `path/to/file.rs:123`.
- Anything this corrects from an earlier assumption.

## The decisions (register)
- **R1.** A decision, and why.
- **R2.** …

## Verified assumptions (run first; no commits)
- **A0. STOP:** the tree is clean, HEAD contains the base, and the tests pass. Name the other running lanes and what
  they touch.
- **A1. STOP:** quote each fact above at HEAD. **STOP if** any of them is false.
- **A2. Documented branch:** if X, do Y and record it; this is not a stop.

Write predictions for A0–A2 first, then mark each one confirmed or refuted.

## Steps
### Step 1: <name>
What to change. Show the new test failing on the old code, then passing.
```
git add <files>
```
```
git commit -m "T1 step 1: <what>"
```
```
git push
```

## Exit criteria
- The test suite is green; the new tests failed first and pass now.
- `git status` is clean, and every step is pushed. Report the final HEAD.
- The report lists deviations first, every STOP check verbatim, and the predictions marked.
- If you stop, also write the stop message to `<scratch>/STOP_QUESTIONS.md`.
- Do not propose or suggest next tasks.
