# Changelog

All notable changes to X Messenger Terminal are documented here.

## [0.1.0] - Stage 0: Legacy Migration

### Added
- Repository structure per spec §8
- Honest README with no "stable", "guaranteed", or hand-typed test counts
- SECURITY.md with threat model and honest claims
- Repository structure: xc, tests/, docs/, scripts/, evidence/, .github/workflows/
- MIT LICENSE

### Removed
- Legacy Node.js web app, Capacitor Android, Windows builds, VPS/LAN modes, custom v2 protocol
- All Node.js, Go, Java/Kotlin, Capacitor, Gradle, web assets

### Migration
- Tagged legacy state as `legacy-v1.5.2` on `legacy` branch
- Recorded 38/100 review score in `docs/SCORE_HISTORY.md` (commit cd14a34)