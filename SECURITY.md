# Security Policy

## Supported Versions
SchroSIM is an active development project. Security fixes are applied to the latest development line.

| Version | Supported |
| --- | --- |
| `main` | :white_check_mark: |
| Older branches/tags | :x: |

## Reporting a Vulnerability
Please report suspected vulnerabilities privately. Do not open public issues for exploitable security details.

Preferred process:
1. Use GitHub private vulnerability reporting for this repository if available.
2. Include clear reproduction details:
   - affected component (`core-rust`, `core-swift`, CLI, runtime config),
   - impact and attack scenario,
   - proof of concept or minimal reproduction input,
   - suggested mitigation if known.

If private vulnerability reporting is not enabled, open a minimal issue requesting a private channel and do not include exploit details publicly.
You can also contact the maintainer account at https://github.com/DennisWayo and request a private reporting channel.

## Response and Disclosure
Project maintainers aim to:
1. Acknowledge reports within 5 business days.
2. Assess severity and affected scope.
3. Coordinate remediation and validation.
4. Publish fixes and disclosure notes once users can safely update.

## Scope Notes
Security reports are especially useful for:
1. Unsafe parsing or execution behavior in circuit/runtime input paths.
2. Privilege or boundary breaks in tooling or scripts.
3. Supply-chain risk in dependency and build workflows.
4. Sensitive data leakage through logs, traces, or exported artifacts.
