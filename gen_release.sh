#!/bin/bash

#git tag -a $1 -m "$2"
FN=$(git tag)

echo "Creating the $FN src release..."
rm -f releases/*.tar.gz
tar -c --owner=root --group=root -f releases/newsman-$FN.tar src/
gzip releases/newsman-$FN.tar

echo "Creating the $FN deb release..."
rm -rf tmp_deb/
rm -f releases/*.deb
cp -r debian_package/ tmp_deb/
mkdir -p tmp_deb/usr/bin/
cp src/newsman.pl tmp_deb/usr/bin/newsman
echo "Version: $FN" >> tmp_deb/DEBIAN/control
dpkg --build tmp_deb/ releases/
echo "Made $FN."
