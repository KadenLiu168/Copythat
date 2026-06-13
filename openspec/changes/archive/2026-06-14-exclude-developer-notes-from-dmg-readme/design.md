## Context

`script/package_dmg.sh` currently copies the root `README.md` into the DMG. The root README intentionally contains both user-facing installation information and developer-only sections beginning at `## Developer Notes`, but DMG users only need the installation and feature content.

## Goals / Non-Goals

**Goals:**
- Keep the repository README as the complete source for user and developer documentation.
- Package only the README content before `## Developer Notes` into the DMG.
- Verify the packaged README keeps user-facing guidance and excludes developer-only content.

**Non-Goals:**
- Do not split the README into two hand-maintained files.
- Do not remove developer documentation from the repository README.
- Do not change signing, notarization, app behavior, or DMG layout.

## Decisions

- Use `## Developer Notes` as the delimiter for the DMG README. This matches the current README structure and keeps the generated DMG README derived from the same source.
- Generate the DMG README during packaging with `awk` rather than adding a new tracked file. This avoids documentation drift while keeping the script simple.
- Add positive and negative content checks after mounting the DMG: the README must include user-facing headings and must not include `Developer Notes`.

## Risks / Trade-offs

- If the delimiter is renamed, the packaged README could include developer content again -> Mitigation: packaging verification fails when `Developer Notes` appears in the DMG README.
- The generation step depends on a specific README structure -> Mitigation: keep the delimiter explicit in the spec and script.
