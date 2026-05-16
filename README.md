# dotfiles

Aaron Walker's dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## What's tracked

| Package | Source | Symlink target |
|---------|--------|----------------|
| `claude` | `.dotfiles/claude/.claude/skills/` | `~/.claude/skills/` |

Project-specific memory files live in their own repos and are symlinked separately (see below).

---

## New machine setup

### 1. Prerequisites

```bash
brew install stow git gh
```

### 2. Clone this repo

```bash
git clone https://github.com/busukajw/dotfiles.git ~/.dotfiles
```

### 3. Stow packages

```bash
cd ~/.dotfiles
stow -t ~ claude
```

This creates `~/.claude/skills/` → `~/.dotfiles/claude/.claude/skills/`.

### 4. Project memory symlinks

Memory files are tracked in their project repos, not here. Recreate the symlinks manually:

**Home Automation**
```bash
# Clone the project repo if not already present
git clone https://github.com/busukajw/Home_Automation.git ~/Documents/CLAUDE/Home_Automation

# Create the symlink
ln -s ~/Documents/CLAUDE/Home_Automation/.claude/memory \
  ~/.claude/projects/-Users-awalker-Documents-CLAUDE-Home-Automation/memory
```

> Note: the `~/.claude/projects/` directory name is a sanitised version of the project
> path. If the project lives somewhere else on a new machine, adjust accordingly.

---

## Day-to-day usage

Skills are edited in place via `~/.claude/skills/` (the symlink). To save changes:

```bash
cd ~/.dotfiles
git add -A
git commit -m "update skills"
git push
```

## Adding a new package

```bash
mkdir -p ~/.dotfiles/<package>/<path/relative/to/home>
# move files in, then:
cd ~/.dotfiles && stow -t ~ <package>
```
