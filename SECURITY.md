# Security Policy

## Supported Versions

Only builds of 0.6.0-alpha.1 and later get security fixes. 0.5.0-beta.4 and earlier get none.

## Report a Vulnerability

Report it privately through [GitHub private vulnerability reporting](https://github.com/xsyetopz/OpenJoystickDriver/security/advisories/new). Do not open a public issue, discussion, or pull request.

Include:

- The OpenJoystickDriver version: the whole line from **About OpenJoystickDriver**, such as `0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)`. [Finding the Version](CONTRIBUTING.md#finding-the-version) shows how to get it.
- The macOS version and build from `sw_vers`.
- The part affected: the app, the service, the `ojd` command, the endpoint, the Xbox USB driver extension, profiles, or mod packages.
- Numbered steps that show the problem, and what an attacker gains.
- A proof of concept, if you have one.

AI agents follow the same rules as in [`CONTRIBUTING.md`](CONTRIBUTING.md#ai-agents): a human operator reads and submits the report and is named in it.

## In Scope

- A local program that reaches the service socket or the endpoint without a grant, or does more than its grant allows.
- A profile, mod package, or controller record that makes OpenJoystickDriver run code, write outside its own folders, or crash the service.
- A USB device that makes the driver extension or the service crash, hang, or read or write out of bounds.
- A support report or log that leaks data that [Permissions and Security](wiki/Permissions-and-Security.md) says it leaves out.

## Out of Scope

- A Mac with System Integrity Protection or Apple Mobile File Integrity turned off.
- An attacker who already runs code as the logged-in user and only does what that user can do.
- Builds that you signed yourself, or that a third party modified.
