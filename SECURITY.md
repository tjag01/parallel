# Security

Parallel drives Claude Code sessions on your machine. The parts that matter for security are the relay, which types
text into running sessions, and the optional `CLAUDE_FLAGS="--dangerously-skip-permissions"`. Both are described in
the README and in [docs/RELAY.md](docs/RELAY.md).

To report a security problem, open a private report through GitHub's "Report a vulnerability" button on this
repository (Security tab), rather than a public issue. Please include the version (`cc-parallel version`), what you
ran, and what happened.
