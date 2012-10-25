#!/bin/bash

if [ "$1" = '-h' ]; then

	echo ''
	echo 'Release Process:'
	echo 'git tag -a r0.9.2 -m "built"'
	echo './gen_release.sh'
	echo 'git push --tags'
	echo 'then upload files to code.google.com/p/newsman-news-tool/'
	echo ''
	exit 2	
fi

FNR=$(git tag -l 'r*' | tail -n 1)
FN=${FNR#r}

mkdir releases 2>/dev/null

echo "Creating the $FN src release..."
rm -f releases/*.tar.gz
tar -c --owner=root --group=root -f releases/newsman-$FN.tar src/
gzip releases/newsman-$FN.tar

echo "Creating the $FN deb release..."
rm -rf tmp_deb/
rm -f releases/*.deb
cp -r debian_package/ tmp_deb/

echo "Installed-Size: $(du -b tmp_deb/ -c | tail -n 1 | awk '{print $1}')">> tmp_deb/DEBIAN/control
mkdir -p tmp_deb/usr/bin/
cp src/newsman.pl tmp_deb/usr/bin/newsman

echo "Version: $FN" >> tmp_deb/DEBIAN/control
dpkg --build tmp_deb/ releases/
echo "Made $FN."
