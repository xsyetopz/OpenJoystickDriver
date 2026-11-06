# Before / after

## Tagline

Before: `🚀 A powerful, blazing-fast, and intuitive tool to supercharge your workflow ✨`
After: `Find unused exports in a TypeScript monorepo in under a second.`

Why: the after names the input, the output, and a checkable number.

## Intro

Before:
> In today's fast-paced development landscape, managing configuration can be a daunting challenge. Whether you're a solo developer or part of a large team, ConfigX empowers you to seamlessly manage your settings — it's not just a config loader, it's a complete configuration solution.

After:
> ConfigX loads config from env vars, `.env`, and YAML, validates it against a schema, and fails at startup with the exact key that is wrong. We wrote it after a missing `DATABASE_URL` took down staging for an hour.

## Features

Before:
```md
## ✨ Features
- 🔥 **Blazing Fast**: Experience lightning-fast performance
- 🛡️ **Secure**: Built with security in mind
- 🎨 **Customizable**: Tailor it to your needs
- 🌍 **Cross-Platform**: Works everywhere
```

After:
```md
## Features
- Parses 1 GB of logs in 2.1 s on an M2 (see `bench/`)
- No network access; runs fully offline
- Output as JSON, CSV, or a terminal table (`--format`)
- Linux, macOS, Windows binaries on every release
```

## Contributing

Before: a 5-step fork/clone/branch/commit/PR list plus "Contributions are what make the open source community such an amazing place to learn, inspire, and create."

After:
```md
## Contributing
PRs welcome. Run `make test` before opening one; see [CONTRIBUTING.md](CONTRIBUTING.md).
```

## Ending

Before:
> ## Conclusion
> ConfigX is a robust and versatile solution for all your configuration needs. Happy coding! 🎉

After: (nothing; the README ends at License)
