#!/bin/bash
ORIG=$PWD

# Get Project configuration
. tools/release.conf

# This script creates a mer release intended to appear on http://releases.merproject.org/releases/

# Note that createrelease will take an instantaneous snapshot of the CI OBS - please ensure it is not busy

# It operates within the release-tools directory
# It uses the following subdirs:
#  obs-projects/
#    This contains the obs project metadata - it's used to obtain the group data to build the repos
# It updates the following subdirs:
#  $OBSDIR/
#    This is a mirror of the OBS built rpms and some useful OBS state (such as solvstate)
#    It's a transient holding directory as rpms are transferred to the correct structure in ...
#  $RELEASEDIR/
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

if [[ -z $OBSDIR ]] || ! [[ -d $OBSDIR ]] ; then echo "The OBSDIR variable is set to '$OBSDIR' which is not a directory. Please correct this in release.conf"; exit 1; fi
if [[ -z $RELEASEDIR ]] || ! [[ -d $RELEASEDIR ]] ; then echo "The RELEASEDIR variable is set to '$RELEASEDIR' which is not a directory. Please correct this in release.conf"; exit 1; fi

# Check PROJECTS
while read -r project repo arch scheds ; do
    if ! [[ $project ]]; then echo "Invalid blank line in PROJECTS in releases.conf"; exit 1; fi # blank line
    if ! [[ $scheds ]]; then echo "Invalid line in PROJECTS in releases.conf, no schedulers"; exit 1; fi # not enough values
done <<< "$PROJECTS"

################

