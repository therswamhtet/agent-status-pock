# Contributing

Thanks for helping improve Agent Status.

## Before You Start

- Search existing issues and pull requests before opening a new one.
- Use an issue for behavior changes or larger features before implementation.
- Keep changes focused and preserve existing user configuration.
- Never include tokens, private logs, or machine-specific paths in commits.

## Development Setup

Agent Status requires macOS 15 or newer and Xcode Command Line Tools.

```bash
git clone https://github.com/therswamhtet/agent-status-pock.git
cd agent-status-pock
make test
```

`make test` builds the bridge and universal widget, exercises the local HTTP
API, runs the widget smoke test, and renders visual states.

## Pull Requests

1. Create a branch from `main`.
2. Add focused tests for behavior changes.
3. Run `make test` and `bash -n install.sh uninstall.sh scripts/*.sh`.
4. Explain the user-visible change and how it was verified.
5. Include screenshots when changing the Touch Bar UI.

By submitting a contribution, you agree that it is licensed under the MIT
License included in this repository.
