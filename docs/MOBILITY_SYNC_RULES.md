# Mobility Sync Rules

This document defines how mobility-side work moves from internal development into the public `OpenBene` tree.

## Source Of Truth

- Internal development source: `BeneMobility` and the local-only `openbene_mobility/`
- Public release target: `OpenBene`

Do not copy the whole internal mobility tree into `OpenBene`.

## What May Move Into OpenBene

- Stable ROS2 packages that are no longer experimental
- General launch files and configs that a customer can run directly
- Cleaned mapping / localization workflows with minimal dependencies
- Public-facing setup and run documentation
- Mobility features that are reusable across robots and not tied to internal experiments

## What Must Stay Out Of OpenBene

- Experiments, sweeps, and one-off evaluation scripts
- Internal datasets, captured sessions, and local outputs
- Internal worklogs, handoff notes, and draft plans
- Customer-specific parameters and environment assumptions
- Unstable algorithms that still change frequently

## Promotion Checklist

Before moving a mobility feature into `OpenBene`, confirm all of the following:

1. The feature has a clear public purpose.
2. The file layout is clean and no longer depends on internal paths.
3. Setup steps are short enough for an external user.
4. Local datasets and private docs are removed.
5. The feature has at least minimal smoke validation.
6. The code no longer depends on internal-only helper scripts unless those helpers are promoted too.

## Preferred Public Layout

When mobility work is promoted, place it in a clearly bounded public area, for example:

- `openbene_mobility/` for a future public mobility package
- `docs/` for public mobility runbooks

Do not mix public mobility code back into `openbene_sdk/` unless it is truly platform-layer code.

## Boundary Rule

- If the code is platform-layer, reusable, and hardware-agnostic: keep or move it into `OpenBene`.
- If the code is ROS2 research, mapping, localization, navigation tuning, or internal workflow glue: keep it in internal mobility development until it is cleaned for release.
