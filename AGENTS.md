# AGENTS.md

## Project overview

This is Pi-hole's core repository: the installer, the `pihole` command line interface, and the gravity subsystem that builds the domain blocking database. It is almost entirely bash.

## Repository layout

- `automated install/basic-install.sh` - the installer (also handles updates and repairs)
- `automated install/uninstall.sh` - the uninstaller
- `pihole` - the `pihole` CLI entry point
- `advanced/Scripts/` - scripts backing the CLI subcommands (version, query, api, etc.)
- `advanced/Templates` and `advanced/` generally - service files, templates and assets installed onto the system
- `gravity.sh` - builds `gravity.db` from configured blocklists
- `manpages/` - man pages
- `test/` - BATS test suite, run inside distro-specific Docker containers

## Dev environment tips

- You need Docker (with buildx) and a bash shell; tests and most realistic verification run inside containers, not on the host.
- Keep scripts bash-compatible across all supported distros; do not introduce dependencies that are not available (or installed by the installer) on all of them.
- Installed scripts must remain executable.

## Testing instructions

- From the repository root: `bash test/run.sh --distro debian_12`
- Run `bash test/run.sh --help` for the list of supported distros. The suite covers mocked function tests and a fresh-install test.
- Run at least one distro locally before proposing changes; CI runs the full matrix.
- Lint shell code with shellcheck; CI enforces it.
- Add or update tests in `test/` for any behavioural change.

## PR instructions

- Base all work on the `development` branch; pull requests target `development`.
- Read the [contributors guide](https://docs.pi-hole.net/guides/github/contributing/)
- Every commit must be signed off (DCO): use `git commit -s`.
- Run the tests and shellcheck before committing.
- Use Unix line endings (LF).
- Code is licensed under the EUPL 1.2; contributions must be compatible.
- Stability comes before features. This code runs unattended on a huge variety of systems; prefer conservative, well-tested changes and avoid speculative refactors.
- Match the existing style of surrounding code, including the `# shellcheck` directives and local/readonly variable conventions already in use.
- The correct project spelling is "Pi-hole" (capital P, lowercase h, hyphen).

## Security considerations

- The installer and most scripts run as root on end-user systems. Quote variables, validate all user-supplied and downloaded input, and avoid constructs that can expand into unintended commands.
- Gravity consumes remote blocklists; treat downloaded content as untrusted data, never as executable input.
- If you believe you have found a vulnerability, do not open a public issue or PR; report it privately per the organisation's security policy (disclosure@pi-hole.net).

## Common pitfalls

- Testing only on one distro and breaking another; the installer supports many package managers and init systems.
- Using bashisms in contexts executed by `sh`, or GNU-only flags on tools that differ on busybox/Alpine.
- Forgetting the DCO sign-off on commits.
- Changing installer behaviour without updating the corresponding tests in `test/`.
