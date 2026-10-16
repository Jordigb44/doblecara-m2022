#!/bin/bash
# Doble clic para instalar (o actualizar) Doble Cara M2022
cd "$(dirname "$0")"
./install.sh 2>&1 | tee instalar.log
echo; echo "Abriendo la app…"
open "$HOME/Applications/Doble Cara M2022.app"
