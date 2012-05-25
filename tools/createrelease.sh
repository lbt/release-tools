#!/bin/bash
ORIG=$PWD
TOOLS=$PWD/tools

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

usage()
{
    cat <<EOF
    usage: $1 [ --latest | --next ] [--all |  --get-from-obs | --make-repos | --publish ] ] <release>

     Create a repository and MDS release from an OBS project and OBS project repo
     There are 3 steps

     Specify which steps (one of the following only):
       --get-from-obs  : Just do the OBS pull and populate ./obs-repos from the OBS API
       --make-repos    : Just make the zypper repositories from ./obs-repos -> ./releases
       --publish       : Just publish via rsync

     To perform all the steps (normal use)
       --all           : Normal release, perform all the steps


     Optionally a symbolic link to 'latest' or 'next' can be made:
       --latest        : Make 'latest' point to the new release
       --next          : Make 'next' point to the new release

       <release>
EOF
    return 0
}

# Defaults
PRERELEASE=
GET_FROM_OBS=1
MAKE_REPOS=1
PUBLISH=1

# Must specify STEPS
STEPS=

while [[ $1 ]] ; do
    case $1 in
	--latest ) PRERELEASE=latest;;
	--next   ) PRERELEASE=next;;

	--all ) if [[ $STEPS ]]; then usage; exit 1; fi
	    GET_FROM_OBS=1; MAKE_REPOS=1; PUBLISH=1 ;   STEPS=1 ;;

	--get-from-obs ) if [[ $STEPS ]]; then usage; exit 1; fi
	    GET_FROM_OBS=1; MAKE_REPOS= ; PUBLISH=   ;   STEPS=1 ;;

	--make-repos ) if [[ $STEPS ]]; then usage; exit 1; fi
	    GET_FROM_OBS= ; MAKE_REPOS=1; PUBLISH=   ;   STEPS=1 ;;

	--publish ) if [[ $STEPS ]]; then usage; exit 1; fi
	    GET_FROM_OBS= ; MAKE_REPOS= ; PUBLISH=1 ;   STEPS=1 ;;

	* ) if [[ $RELEASE ]]; then usage; exit 1; fi
	    RELEASE=$1 ;;
    esac
    shift
done

if [[ -z $STEPS ]]; then usage; exit 1; fi
if [[ -z $RELEASE ]]; then usage; exit 1; fi

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

dumpbuild ()
{
    API=$1
    OBSPROJECT=$2
    OUTDIR=$3
    REPONAME=$4
    IFS=: read -ra SCHEDULERS <<< $5 # : seperated list of architectures in $5

    [[ -d obs-repos/$OUTDIR ]] && {
	echo "obs-repos/$OUTDIR exists already. Looks like you already fetched this release from OBS"
	echo 'remove the obs-repos/*$RELEASE directories manually if you need to re-fetch'
	exit 1
    }

    wget_opts="-q --no-check-certificate -N -c -r -nd -nH -p"
    for scheduler in "${SCHEDULERS[@]}"; do
	baseurl=$API/build/$OBSPROJECT/$REPONAME/$scheduler
	targetdir=obs-repos/$OUTDIR/$REPONAME/$scheduler
	mkdir -p $targetdir
	echo Getting metadata for $scheduler
	wget $wget_opts -P $targetdir $baseurl/_repository?view=cache
	wget $wget_opts -P $targetdir $baseurl/_repository?view=names
	wget $wget_opts -P $targetdir $baseurl/_repository?view=binaryversions
	wget $wget_opts -P $targetdir $baseurl/_repository?view=solvstate
	echo Getting binaries for $scheduler
	python $ORIG/tools/printbinaries.py "$targetdir/_repository?view=names" | while read -r binaries ; do
	    curl -sS "$baseurl/_repository?$binaries" | (cd $targetdir; cpio -idvm)
	done
    done
}

################

# Step 1 : Get from OBS and update latest/next obs-repo
if [[ $GET_FROM_OBS ]]; then
    # If a dumpbuild fails, abort
    while read project repo arch scheds ; do
	echo "Get OBS build for $project with repo $repo for $scheds"
	set -e
	dumpbuild "$API" "$project" ${project}:$RELEASE $repo $scheds
	set +e
    done <<< $PROJECTS

    if [[ $PRERELEASE ]]; then
	while read project repo arch scheds ; do
	    echo "Make $PRERELEASE for $project"
	    rm -f obs-repos/${project}:$PRERELEASE
	    ln -s ${project}:$RELEASE obs-repos/${project}:$PRERELEASE
	done <<< $PROJECTS
    fi
fi

# Step 2: Make repos in release area
if [[ $MAKE_REPOS ]]; then
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

    if [[ $PRERELEASE ]]; then
	echo $RELEASE > obs-repos/$PRERELEASE.release
	echo $RELEASE > releases/$PRERELEASE-release
	rm -f releases/$PRERELEASE
	ln -s $RELEASE releases/$PRERELEASE
    fi
fi

# Step 3: Publish
if [[ $PUBLISH ]]; then

#rsync -aHx --progress obs-repos/Core\:*\:$RELEASE obs-repos/Core\:*\:latest merreleases@monster.tspre.org:~/public_html/obs-repos/
#rsync -aHx --progress obs-repos/latest.release obs-repos/next.release merreleases@monster.tspre.org:~/public_html/obs-repos/
#rsync -aHx --progress releases/$RELEASE merreleases@monster.tspre.org:~/public_html/releases/
#rsync -aHx --progress releases/latest-release releases/latest releases/next-release releases/next merreleases@monster.tspre.org:~/public_html/releases/

fi

exit 0

