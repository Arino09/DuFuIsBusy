#!/usr/bin/env bash
set -euo pipefail
version=4.7.2
install_dir="${RUNNER_TEMP:-/tmp}/dufu-godot"
mkdir -p "$install_dir" "$HOME/.local/share/godot/export_templates/$version.stable"
base="https://github.com/godotengine/godot-builds/releases/download/$version-stable"
for archive in "Godot_v${version}-stable_linux.x86_64.zip" "Godot_v${version}-stable_export_templates.tpz"; do
  curl --fail --location --retry 3 "$base/$archive" --output "$install_dir/$archive"
done
curl --fail --location --retry 3 "$base/SHA512-SUMS.txt" --output "$install_dir/SHA512-SUMS.txt"
(cd "$install_dir" && sha512sum --check --ignore-missing SHA512-SUMS.txt)
unzip -q -o "$install_dir/Godot_v${version}-stable_linux.x86_64.zip" -d "$install_dir"
unzip -q -o "$install_dir/Godot_v${version}-stable_export_templates.tpz" -d "$install_dir"
cp "$install_dir/templates/"* "$HOME/.local/share/godot/export_templates/$version.stable/"
chmod +x "$install_dir/Godot_v${version}-stable_linux.x86_64"
ln -sf "$install_dir/Godot_v${version}-stable_linux.x86_64" "$install_dir/godot"
echo "$install_dir" >> "$GITHUB_PATH"
