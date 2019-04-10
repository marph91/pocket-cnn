files=$(find . -name "*.vhd")

for f in $files; do
    echo "$f"

    # replace all tabs by 2 white spaces
    # simple > would overwrite the file too fast
    expand -t 2 "$f" | sponge "$f"

    # remove trailing whitespaces
    sed -i 's/[[:space:]]*$//' "$f"
done