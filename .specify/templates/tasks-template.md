# Tasks: [FEATURE_NAME]

**Branch**: [BRANCH_NAME]
**Plan**: [PLAN_FILE]
**Generated**: [DATE]

---

## Summary

- Total tasks: [TOTAL]
- Phases: [PHASE_COUNT]
- Parallelizable tasks: [PARALLEL_COUNT]

---

## Phase 1: Setup

**Goal**: Initialize project structure and tooling required for this feature.

- [ ] T001 [SETUP_TASK_1]
- [ ] T002 [SETUP_TASK_2]

---

## Phase 2: Foundational

**Goal**: Implement blocking prerequisites that all user stories depend on.

- [ ] T003 [FOUNDATIONAL_TASK_1]
- [ ] T004 [FOUNDATIONAL_TASK_2]

---

## Phase 3: [USER_STORY_1_NAME] (P1)

**Story goal**: [WHAT THE USER CAN DO AFTER THIS PHASE]
**Test criteria**: [HOW TO VERIFY THIS STORY INDEPENDENTLY]

- [ ] T005 [P] [US1] [TASK_DESCRIPTION] in [FILE_PATH]
- [ ] T006 [US1] [TASK_DESCRIPTION] in [FILE_PATH]

---

## Phase 4: [USER_STORY_2_NAME] (P2)

**Story goal**: [WHAT THE USER CAN DO AFTER THIS PHASE]
**Test criteria**: [HOW TO VERIFY THIS STORY INDEPENDENTLY]

- [ ] T007 [P] [US2] [TASK_DESCRIPTION] in [FILE_PATH]
- [ ] T008 [US2] [TASK_DESCRIPTION] in [FILE_PATH]

---

## Final Phase: Polish & Cross-Cutting

**Goal**: Final integration, cleanup, documentation updates.

- [ ] T009 [POLISH_TASK_1]
- [ ] T010 [POLISH_TASK_2]

---

## Dependency Graph

```
T001 → T003 → T005
T002 → T004 → T007
T005 → T009
T007 → T009
```

---

## Parallel Execution Examples

**User Story 1** — can run in parallel after T004:
```
T005 ‖ T006
```

---

## MVP Scope

Minimum viable: Phase 1 + Phase 2 + Phase 3 (User Story 1 only)
