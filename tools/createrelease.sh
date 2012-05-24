#!/bin/bash
ORIG=$PWD
TOOLS=$PWD/tools

RELEASE=$1

# Get Project configuration
. tools/release.conf

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

build2repo()
{
    # This gets binary rpms from the build RSYNC source path passed into the main script
    # removes signatures, tweaks debug* things, handles -cross and makes the repositories
    # eg : rsync://be.example.com/obsrepos
    # It takes 4 args:
    RSYNCPATH=$1   # Path to the rpms
    NAME=$2       # The architecture name
    GROUPXML=$3
    PATTERNXML=$4

    # Phase 1 : get and prepare rpms
    mkdir -p releases/$RELEASE/builds/$NAME/{packages,debug}
    echo copying from OBS repo to releases
    rsync  -aHx --verbose $RSYNCPATH/* --exclude=*.src.rpm --exclude=repocache/ --exclude=*.repo --exclude=repodata/ --exclude=src/ --exclude=dontuse/ --include=*.rpm releases/$RELEASE/builds/$NAME/packages/


    echo removing signatures
    find releases/$RELEASE/builds/$NAME/packages/ -name \*.rpm | xargs -L1 rpm --delsign
    mv releases/$RELEASE/builds/$NAME/packages/*/*-debug{info,source}-* releases/$RELEASE/builds/$NAME/debug/

    # Move all cross- gcc/binutils packages to the relevant arch's cross/ area
    case $NAME in
	*86* ) ;; # Ignore cross for i{3,4,5,6}86 and x86_64 ?
	* )
	    echo "Preparing /cross" # This may need to be handled better with x86_64 etc
	    mv releases/$RELEASE/builds/$NAME/packages/*/cross-*{gcc,binutils}*.i{4,5}86.rpm releases/$RELEASE/builds/i486/cross/
	    ;;
    esac
    # Phase 2 : Apply package groups and create repository
    if [ -e $GROUPXML ] ; then
	createrepo -g $GROUPXML releases/$RELEASE/builds/$NAME/packages/
    else
	createrepo releases/$RELEASE/builds/$NAME/packages/
    fi
    [ -e $PATTERNXML ] && {
	cp $PATTERNXML releases/$RELEASE/builds/$NAME/packages/repodata/
	modifyrepo releases/$RELEASE/builds/$NAME/packages/repodata/patterns.xml releases/$RELEASE/builds/$NAME/packages/repodata/
    }
    # No need for package groups in debug symbols
    createrepo releases/$RELEASE/builds/$NAME/debug/
    # Remove confusing empty directories
    rmdir --ignore-fail-on-non-empty releases/$RELEASE/builds/$NAME/packages/*
}

################

if [ x$1 = x ]; then
    echo Syntax: tools/createrelease.sh RELEASE
    exit 0
fi

if [ x$RESYNC = x -a x$SKIPWGET = x ]; then
    # If a dumpbuild fails, abort
    while read project repo arch scheds ; do
	echo "Get OBS build for $project with repo $repo for $scheds"
	set -e
	$TOOLS/dumpbuild "$API" "$project" ${project}:$RELEASE $repo $scheds
	set +e
    done <<< $PROJECTS
fi

while read project repo arch scheds ; do
    if [ x$PRERELEASE = x ]; then
	echo "Make latest for $project"
	rm -f obs-repos/${project}:latest
	ln -s ${project}:$RELEASE obs-repos/${project}:latest
    else
	echo "Make next for $project"
	rm -f obs-repos/${project}:next
	ln -s ${project}:$RELEASE obs-repos/${project}:next
    fi
done <<< $PROJECTS


if [ x$RESYNC = x -a x$NO_GRAB = x ]; then
    if [[ $CROSS ]]; then
	mkdir -p releases/$RELEASE/builds/i486/cross
	mkdir -p releases/$RELEASE/builds/i586/cross
    fi
    while read project repo arch scheds ; do
	echo "Make repos for $project"
	projdir=${project//:/:\/}
	build2repo $RSYNC/${projdir}/$repo $arch $ORIG/obs-projects/Core/$NAME/group.xml $ORIG/obs-projects/Core/$NAME/patterns.xml
        # Now update the repo in the cross areas (this will need some grouping generated for easy installation)
    done <<< $PROJECTS
    if [[ $CROSS ]]; then
	createrepo releases/$RELEASE/builds/i486/cross
	createrepo releases/$RELEASE/builds/i586/cross
    fi
fi

if [ x$NORSYNC = x1 ]; then
    exit 0
fi

if [ x$PRERELEASE = x ]; then
    echo $RELEASE > obs-repos/latest.release
    echo $RELEASE > releases/latest-release
    rm -f releases/latest
    ln -s $RELEASE releases/latest
else
    echo $RELEASE > obs-repos/next.release
    echo $RELEASE > releases/next-release
    rm -f releases/next
    ln -s $RELEASE releases/next
fi

rsync -aHx --progress obs-repos/Core\:*\:$RELEASE obs-repos/Core\:*\:latest merreleases@monster.tspre.org:~/public_html/obs-repos/
rsync -aHx --progress obs-repos/latest.release obs-repos/next.release merreleases@monster.tspre.org:~/public_html/obs-repos/
rsync -aHx --progress releases/$RELEASE merreleases@monster.tspre.org:~/public_html/releases/
rsync -aHx --progress releases/latest-release releases/latest releases/next-release releases/next merreleases@monster.tspre.org:~/public_html/releases/

exit 0

