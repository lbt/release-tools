#!/bin/sh
ORIG=$PWD
API=$2
TOOLS=$PWD/tools
RELEASE=$1
RSYNC=$3

# This script creates a mer release intended to appear on http://releases.merproject.org/releases/

# Note that createrelease will take an instantaneous snapshot of the CI OBS - please ensure it is not busy

# It operates within the release-tools directory
# It uses the following subdirs:
#  obs-projects/
#    This contains the obs project metadata - it's used to obtain the group data to build the repos
# It updates the following subdirs:
#  obs-repos/
#    This is a mirror of the OBS built rpms and some useful OBS state (such as solvstate)
#    It's a transient holding directory as rpms are transferred to the correct structure in ...
#  releases/
#    This area contains the completed release ready to be rsync'ed to the public server

# Additional controls
#
# Set SKIPWGET to skip pulling from the OBS to obs-repos
# Set RESYNC to only redo the rsync
# Set PRERELEASE to skip updating the "latest" links
# Set NORSYNC to skip the push to public servers
# Set NOGRAB to skip the restructuring into the releases/ area

if [ x$1 = x -o x$2 = x -o x$3 = x ]; then
    echo Syntax: tools/createrelease.sh RELEASE OBSAPI RSYNCURL
    exit 0
fi

if [ x$RESYNC = x -a x$SKIPWGET = x ]; then
    # If a dumpbuild fails, abort
    set -e
    $TOOLS/dumpbuild "$API" "Core:i586" Core:i586:$RELEASE Core_i586 "i586"
    $TOOLS/dumpbuild "$API" "Core:i486" Core:i486:$RELEASE Core_i486 "i586"
    $TOOLS/dumpbuild "$API" "Core:armv7l" Core:armv7l:$RELEASE Core_armv7l "i586 armv7el"
    $TOOLS/dumpbuild "$API" "Core:armv7hl" Core:armv7hl:$RELEASE Core_armv7hl "i586 armv8el"
    $TOOLS/dumpbuild "$API" "Core:armv6l" Core:armv6l:$RELEASE Core_armv6l "i586 armv7el"
    $TOOLS/dumpbuild "$API" "Core:mipsel" Core:mipsel:$RELEASE Core_mipsel "i586 mips"
    set +e
fi
if [ x$PRERELEASE = x ]; then

    rm -f obs-repos/Core:i586:latest obs-repos/Core:i486:latest obs-repos/Core:armv7l:latest obs-repos/Core:armv7hl:latest obs-repos/Core:armv6l:latest obs-repos/Core:mipsel:latest 
    ln -s Core:i586:$RELEASE obs-repos/Core:i586:latest
    ln -s Core:i486:$RELEASE obs-repos/Core:i486:latest
    ln -s Core:armv7l:$RELEASE obs-repos/Core:armv7l:latest
    ln -s Core:armv7hl:$RELEASE obs-repos/Core:armv7hl:latest
    ln -s Core:armv6l:$RELEASE obs-repos/Core:armv6l:latest
    ln -s Core:mipsel:$RELEASE obs-repos/Core:mipsel:latest
else
    rm -f obs-repos/Core:i586:next obs-repos/Core:i486:next obs-repos/Core:armv7l:next obs-repos/Core:armv7hl:next obs-repos/Core:armv6l:next obs-repos/Core:mipsel:next 
    ln -s Core:i586:$RELEASE obs-repos/Core:i586:next
    ln -s Core:i486:$RELEASE obs-repos/Core:i486:next
    ln -s Core:armv7l:$RELEASE obs-repos/Core:armv7l:next
    ln -s Core:armv7hl:$RELEASE obs-repos/Core:armv7hl:next
    ln -s Core:armv6l:$RELEASE obs-repos/Core:armv6l:next
    ln -s Core:mipsel:$RELEASE obs-repos/Core:mipsel:next
fi

grab_build()
{
    SYNCPATH=$1
    NAME=$2
    mkdir -p releases/$RELEASE/builds/$NAME
    cd releases/$RELEASE/builds/$NAME
    mkdir -p packages debug
    cd packages
    echo copying from OBS repo to releases
    rsync  -aHx --verbose $RSYNC/$SYNCPATH/* --exclude=*.src.rpm --exclude=repocache/ --exclude=*.repo --exclude=repodata/ --exclude=src/ --exclude=dontuse/ --include=*.rpm .
    echo removing signatures
    find -name \*.rpm | xargs -L1 rpm --delsign
    mv */*-debuginfo-* ../debug
    mv */*-debugsource-* ../debug
    # Move all cross- gcc/binutils packages to the relevant arch's cross/ area
    case $NAME in
	*86 ) ;;
	* )
	    echo "Preparing /cross"
	    mv  */cross-*{gcc,binutils}*.i486.rpm ../../i486/cross/
	    mv  */cross-*{gcc,binutils}*.i586.rpm ../../i586/cross/
	    ;;
    esac
    # Apply package groups and create repository
    createrepo -g $ORIG/obs-projects/Core/$NAME/group.xml .
    cp $ORIG/obs-projects/Core/$NAME/patterns.xml repodata/
    modifyrepo repodata/patterns.xml repodata/
    # No need for package groups in debug symbolsA
    cd ../debug
    createrepo .
    cd $ORIG
    # Remove confusing empty directories
    cd releases/$RELEASE/builds/$NAME/packages
    rmdir --ignore-fail-on-non-empty *
    cd $ORIG
}

if [ x$RESYNC = x -a x$NO_GRAB = x ]; then
    grab_build Core:/i586/Core_i586 i586
    grab_build Core:/i486/Core_i486 i486 
    mkdir -p releases/$RELEASE/builds/i486/cross
    mkdir -p releases/$RELEASE/builds/i586/cross
    grab_build Core:/armv7l/Core_armv7l armv7l
    grab_build Core:/armv7hl/Core_armv7hl armv7hl
    grab_build Core:/armv6l/Core_armv6l armv6l
    grab_build Core:/mipsel/Core_mipsel mipsel
    # Now update the repo in the cross areas (this will need some grouping generated for easy installation)
    (cd releases/$RELEASE/builds/i486/cross; createrepo .)
    (cd releases/$RELEASE/builds/i586/cross; createrepo .)
fi

if [ x$NORSYNC = x1 ]; then
    exit 0
fi

if [ x$PRERELEASE = x ]; then
    echo $RELEASE > obs-repos/latest.release
    echo $RELEASE > releases/latest-release
    rm releases/latest
    ln -s $RELEASE releases/latest
else
    echo $RELEASE > obs-repos/next.release
    echo $RELEASE > releases/next-release
    rm releases/next
    ln -s $RELEASE releases/next
fi

rsync -aHx --progress obs-repos/Core\:*\:$RELEASE obs-repos/Core\:*\:latest merreleases@monster.tspre.org:~/public_html/obs-repos/
rsync -aHx --progress obs-repos/latest.release obs-repos/next.release merreleases@monster.tspre.org:~/public_html/obs-repos/
rsync -aHx --progress releases/$RELEASE merreleases@monster.tspre.org:~/public_html/releases/
rsync -aHx --progress releases/latest-release releases/latest releases/next-release releases/next merreleases@monster.tspre.org:~/public_html/releases/

exit 0

