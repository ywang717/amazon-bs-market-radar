# Codex Skills Work Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify four user-level Amazon/product-development skills that complement the existing Superpowers workflow without overlapping triggers.

**Architecture:** Install no new third-party code unless the existing Superpowers package is absent. Put the four standalone skills under `C:\Users\ASUS\.agents\skills`, keep routing and decision rules in each `SKILL.md`, move substantial frameworks to `references`, and keep report layouts in `assets\templates` because current Codex treats output resources as assets. Use implicit invocation with discriminating descriptions and verify routing with clean-context positive and negative prompts.

**Tech Stack:** Codex CLI 0.150.0-alpha.8, Agent Skills `SKILL.md`, YAML `agents/openai.yaml`, Markdown references/templates, Python-based `quick_validate.py`.

**Spec:** User-approved “Codex Skills 工作环境搭建 — 最终执行方案” supplied in the 2026-08-28 conversation.

## Global Constraints

- Create exactly four business skills: `amazon-research`, `amazon-compliance`, `prd-product-review`, and `amazon-report`.
- Keep existing Superpowers; do not duplicate or delete it.
- Default marketplace is Amazon US and default output language is Chinese; preserve Brand, ASIN, SKU, product names, and technical terms in English.
- Keep implicit triggers mutually exclusive; bug-fix prompts route to `superpowers:systematic-debugging` rather than `prd-product-review`.
- Do not install or execute unreviewed third-party code or access credentials, cookies, SSH keys, Git credentials, or unrelated API keys.
- Distinguish facts, data, inferences, assumptions, and recommendations; never fabricate Amazon metrics or compliance requirements.

---

### Task 1: Audit the current runtime and record a routing baseline

**Files:**
- Read: `C:\Users\ASUS\.codex\config.toml` (skill-related keys only)
- Read: installed `SKILL.md` and plugin manifests
- No files created

**Interfaces:**
- Consumes: Codex CLI and current skill/plugin directories
- Produces: environment inventory, duplicate-name inventory, Superpowers availability, and baseline routing failures

- [x] Inspect Codex version, official loading paths, plugins, current skills, and duplicate names.
- [x] Run the ten requested trigger prompts without the four custom skills.
- [x] Confirm the missing-domain-routing failures that the custom skills must correct.

### Task 2: Create and verify `amazon-research`

**Files:**
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\SKILL.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\agents\openai.yaml`
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\references\research-framework.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\references\opportunity-scoring.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\references\confidence-model.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-research\references\data-analysis.md`

**Interfaces:**
- Consumes: Amazon category questions, ASIN/competitor data, Excel/CSV datasets
- Produces: evidence-labeled market analysis and optional opportunity score with confidence

- [x] Initialize only the required resources.
- [x] Write the minimal discriminating description and routing workflow.
- [x] Validate structure with `quick_validate.py`.
- [x] Run research, Excel, opportunity, compliance-negative, and report-negative routing tests.
- [x] Refine the description until tests pass.

### Task 3: Create and verify `amazon-compliance`

**Files:**
- Create: `C:\Users\ASUS\.agents\skills\amazon-compliance\SKILL.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-compliance\agents\openai.yaml`
- Create: `C:\Users\ASUS\.agents\skills\amazon-compliance\references\source-priority.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-compliance\references\compliance-classification.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-compliance\references\compliance-checklist.md`

**Interfaces:**
- Consumes: product classification, marketplace, electrical/battery/material attributes, and current authoritative sources
- Produces: requirement table with A/B/C/D classification, status, evidence, risk, and checklist

- [x] Initialize and write the skill and references.
- [x] Validate with `quick_validate.py`.
- [x] Run compliance-positive and market-research-negative routing tests.
- [x] Refine until authoritative-source and classification behavior passes.

### Task 4: Create and verify `prd-product-review`

**Files:**
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\SKILL.md`
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\agents\openai.yaml`
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\references\prd-framework.md`
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\references\product-review-framework.md`
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\references\ui-review-framework.md`
- Create: `C:\Users\ASUS\.agents\skills\prd-product-review\references\acceptance-criteria.md`

**Interfaces:**
- Consumes: product/dashboard/software context, review evidence, or requested requirements
- Produces: prioritized review findings or a scoped PRD/implementation plan

- [x] Initialize and write Review Mode and PRD Mode routing.
- [x] Validate with `quick_validate.py`.
- [x] Run review/PRD positive tests and bug-fix negative tests.
- [x] Refine until bug prompts consistently remain with `systematic-debugging`.

### Task 5: Create and verify `amazon-report`

**Files:**
- Create: `C:\Users\ASUS\.agents\skills\amazon-report\SKILL.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-report\agents\openai.yaml`
- Create: `C:\Users\ASUS\.agents\skills\amazon-report\assets\templates\market-report.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-report\assets\templates\product-opportunity-report.md`
- Create: `C:\Users\ASUS\.agents\skills\amazon-report\assets\templates\compliance-report.md`

**Interfaces:**
- Consumes: existing research, Excel analysis, opportunity results, or compliance findings
- Produces: decision-oriented chat, Markdown, Excel, Word, or PowerPoint report selected by user need

- [x] Initialize and write the output-layer-only trigger.
- [x] Validate with `quick_validate.py`.
- [x] Run report-positive and new-research-negative routing tests.
- [x] Refine until research and report routing no longer compete.

### Task 6: Run full conflict, security, and readiness verification

**Files:**
- Verify: all files under `C:\Users\ASUS\.agents\skills\{amazon-research,amazon-compliance,prd-product-review,amazon-report}`

**Interfaces:**
- Consumes: four validated skills and current Superpowers package
- Produces: final PASS/FAIL matrix and READY/NOT READY decision

- [x] Run all requested positive trigger tests in clean contexts.
- [x] Run all requested negative trigger tests in clean contexts.
- [x] Scan names/descriptions for duplicate and trigger conflicts.
- [x] Inspect all created resources for credential, network, shell, and executable behavior.
- [x] Confirm all required Superpowers skills are present and readable.
- [x] Run `quick_validate.py` for all four skills and inspect every output.
- [x] Report READY only if every Definition of Done condition is evidenced.
