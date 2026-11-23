#!/bin/sh
# fetch_archive.sh [DIR]: downloads Levent Alpöge's Lean archive from alpo.ge (14 parts), checks the concatenation
# against the sha256 this replay used, and extracts it into DIR (default ./archive). The archive is his work and is
# not part of this repository.
set -eu
D=${1:-archive}; SUM=9631b4f020199e580ba86178cb56c6e9b09f690c2369a80dc4334aa93f49c7fc
mkdir -p "$D/parts"
i=1
while [ "$i" -le 14 ]; do
  p=$(printf 'lean.tar.gz.part%02d' "$i")
  [ -s "$D/parts/$p" ] || curl -fL --retry 3 -o "$D/parts/$p.tmp" "https://alpo.ge/$p"
  [ -s "$D/parts/$p.tmp" ] && mv "$D/parts/$p.tmp" "$D/parts/$p"
  i=$((i + 1))
done
cat "$D"/parts/lean.tar.gz.part?? > "$D/lean.tar.gz"
echo "$SUM  $D/lean.tar.gz" | sha256sum -c - || { echo "fetch_archive: sha256 differs from the replayed archive" >&2; exit 1; }
tar -xzf "$D/lean.tar.gz" -C "$D"
echo "extracted into $D"
