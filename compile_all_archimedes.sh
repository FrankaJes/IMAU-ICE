#!/bin/sh

# If modules and objects folders do not exist, create them
mkdir -p src/module-files
mkdir -p src/object-files

# Go to src/, make, and come back
cd src
make all
cd ..

# Update program
rm -f IMAU_ICE_program
mv src/IMAU_ICE_program .
