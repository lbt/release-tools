#!/bin/sh
ORIG=$PWD
API=$2
TOOLS=$PWD/tools
RELEASE=$1
RSYNC=$3

if [ x$1 = x -o x$2 = x -o x$3 = x ]; then
	echo Syntax: tools/createrelease.sh RELEASE OBSAPI RSYNCURL
	exit 0
fi

$TOOLS/dumpbuild "$API" "Core:i586" Core:i586:$RELEASE Core_i586 "i586"
$TOOLS/dumpbuild "$API" "Core:armv7l" Core:armv7l:$RELEASE Core_armv7l "i586 armv7el"
$TOOLS/dumpbuild "$API" "Core:armv7hl" Core:armv7hl:$RELEASE Core_armv7hl "i586 armv8el"
$TOOLS/dumpbuild "$API" "Core:armv6l" Core:armv6l:$RELEASE Core_armv6l "i586 armv7el"

rm -f obs-repos/Core:i586:latest obs-repos/Core:armv7l:latest obs-repos/Core:armv7hl:latest obs-repos/Core:armv6l:latest
ln -s Core:i586:$RELEASE obs-repos/Core:i586:latest
ln -s Core:armv7l:$RELEASE obs-repos/Core:armv7l:latest
ln -s Core:armv7hl:$RELEASE obs-repos/Core:armv7hl:latest
ln -s Core:armv6l:$RELEASE obs-repos/Core:armv6l:latest


grab_build()
{
	SYNCPATH=$1
	NAME=$2
	mkdir -p releases/$RELEASE/builds/$NAME
	cd releases/$RELEASE/builds/$NAME
	mkdir -p packages debug
	cd packages
	rsync  -aHx --progress $RSYNC/$SYNCPATH/* --exclude=*.src.rpm --exclude=repocache/ --exclude=*.repo --exclude=repodata/ --exclude=src/ --include=*.rpm .
	mv */*-debuginfo-* ../debug
	mv */*-debugsource-* ../debug
	createrepo .
	cd ../debug
#rpm2cpio ./*/package-groups-*.rpm | cpio -vid .
#createrepo -g ./usr/share/package-groups/group.xml .
#rm -rf ./usr
	createrepo .
	cd $ORIG
}

grab_build Core:/i586/Core_i586 i586 
grab_build Core:/armv7l/Core_armv7l armv7l
grab_build Core:/armv7hl/Core_armv7hl armv7hl
grab_build Core:/armv7hl/Core_armv6l armv6l

rsync -aHx --progress obs-repos/Core\:*\:$RELEASE obs-repos/Core\:*\:latest merreleases@monster.tspre.org:~/public_html/obs-repos/
rsync -aHx --progress releases/$RELEASE merreleases@monster.tspre.org:~/public_html/releases/

exit 0