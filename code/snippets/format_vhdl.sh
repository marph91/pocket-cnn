#!/bin/bash

FILES=$(find "${1-.}" -name "*.vhd")
FILE_CNT=$(echo -n "$FILES" | grep -c "^")

for f in $FILES; do
    # replace all tabs by 2 white spaces
    # simple > would overwrite the file too fast
    expand -t 2 "$f" | sponge "$f"

    # remove trailing whitespaces
    sed -i "s/[[:space:]]*$//" "$f"
done

echo "$FILE_CNT files formatted."