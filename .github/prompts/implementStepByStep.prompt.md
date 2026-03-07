---
name: implementStepByStep
description: Implement multi-step technical plan with tests, pausing after each step for review
argument-hint: The multi-step plan or specification to implement incrementally
---

# Step-by-Step Implementation with Testing

Implement the provided multi-step plan following these principles:

## Implementation Rules

1. **One Step at a Time**: Implement only one complete step before stopping
2. **Complete Implementation**: For each step, create all required:
   - Core functionality files (functions, modules, schemas, etc.)
   - Comprehensive test suite covering all features
   - Documentation (optional: README/guide for complex steps)

3. **Test-First Verification**: 
   - Write tests that cover all functionality in the step
   - Run tests against the appropriate environment (Docker, local, etc.)
   - Fix any issues until all tests pass
   - Show test results proving everything works

4. **Pause for Review**:
   - After each step is complete and tested, STOP
   - Present what was created (files, line counts, key features)
   - Show test results summary
   - Wait for user confirmation before proceeding to next step

## Quality Standards

- **Tests are mandatory**: Every function/feature must have corresponding tests
- **All tests must pass**: Do not proceed if tests fail
- **Use containerized services**: When applicable, use Docker for databases, services, etc.
- **Show your work**: Display the actual functions/code and tests for user review
- **Track progress**: Use todo lists or similar to show which steps are complete

## Output Format

For each step, provide:
1. **Files Created/Modified**: List with line counts
2. **Key Features**: Bullet points of what was implemented
3. **Test Coverage**: Number of tests, assertions, what they verify
4. **Test Results**: Show actual test output proving everything passes
5. **What's Next**: Brief preview of the next step

## User Control

- User can request modifications to current step before proceeding
- User can ask to see specific code/tests in detail
- User signals readiness with "next step" or similar

Implement in a way that ensures steady, verified progress with full user visibility and control at each checkpoint.
