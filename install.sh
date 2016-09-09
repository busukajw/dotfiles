#!/usr/bin/env bash

#Initial install of Dotfiles
# Assumes that MacPorts is installed and you have installed coreutils
actual_path=$(greadlink -f "${BASH_SOURCE[0]}")
DOTFILES_DIR=$(dirname "$actual_path")

#install the initial symlinks

ln -sfv "$DOTFILES_DIR/runcom/.bash_profile" ~
ln -sfv "$DOTFILES_DIR/runcom/.inputrc" ~
ln -sfv "$DOTFILES_DIR/tmux/.tmux.conf" ~
ln -sfv "$DOTFILES_DIR/vim/.vimrc" ~
ln -sfv "$DOTFILES_DIR/git/.gitignore_global" ~
ln -svf "$DOTFILES_DIR/git/.gitconfig" ~
