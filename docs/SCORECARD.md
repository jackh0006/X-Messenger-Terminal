# SCORECARD.md — OpenSSF Scorecard & Best Practices

This document tracks the project's OpenSSF Scorecard results and Best Practices badge status.

---

## OpenSSF Scorecard

| Check | Weight | Status | Notes |
|-------|--------|--------|-------|
| **Security** | | | |
| Binary-Artifacts | 4 | Not applicable (source = script) | |
| Branch-Protection | 5 | Required on main | |
| Code-Review | 5 | Required (2 approvals for crypto) | |
| Dangerous-Workflow | 5 | No dangerous workflows | |
| Dependency-Update-Tool | 3 | N/A (no package.json) | |
| Fuzzing | 5 | AFL++/radamsa >=1h/parser in CI | |
| License | 5 | MIT + compatible deps | |
| Maintained | 5 | Active development | |
| Packaging | 5 | Release tarball + signed | |
| Pinned-Dependencies | 5 | Pinned Actions (commit SHAs) | |
| SAST | 5 | shellcheck + semgrep in CI | |
| Signed-Releases | 10 | ssh-keygen -Y verify + SHA256SUMS.sig | |
| Token-Permissions | 5 | Minimal permissions in workflows | |
| Vulnerabilities | 5 | No known vulns in deps | |

**Target Score: >= 8 / 10**

---

## OpenSSF Best Practices Badge

| Criterion | Level | Status | Evidence |
|-----------|-------|--------|----------|
| **Basics** | | | |
| License | Passing | MIT | LICENSE |
| Version Control | Passing | Git + signed commits | |
| Unique Versioning | Passing | SemVer tags | |
| Release Notes | Passing | CHANGELOG.md + release notes | |
| Bug Reporting | Passing | SECURITY.md + GitHub Issues | |
| **Change Control** | | | |
| Small Commits | Passing | One logical change per commit | |
| Tested Releases | Passing | CI must pass before release | |
| **Reporting** | | | |
| Vulnerability Reporting | Passing | SECURITY.md with email | |
| **Quality** | | | |
| CI/CD | Passing | GitHub Actions (pinned) | |
| Code Review | Passing | 2 approvals for crypto | |
| Static Analysis | Passing | shellcheck + semgrep | |
| **Security** | | | |
| Hardening | Passing | FLAG_SECURE, umask 077, no eval | |
| Crypto | Passing | age + OpenSSH only | |
| Input Validation | Passing | Strict validation in xc | |
| **Documentation** | | | |
| README | Passing | Honest, no hype | |
| Install Docs | Passing | INSTALL.md | |
| Security Docs | Passing | SECURITY.md + THREAT_MODEL.md | |
| API Docs | N/A | CLI only | |

**Target: Silver badge (all Passing)**

---

## Current Status

| Metric | Value |
|--------|-------|
| Scorecard Score | Not yet run (Stage 4) |
| Best Practices | Not yet applied |
| Last Updated | Stage 0 |

---

## Next Steps (Stage 4)

1. Enable `ossf/scorecard-action` in CI
2. Run scorecard, fix any failures
3. Apply for Best Practices badge
4. Update this document with actual scores