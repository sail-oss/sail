---
name: update-sail-instructions
description: 'Update the SAIL project copilot-instructions.md. Use when: the architecture has changed, a new subproject was added, build commands changed, new conventions established, CRD or message schema updated, or the instructions are stale. Triggers: "update instructions", "update copilot-instructions", "instructions are outdated", "add to instructions", "document this convention".'
argument-hint: 'What changed, e.g. "new subproject added" or "new Makefile targets"'
---

# Update SAIL Copilot Instructions

## Purpose

Keep `.github/copilot-instructions.md` accurate and current as the SAIL codebase evolves.

## Sections in copilot-instructions.md

| Section | What it covers |
|---------|---------------|
| **Architecture** | Subproject roles, message flow diagram, shared data model, Redis discovery |
| **Build and Run** | Maven commands, dev ports, Makefile targets, scripts |
| **Conventions** | Package names, Quarkus profiles, naming patterns, image registry, security rules |

## Procedure

### 1. Read the current instructions

Read `.github/copilot-instructions.md` in full to understand the current state before making any changes.

### 2. Discover what changed

Based on the user's description (or the `argument-hint`), explore the relevant parts of the codebase:

- **New subproject**: scan the new module's `pom.xml`, `README.md`, and main Java source for its role, dependencies, and entry points.
- **Changed commands**: read the relevant `Makefile`, `scripts/`, and `pom.xml` to verify current targets and flags.
- **Schema / data model changes**: search for the `SailMessage` class and any new message types across all subprojects.
- **CRD changes**: read `sail-operator/resources/genericagents.sebi.org-v1.yml` and the reconciler source.
- **New conventions**: check `application.properties` files and Java source for new patterns.

Use targeted searches rather than reading entire files. Prefer `grep_search` and `semantic_search` for discovery. Consult [codebase-locations.md](./references/codebase-locations.md) for a full map of where each piece of information lives.

### 3. Identify the minimal set of edits

Map discoveries to the affected section(s). Do **not** rewrite unrelated sections. Typical changes:

- Add a bullet to **Architecture** for a new subproject.
- Add or update a command block in **Build and Run**.
- Add a bullet to **Conventions** for a new naming rule or secret.
- Update the message flow diagram only if the topology changed.

### 4. Make the edits

Edit `.github/copilot-instructions.md` directly using targeted replacements. Keep the existing style:
- Subproject bullets use `**name** — description` format.
- Commands go in fenced `sh` blocks with brief inline comments.
- Conventions are short bullet points with the pattern in **bold**.

### 5. Validate

After editing:
- Re-read the updated file to confirm accuracy and consistent formatting.
- Ensure no section was accidentally truncated.
- Confirm factual claims match the codebase (e.g. port numbers, image tags, package names).

## Key Facts to Preserve

These must remain accurate in any update:

- Three independent Quarkus subprojects — no parent POM, no shared modules.
- Java 21 required; each subproject has its own `mvnw`.
- Package `org.sebi` across all modules.
- Knative resource naming: `{agent-name}-svc` (Service), `{agent-name}-trigger` (Trigger).
- Redis key format: `genericagent:<namespace>:<name>`.
- Kafka topic: `agents-messages`.
- MCP server dev port: `8081`.
- Credentials always via Kubernetes secrets — never hardcoded.
