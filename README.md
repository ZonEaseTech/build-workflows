# ZonEaseTech build workflows

Build and verify private release candidates for the ZonEaseTech skills and Shiftly projects. An authorized maintainer can run **Build private release candidates** on main, select the project, and optionally select an exact commit reachable from its main branch. Each project also provides a private dispatch entry point.

The selected revision supplies its build recipe in `scripts/ci-build.sh`. Builds use an isolated Node.js container. Credentials stay on the runner outside that container. Each attempt writes its outputs, diagnostic log, source revision and checksums to a draft Release in the source repository, then downloads and verifies the files. Failed builds deliver diagnostics only. The diagnostic test exercises this failure path.

Only trusted release maintainers should have write access to this repository. The main-only private-build environment issues short-lived GitHub App installation tokens restricted to the selected repository.
