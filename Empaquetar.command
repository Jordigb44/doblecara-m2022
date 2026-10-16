#!/bin/bash
# Doble clic para generar dist/ con el .dmg y el .zip para distribuir
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
./app/package.sh "$VERSION" 2>&1 | tee empaquetar.log
