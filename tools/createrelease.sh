#!/bin/sh 
ORIG=$PWD
API=$2
TOOLS=$PWD/tools
RELEASE=$1

grab_repo() {
	REPO=$1
	ORIG=$PWD
	REPONAME=$3
	REPOSCHEDULERS="$4"
	mkdir -p $2
	cd $2
	
	wget $API/source/$REPO/
	mv index.html _index
	wget $API/source/$REPO/_meta
	wget $API/source/$REPO/_config

	PACKAGES=`python $TOOLS/printnames.py _index | xargs echo`

	for x in $PACKAGES; do
		mkdir -p $x
		cd $x
		wget -nd -nH -cr $API/source/$REPO/$x/_history  $API/source/$REPO/$x/_meta $API/source/$REPO/$x/_attribute $API/source/$REPO/$x/ -nd -nH -cr $API/source/$REPO/$x?expand=1
		mv $x?expand=1 _index-expand
		mv index.html _index
		LATESTREV=`python $TOOLS/getlatestrev.py _history`
		cp _index _index?rev=$LATESTREV
		cp _index-expand _index-expand?rev=$LATESTREV
		cd ..
	done

	mkdir -p _build/$REPONAME
	cd _build/$REPONAME
	if [ x"$REPOSCHEDULERS" != x"NONE" ]; then
		for x in $REPOSCHEDULERS; do
			mkdir -p $x
			cd $x
			wget $API/build/$REPO/$REPONAME/$x/_repository?view=cache
			mv _repository?view=cache _cache
			wget $API/build/$REPO/$REPONAME/$x/_repository?view=names
			mv _repository?view=names _names
			wget $API/build/$REPO/$REPONAME/$x/_repository?view=binaryversions
			mv _repository?view=binaryversions _binaryversions
			
			wget $API/build/$REPO/$REPONAME/$x/_repository
			# XXX not putting along debuginfo or debugsource
			for y in `python $TOOLS/printbinaries.py _repository | grep -v debuginfo.rpm | grep -v debugsource.rpm`; do
				wget -nd -nH -cr $API/build/$REPO/$REPONAME/$x/_repository/$y
			done
			cd ..
		done
	fi
	cd $ORIG
	
	mkdir -p sources-tree/
	cd sources-tree/

	for x in $PACKAGES; do
		python $TOOLS/cachefiles.py $ORIG/$2/$x/_index $API $REPO | sh
	done
	cd $ORIG
}


grab_repo Mer:Trunk:Base releases/$RELEASE/meta/sources/ standard i586
exit 0
grab_repo Mer:Trunk:Crosshelpers releases/$RELEASE/meta/crosshelpers/ standard NONE
grab_repo Mer:Trunk:Base:armv6l releases/$RELEASE/meta/port-armv6l/ standard "i586 armv7el"
grab_repo Mer:Trunk:Base:armv7l releases/$RELEASE/meta/port-armv7l/ standard "i586 armv7el"
grab_repo Mer:Trunk:Base:armv7hl releases/$RELEASE/meta/port-armv7hl/ standard "i586 armv8el"

grab_build()
{
	RSYNC=rsync://192.168.100.213/obsrepos
	SYNCPATH=$1
	NAME=$2
	ORIG=$PWD
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

grab_build Mer:/Trunk:/Base/standard i586 
grab_build Mer:/Trunk:/Base:/armv6l/standard armv6l
grab_build Mer:/Trunk:/Base:/armv7l/standard armv7l
grab_build Mer:/Trunk:/Base:/armv7hl/standard armv7hl

exit 0

