#!/bin/bash
set -e

WORKSPACE=/workspace

git config --add --global safe.directory $WORKSPACE
make venv
cat $WORKSPACE/.devcontainer/bashrc_additions >> ~/.bashrc