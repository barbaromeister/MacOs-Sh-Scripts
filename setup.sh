#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="setup.log"
CONFIG_FILE="config.yaml"
export HOMEBREW_NO_AUTO_UPDATE=1

# Colors
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "➡️  %s\n" "$*" | tee -a "$LOG_FILE"; }
ok()   { printf "✅ %s\n" "$*" | tee -a "$LOG_FILE"; }
warn() { printf "⚠️  %s\n" "$*" | tee -a "$LOG_FILE"; }
err()  { printf "❌ %s\n" "$*" | tee -a "$LOG_FILE"; }

usage() {
  cat <<EOF
Usage: $0 [-c config.yaml]
EOF
}

while getopts ":c:h" opt; do
  case "$opt" in
    c) CONFIG_FILE="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing dependency: $1"
    return 1
  fi
}

# Ensure Homebrew
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew detected"
  else
    info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    if [[ -d /opt/homebrew/bin ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
      add_to_shell_rc 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    else
      eval "$(/usr/local/bin/brew shellenv)"
      add_to_shell_rc 'eval "$(/usr/local/bin/brew shellenv)"'
    fi
    ok "Homebrew installed"
  fi
}

brew_install() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    ok "brew formula already installed: $formula"
  else
    info "brew install $formula"
    brew install "$formula" || warn "Failed installing $formula"
  fi
}

brew_install_cask() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    ok "brew cask already installed: $cask"
  else
    info "brew install --cask $cask"
    brew install --cask "$cask" || warn "Failed installing cask $cask"
  fi
}

brew_install_cask_any() {
  for c in "$@"; do
    if brew list --cask "$c" >/dev/null 2>&1; then ok "brew cask already installed: $c"; return 0; fi
  done
  for c in "$@"; do
    info "Trying cask: $c"
    if brew install --cask "$c"; then ok "Installed cask: $c"; return 0; fi
  done
  warn "None of the casks could be installed: $*"
  return 1
}

shell_rc_file() {
  if [[ -n "${ZDOTDIR:-}" ]]; then echo "$ZDOTDIR/.zshrc"; return; fi
  if [[ -n "${SHELL:-}" && "${SHELL##*/}" == "zsh" ]]; then echo "$HOME/.zshrc"; return; fi
  echo "$HOME/.zshrc"
}

add_to_shell_rc() {
  local line="$1"
  local rc
  rc="$(shell_rc_file)"
  if [[ ! -f "$rc" ]] || ! grep -Fqx "$line" "$rc"; then
    echo "$line" >> "$rc"
    ok "Appended to ${rc}: $line"
  fi
}

ensure_yq_jq() {
  brew_install yq
  brew_install jq
}

ensure_xcode_clt() {
  local want
  want=$(yq -r '.system.xcode_clt // false' "$CONFIG_FILE")
  if [[ "$want" == "true" ]]; then
    if xcode-select -p >/dev/null 2>&1; then
      ok "Xcode Command Line Tools present"
    else
      info "Installing Xcode Command Line Tools..."
      xcode-select --install || true
      warn "If a GUI prompt appeared, complete it and re-run the script."
    fi
  fi
}

ensure_rosetta() {
  local want
  want=$(yq -r '.system.install_rosetta_if_needed // false' "$CONFIG_FILE")
  if [[ "$want" == "true" && "$(uname -m)" == "arm64" ]]; then
    if /usr/bin/pgrep oahd >/dev/null 2>&1; then
      ok "Rosetta already installed"
    else
      info "Installing Rosetta 2..."
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install may require user approval"
    fi
  fi
}

