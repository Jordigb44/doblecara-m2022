#!/bin/bash
# Desinstala DobleCaraM2022
set -u
rm -rf "$HOME/Library/Application Support/DobleCaraM2022"
rm -f  "$HOME/Library/PDF Services/Doble cara manual (Samsung M2022)"
rm -f  "$HOME/Library/PDF Services/Doble cara manual (M2022)"
rm -rf "$HOME/Applications/Doble Cara M2022.app"
rm -f  "$HOME/.local/bin/doblecara"
echo "✔ DobleCaraM2022 desinstalado. (~/.config/doblecara-m2022.conf se conserva si existe)"
