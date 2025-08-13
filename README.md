# MacOs-Sh-Scripts — Pro Fullstack macOS Setup

A configurable, idempotent macOS setup script for experienced full‑stack developers.

Highlights:
- Config‑driven (YAML): choose what to install, per category.
- Homebrew formulae/casks, Mac App Store (mas), npm, pipx, pyenv, fnm.
- AI in terminal: Aider (Claude) via pipx, GitHub Copilot CLI (gh extension).
- Browsers (Arc, Chrome, Firefox Dev), IDEs (IntelliJ Ultimate, VS Code), JetBrains Toolbox.
- Node (fnm + versions + global packages), Python (pyenv + pipx), Java (Temurin), Go, Rust.
- DevOps: Docker Desktop or Colima, kubectl/helm/k9s, Terraform/OpenTofu, AWS/Azure/GCP CLIs.
- GitHub auth (device flow or token env), SSH key generation, git config.
- Idempotent installs, logs, and sensible PATH setup.

Quick start
1) Copy the example config and edit:
```bash
cp config.example.yaml config.yaml
cp .env.example .env    # optional, for tokens/keys
```
2) Run:
```bash
./setup.sh -c config.yaml
```

Requirements
- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (the script can prompt to install)
- Internet access; you may need to sign in interactively for App Store, JetBrains, Docker

Security
- Prefer environment variables in .env for tokens (e.g., ANTHROPIC_API_KEY, GH_TOKEN). Avoid plaintext secrets in config.yaml.

Common tasks
- Re-run safely: The script is idempotent; it skips already-installed items.
- Switch profile: Maintain multiple config YAMLs and run with -c.
- Logs: See setup.log.

Notes
- IntelliJ Ultimate requires a license; installation is automated, sign-in is manual (JetBrains).
- Arc is installed via Homebrew cask.
- Aider uses Claude via ANTHROPIC_API_KEY. Export in .env.
