#!/usr/bin/env bash
set -euo pipefail

# Install only the notebook's isolated environment and two frozen plugin copies.
# Existing global/Conda environments and unrelated plugin locks are untouched.
runtime_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
venv_dir="$data_dir/glow-notebook-venv"
command -v uv >/dev/null || { printf '%s\n' 'Install uv before preparing the Notebook runtime.' >&2; exit 1; }

if [[ ! -x "$venv_dir/bin/python" ]]; then
  uv venv --python 3.12 "$venv_dir"
fi
uv pip sync --python "$venv_dir/bin/python" "$runtime_dir/requirements.txt"
"$venv_dir/bin/python" -m ipykernel install --prefix "$venv_dir" --name glow-python --display-name 'Neovide Glow Python'

install_plugin() {
  local repository="$1" name="$2" commit="$3" destination="$data_dir/lazy/$2"
  if [[ ! -d "$destination" ]]; then
    git clone --filter=blob:none --no-checkout "https://github.com/$repository.git" "$destination"
  fi
  if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
    printf 'Preserving local changes in %s; restore the pinned commit manually.\n' "$destination" >&2
    exit 1
  fi
  if ! git -C "$destination" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$destination" fetch origin "$commit"
  fi
  git -C "$destination" checkout --detach "$commit"
}

install_plugin benlubas/molten-nvim molten-nvim bedea63819c618e007e7c40059fc6e72d598c8df
install_plugin GCBallesteros/jupytext.nvim jupytext.nvim c8baf3ad344c59b3abd461ecc17fc16ec44d0f7b
printf '%s\n' 'Runtime prepared. With the Glow Notebook config loaded, run :UpdateRemotePlugins once and restart Neovim.'