dumpbuild ()
{
    API=$1
    OBSPROJECT=$2
    OUTDIR=$3
    REPONAME=$4
    IFS=: read -ra SCHEDULERS <<< $5 # : seperated list of architectures in $5

    [[ -d $OBSDIR/$OUTDIR ]] && {
	echo "$OBSDIR/$OUTDIR exists already. Looks like you already fetched this release from OBS"
	echo 'remove the $OBSDIR/*$RELEASE directories manually if you need to re-fetch'
	exit 1
    }

    wget_opts="-q --no-check-certificate -N -c -r -nd -nH -p"
    for scheduler in "${SCHEDULERS[@]}"; do
	baseurl=$API/build/$OBSPROJECT/$REPONAME/$scheduler
	targetdir=$OBSDIR/$OUTDIR/$REPONAME/$scheduler
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
    mkdir -p $RELEASEDIR/$RELEASE/builds/$NAME/{packages,debug}
    echo copying from OBS repo to releases
    rsync  -aHx --verbose $RSYNCPATH/* --exclude=*.src.rpm --exclude=repocache/ --exclude=*.repo --exclude=repodata/ --exclude=src/ --exclude=dontuse/ --include=*.rpm $RELEASEDIR/$RELEASE/builds/$NAME/packages/


    echo removing signatures
    find $RELEASEDIR/$RELEASE/builds/$NAME/packages/ -name \*.rpm | xargs -L1 rpm --delsign
    mv $RELEASEDIR/$RELEASE/builds/$NAME/packages/*/*-debug{info,source}-* $RELEASEDIR/$RELEASE/builds/$NAME/debug/

    if [[ $CROSS ]]; then
        # Move all cross- gcc/binutils packages to the relevant arch's cross/ area
	case $NAME in
	    *86* ) ;; # Ignore cross for i{3,4,5,6}86 and x86_64 ?
	    * )
		echo "Preparing /cross" # This may need to be handled better with x86_64 etc
		mv $RELEASEDIR/$RELEASE/builds/$NAME/packages/*/cross-*{gcc,binutils}*.i{4,5}86.rpm $RELEASEDIR/$RELEASE/builds/i486/cross/
		;;
	esac
    fi

    # Phase 2 : Apply package groups and create repository
    if [ -e $GROUPXML ] ; then
	createrepo -g $GROUPXML $RELEASEDIR/$RELEASE/builds/$NAME/packages/
    else
	createrepo $RELEASEDIR/$RELEASE/builds/$NAME/packages/
    fi
    [ -e $PATTERNXML ] && {
	cp $PATTERNXML $RELEASEDIR/$RELEASE/builds/$NAME/packages/repodata/
	modifyrepo $RELEASEDIR/$RELEASE/builds/$NAME/packages/repodata/patterns.xml $RELEASEDIR/$RELEASE/builds/$NAME/packages/repodata/
    }
    # No need for package groups in debug symbols
    createrepo $RELEASEDIR/$RELEASE/builds/$NAME/debug/
    # Remove confusing empty directories
    rmdir --ignore-fail-on-non-empty $RELEASEDIR/$RELEASE/builds/$NAME/packages/*
}

################

# Step 1 : Get from OBS and update latest/next obs-repo
# This populates ./obs-repos
if [[ $GET_FROM_OBS ]]; then
    echo "################################################################ Get from OBS"
    # If a dumpbuild fails, abort
    while read -r project repo arch scheds ; do
	echo "Get OBS build for $project with repo $repo for $scheds"
	set -e
	dumpbuild "$API" "$project" ${project}:$RELEASE $repo $scheds
	set +e
    done <<< "$PROJECTS"

    if [[ $PRERELEASE ]]; then
	while read -r project repo arch scheds ; do
	    echo "Make $PRERELEASE for $project"
	    rm -f $OBSDIR/${project}:$PRERELEASE
	    ln -s ${project}:$RELEASE $OBSDIR/${project}:$PRERELEASE
	done <<< "$PROJECTS"
    fi
fi

# Step 2: Make repos in release area
# This populates ./releases
if [[ $MAKE_REPOS ]]; then
    echo "################################################################ Make Repos"
    if [[ $CROSS ]]; then
	mkdir -p $RELEASEDIR/$RELEASE/builds/i486/cross
	mkdir -p $RELEASEDIR/$RELEASE/builds/i586/cross
    fi
    while read -r project repo arch scheds ; do
	echo "Make repos for $project"
	projdir=${project//:/:\/}
	build2repo $RSYNC/${projdir}/$repo $arch $ORIG/obs-projects/Core/$NAME/group.xml $ORIG/obs-projects/Core/$NAME/patterns.xml
        # Now update the repo in the cross areas (this will need some grouping generated for easy installation)
    done <<< "$PROJECTS"
    if [[ $CROSS ]]; then
	createrepo $RELEASEDIR/$RELEASE/builds/i486/cross
	createrepo $RELEASEDIR/$RELEASE/builds/i586/cross
    fi

    if [[ $PRERELEASE ]]; then
	echo $RELEASE > $OBSDIR/$PRERELEASE.release
	echo $RELEASE > $RELEASEDIR/$PRERELEASE-release
	rm -f $RELEASEDIR/$PRERELEASE
	ln -s $RELEASE $RELEASEDIR/$PRERELEASE
    fi
fi

# Step 3: Publish
# This publishes ./releases
if [[ $PUBLISH ]]; then
    echo "################################################################ Publish"

    while read -r project repo arch scheds ; do
	echo "Publish OBS build for $project"
	rsync -aHx --progress $OBSDIR/${project}:$RELEASE $RSYNC_OBS_PUBLISH

	if [[ $PRERELEASE ]]; then
	    rsync -aHx --progress $OBSDIR/${project}:$PRERELEASE $OBSDIR/$PRERELEASE.release $RSYNC_OBS_PUBLISH
	fi
    done <<< "$PROJECTS"

    echo "Publish Repos for $project with repo $repo for $scheds"
    rsync -aHx --progress $RELEASEDIR/$RELEASE $RSYNC_REPO_PUBLISH
    if [[ $PRERELEASE ]]; then
	    rsync -aHx --progress $RELEASEDIR/$PRERELEASE-release $RELEASEDIR/$PRERELEASE $RSYNC_REPO_PUBLISH
    fi
fi

exit 0
