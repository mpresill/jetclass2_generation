#!/bin/bash -e

# Works around a MadGraph5/MadSpin + numpy f2py incompatibility.
#
# MadGraph's standalone f2py Makefile templates invoke f2py with
# `--include-paths=<dir>` (single token, '=' form). The f2py CLI shipped
# with numpy (still true as of numpy 1.23.x) only recognizes the two-token
# form `--include-paths <dir>`; with the '=' form the path is silently
# dropped and, since it is the last argument on the command line, the raw
# flag string is forwarded to distutils as if it were a source file. This
# makes MadSpin's standalone spin-correlated decay matrix elements
# (matrix2py.so, needed whenever madspin=ON with spinmode onshell, e.g. the
# jetclass2/train_zz config) fail to compile with:
#   error: unknown file type '' (from '--include-paths=...')
#
# This script rewrites the '=' to a space in the two affected templates.
# Safe to re-run (idempotent).

MG5_PATH=${1:-$MG5_PATH}
if [ -z "$MG5_PATH" ] || [ ! -d "$MG5_PATH" ]; then
    echo "Usage: $0 /path/to/MG5_aMC_vX_Y_Z   (or export MG5_PATH first)" >&2
    exit 1
fi

TEMPL_DIR="$MG5_PATH/madgraph/iolibs/template_files"
patched=0
for f in makefile_sa_f_sp makefile_sa_f2py; do
    target="$TEMPL_DIR/$f"
    if [ ! -f "$target" ]; then
        echo "Warning: $target not found, skipping" >&2
        continue
    fi
    if grep -q -- '--include-paths=\$(HERE)' "$target"; then
        sed -i 's/--include-paths=\$(HERE)/--include-paths \$(HERE)/g' "$target"
        echo "Patched $target"
        patched=$((patched + 1))
    else
        echo "$target already patched, skipping"
    fi
done

if [ "$patched" -eq 0 ]; then
    echo "No files needed patching."
fi