install_browsers() {
  if [[ "$(yq -r '.browsers.arc // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install_cask_any arc arc-browser
  fi
  if [[ "$(yq -r '.browsers.chrome // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install_cask google-chrome
  fi
  if [[ "$(yq -r '.browsers.firefox_dev // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install_cask firefox-developer-edition
  fi
}

install_terminal_stack() {
  [[ "$(yq -r '.terminal.warp // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask warp
  [[ "$(yq -r '.terminal.iterm2 // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask iterm2
  if [[ "$(yq -r '.terminal.starship // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install starship
    add_to_shell_rc 'eval "$(starship init zsh)"'
  fi
  [[ "$(yq -r '.terminal.tmux // false' "$CONFIG_FILE")" == "true" ]] && brew_install tmux

  local tap
  tap=$(yq -r '.terminal.fonts.tap_cask_fonts // false' "$CONFIG_FILE")
  if [[ "$tap" == "true" ]]; then
    if brew tap | grep -q '^homebrew/cask-fonts$'; then
      ok "tap homebrew/cask-fonts already present"
    else
      info "brew tap homebrew/cask-fonts"
      brew tap homebrew/cask-fonts
    fi
  fi
  [[ "$(yq -r '.terminal.fonts.jetbrains_mono // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask font-jetbrains-mono
  [[ "$(yq -r '.terminal.fonts.fira_code // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask font-fira-code
}

install_editors() {
  [[ "$(yq -r '.editors.jetbrains_toolbox // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask jetbrains-toolbox
  if [[ "$(yq -r '.editors.intellij_ultimate // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install_cask intellij-idea
  fi
  [[ "$(yq -r '.editors.vscode // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask visual-studio-code
  if [[ "$(yq -r '.editors.xcode // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install mas
    mas install 497799835 || warn "mas: ensure App Store login before installing Xcode"
  fi
}

install_node() {
  if [[ "$(yq -r '.languages.node.manager // "fnm"' "$CONFIG_FILE")" == "fnm" ]]; then
    brew_install fnm
    add_to_shell_rc 'eval "$(fnm env --use-on-cd --shell=zsh)"'
    local versions default
    versions=$(yq -r '.languages.node.versions[]? // empty' "$CONFIG_FILE")
    default=$(yq -r '.languages.node.default // "lts"' "$CONFIG_FILE")
    if [[ -z "$versions" ]]; then versions="lts"; fi
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      info "fnm install $v"
      fnm install "$v" || warn "fnm failed for $v"
    done <<< "$versions"
    info "fnm default $default"
    fnm default "$default" || true
    eval "$(fnm env --use-on-cd --shell=zsh)"
    # Globals
    local globals
    globals=$(yq -r '.languages.node.globals[]? // empty' "$CONFIG_FILE")
    if [[ -n "$globals" ]]; then
      info "Installing global npm packages..."
      while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if npm list -g --depth=0 "$pkg" >/dev/null 2>&1; then
          ok "npm global already: $pkg"
        else
          npm install -g "$pkg" || warn "npm global failed: $pkg"
        fi
      done <<< "$globals"
    fi
  else
    warn "Only 'fnm' flow is implemented robustly; adjust config if needed."
  fi
}

install_python() {
  local use_pyenv
  use_pyenv=$(yq -r '.languages.python.use_pyenv // true' "$CONFIG_FILE")
  brew_install python@3.12 || true # base python
  brew_install pipx

  if [[ "$use_pyenv" == "true" ]]; then
    brew_install pyenv
    add_to_shell_rc 'export PYENV_ROOT="$HOME/.pyenv"'
    add_to_shell_rc 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
    add_to_shell_rc 'eval "$(pyenv init -)"'
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    local versions
    versions=$(yq -r '.languages.python.versions[]? // empty' "$CONFIG_FILE")
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      if pyenv versions --bare | grep -qx "$v"; then
        ok "pyenv version present: $v"
      else
        info "pyenv install $v (this may take a while)"
        CFLAGS="-I$(xcrun --show-sdk-path)/usr/include" pyenv install "$v" || warn "pyenv install failed: $v"
      fi
    done <<< "$versions"
    if [[ -n "$versions" ]]; then
      local first
      first="$(printf "%s\n" "$versions" | head -n1)"
      pyenv global "$first" || true
    fi
  fi

  # pipx packages
  local pkgs
  pkgs=$(yq -r '.languages.python.pipx[]? // empty' "$CONFIG_FILE")
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if pipx list 2>/dev/null | grep -q "package $p "; then
      ok "pipx already: $p"
    else
      info "pipx install $p"
      pipx install "$p" || warn "pipx failed: $p"
    fi
  done <<< "$pkgs"
}

install_java() {
  local versions tools
  versions=$(yq -r '.languages.java.temurin_versions[]? // empty' "$CONFIG_FILE")
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    if [[ "$v" == "21" ]]; then brew_install_cask temurin; fi
    if [[ "$v" == "17" ]]; then brew_install_cask temurin@17; fi
  done <<< "$versions"
  tools=$(yq -r '.languages.java.build_tools[]? // empty' "$CONFIG_FILE")
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    brew_install "$t"
  done <<< "$tools"
}

install_go()   { [[ "$(yq -r '.languages.go // false' "$CONFIG_FILE")" == "true" ]] && brew_install go; }
install_rust() {
  if [[ "$(yq -r '.languages.rust // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install rustup-init
    if [[ ! -x "$HOME/.cargo/bin/rustc" ]]; then
      info "Installing Rust toolchain (stable)..."
      rustup-init -y || true
      add_to_shell_rc 'export PATH="$HOME/.cargo/bin:$PATH"'
    fi
  fi
}

install_web_tooling() {
  if [[ "$(yq -r '.web_tooling.angular_cli // false' "$CONFIG_FILE")" == "true" ]]; then
    npm list -g @angular/cli >/dev/null 2>&1 || npm install -g @angular/cli || warn "Failed: @angular/cli"
  fi
  if [[ "$(yq -r '.web_tooling.react_tooling // false' "$CONFIG_FILE")" == "true" ]]; then
    npm list -g vite >/dev/null 2>&1 || npm install -g vite || true
    npm list -g create-next-app >/dev/null 2>&1 || npm install -g create-next-app || true
  fi
  if [[ "$(yq -r '.web_tooling.typescript // false' "$CONFIG_FILE")" == "true" ]]; then
    npm list -g typescript >/dev/null 2>&1 || npm install -g typescript || true
  fi
  if [[ "$(yq -r '.web_tooling.tailwind // false' "$CONFIG_FILE")" == "true" ]]; then
    npm list -g tailwindcss >/dev/null 2>&1 || npm install -g tailwindcss || true
  fi
}

install_devops() {
  case "$(yq -r '.devops.docker // "none"' "$CONFIG_FILE")" in
    docker-desktop) brew_install_cask docker ;;
    colima) brew_install colima; brew_install docker ;;
    none|*) ;;
  esac

  local ktools
  ktools=$(yq -r '.devops.kubernetes[]? // empty' "$CONFIG_FILE")
  while IFS= read -r kt; do
    [[ -z "$kt" ]] && continue
    brew_install "$kt"
  done <<< "$ktools"

  local iac
  iac=$(yq -r '.devops.iac[]? // empty' "$CONFIG_FILE")
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    brew_install "$t"
  done <<< "$iac"

  local clouds
  clouds=$(yq -r '.devops.cloud_clis[]? // empty' "$CONFIG_FILE")
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    brew_install "$c"
  done <<< "$clouds"
}

install_databases() {
  local servers clis guis
  servers=$(yq -r '.databases.servers[]? // empty' "$CONFIG_FILE")
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    brew_install "$s"
  done <<< "$servers"

  clis=$(yq -r '.databases.clients_cli[]? // empty' "$CONFIG_FILE")
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    brew_install "$s"
  done <<< "$clis"

  guis=$(yq -r '.databases.clients_gui[]? // empty' "$CONFIG_FILE")
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    case "$g" in
      dbeaver) brew_install_cask dbeaver-community ;;
      tableplus) brew_install_cask tableplus ;;
      postico) brew_install_cask postico ;;
      sequel-ace) brew_install_cask sequel-ace ;;
      beekeeper) brew_install_cask beekeeper-studio ;;
      *) warn "Unknown DB GUI: $g" ;;
    esac
  done <<< "$guis"
}

install_productivity() {
  [[ "$(yq -r '.productivity.raycast // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask raycast
  [[ "$(yq -r '.productivity.rectangle // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask rectangle
  [[ "$(yq -r '.productivity.slack // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask slack
  [[ "$(yq -r '.productivity.zoom // false' "$CONFIG_FILE")" == "true" ]] && brew_install_cask zoom
}

install_extras() {
  [[ "$(yq -r '.extras.shellcheck // false' "$CONFIG_FILE")" == "true" ]] && brew_install shellcheck
  [[ "$(yq -r '.extras.shfmt // false' "$CONFIG_FILE")" == "true" ]] && brew_install shfmt
  [[ "$(yq -r '.extras.pre_commit // false' "$CONFIG_FILE")" == "true" ]] && brew_install pre-commit
  [[ "$(yq -r '.extras.direnv // false' "$CONFIG_FILE")" == "true" ]] && brew_install direnv
  [[ "$(yq -r '.extras.jq // false' "$CONFIG_FILE")" == "true" ]] && brew_install jq
  [[ "$(yq -r '.extras.yq // false' "$CONFIG_FILE")" == "true" ]] && brew_install yq
  [[ "$(yq -r '.extras.httpie // false' "$CONFIG_FILE")" == "true" ]] && brew_install httpie
  [[ "$(yq -r '.extras.wget // false' "$CONFIG_FILE")" == "true" ]] && brew_install wget
}

setup_github() {
  if [[ "$(yq -r '.github.install_gh_cli // true' "$CONFIG_FILE")" == "true" ]]; then
    brew_install gh
  fi

  # Git config
  if [[ "$(yq -r '.github.git.set_name_email // false' "$CONFIG_FILE")" == "true" ]]; then
    local name email
    name=$(yq -r '.github.git.name // ""' "$CONFIG_FILE")
    email=$(yq -r '.github.git.email // ""' "$CONFIG_FILE")
    if [[ -n "$name" && -n "$email" ]]; then
      git config --global user.name "$name"
      git config --global user.email "$email"
      ok "Configured git user: $name <$email>"
    fi
  fi

  # Auth
  local method token_env
  method=$(yq -r '.github.auth.method // "device"' "$CONFIG_FILE")
  token_env=$(yq -r '.github.auth.token_env // "GH_TOKEN"' "$CONFIG_FILE")
  if [[ "$method" == "token" ]]; then
    local token="${!token_env:-}"
    if [[ -n "$token" ]]; then
      info "Authenticating gh via token env $token_env"
      printf "%s" "$token" | gh auth login --with-token || warn "gh auth via token failed"
    else
      warn "No token found in $token_env; skipping gh token auth"
    fi
  elif [[ "$method" == "device" ]]; then
    info "gh auth login (device flow). You may be prompted in browser."
    gh auth login || warn "gh device auth skipped/failed"
  fi

  # SSH
  if [[ "$(yq -r '.github.ssh.generate // false' "$CONFIG_FILE")" == "true" ]]; then
    local key_type comment
    key_type=$(yq -r '.github.ssh.key_type // "ed25519"' "$CONFIG_FILE")
    comment=$(yq -r '.github.ssh.comment // "macos-sh-scripts"' "$CONFIG_FILE")
    mkdir -p "$HOME/.ssh"
    local keyfile="$HOME/.ssh/id_${key_type}"
    if [[ -f "$keyfile" ]]; then
      ok "SSH key exists: $keyfile"
    else
      info "Generating SSH key: $keyfile"
      ssh-keygen -t "$key_type" -C "$comment" -f "$keyfile" -N "" || warn "ssh-keygen failed"
      eval "$(ssh-agent -s)"
      ssh-add "$keyfile" || true
      if [[ "$(yq -r '.github.ssh.upload_to_github // false' "$CONFIG_FILE")" == "true" ]]; then
        if command -v gh >/dev/null 2>&1; then
          gh ssh-key add "${keyfile}.pub" --title "$comment" || warn "Failed to upload SSH key via gh"
        fi
      fi
    fi
  fi
}

install_ai() {
  if [[ "$(yq -r '.ai.aider // false' "$CONFIG_FILE")" == "true" ]]; then
    pipx list 2>/dev/null | grep -q "package aider-chat " || pipx install aider-chat || warn "aider install failed"
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
      warn "ANTHROPIC_API_KEY not set. Add it to your .env for Aider."
    fi
  fi
  if [[ "$(yq -r '.ai.gh_copilot_cli // false' "$CONFIG_FILE")" == "true" ]]; then
    if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
      ok "gh-copilot already installed"
    else
      gh extension install github/gh-copilot || warn "Failed installing gh-copilot"
    fi
  fi
  if [[ "$(yq -r '.ai.llm_cli // false' "$CONFIG_FILE")" == "true" ]]; then
    pipx list 2>/dev/null | grep -q "package llm " || pipx install llm || true
    llm install llm-anthropic || true
  fi
}

install_brew_section_overrides() {
  # custom taps
  yq -r '.brew.taps[]? // empty' "$CONFIG_FILE" | while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if brew tap | grep -q "^${t}$"; then ok "tap already: $t"; else brew tap "$t"; fi
  done
  # custom formulae
  yq -r '.brew.formulae[]? // empty' "$CONFIG_FILE" | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    brew_install "$f"
  done
  # custom casks
  yq -r '.brew.casks[]? // empty' "$CONFIG_FILE" | while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    brew_install_cask "$c"
  done
}

install_app_store() {
  if [[ "$(yq -r '.app_store.enabled // false' "$CONFIG_FILE")" == "true" ]]; then
    brew_install mas
    yq -r '.app_store.apps[]? | "\(.id) \(.name)"' "$CONFIG_FILE" | while read -r id name; do
      if mas list | awk '{print $1}' | grep -qx "$id"; then
        ok "mas app already installed: $name ($id)"
      else
        info "mas install $name ($id)"
        mas install "$id" || warn "mas install failed: $name ($id). Ensure App Store login."
      fi
    done
  fi
}

load_env() {
  if [[ -f ".env" ]]; then
    # shellcheck disable=SC2046
    set -a; source ".env"; set +a
    ok "Loaded environment variables from .env"
  fi
}

main() {
  : > "$LOG_FILE"
  bold "macOS Fullstack Developer Setup"
  info "Config: $CONFIG_FILE"
  load_env

  # Ensure core tooling before reading YAML
  ensure_brew
  ensure_yq_jq

  # Now we can safely read config and perform OS-specific items
  ensure_xcode_clt
  ensure_rosetta

  setup_github
  install_browsers
  install_terminal_stack
  install_editors

  install_node
  install_python
  install_java
  install_go
  install_rust
  install_web_tooling
  install_devops
  install_databases
  install_productivity
  install_extras
  install_ai

  install_brew_section_overrides
  install_app_store

  ok "All done. Open a new terminal to pick up PATH changes. See $LOG_FILE for details."
}

main "$@"