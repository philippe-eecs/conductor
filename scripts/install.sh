#!/bin/bash
# Install to ~/Applications
./scripts/build-app.sh
cp -r build/Conductor.app ~/Applications/
echo "Installed to ~/Applications/Conductor.app"
