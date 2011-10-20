PLEASEMAKE=packages-git/mappingscache.xml lastevents obs-projects/Core

GIT_URL=http://monster.tspre.org:8080/p/mer/project-core

all: $(PLEASEMAKE)

fetchlatestrepo:
       rsync -aHx --verbose rsync://monster.tspre.org/mer-releases/obs-repos/latest.release obs-repos/latest.release
       rsync -aHx --verbose rsync://monster.tspre.org/mer-releases/obs-repos/Core:*:`cat obs-repos/latest.release` obs-repos
       rsync -aHx --verbose rsync://monster.tspre.org/mer-releases/obs-repos/Core:*:latest obs-repos

updatepackages:
	rsync -aHx --verbose --exclude=repos.lst --exclude=mappingscache.xml --exclude=.keep --delete-after rsync://monster.tspre.org/mer-releases/packages-git/ packages-git

updatecore:
	cd obs-projects/Core; git pull

updatesstorm:
	python tools/updatesstorm.py

update: fetchlatestrepo updatepackages updatecore all updatesstorm 
	
obs-projects/Core:
	git clone $(GIT_URL) obs-projects/Core

packages-git/repos.lst:: updatepackages
	find packages-git/mer-core packages-git/mer-crosshelpers -mindepth 1 -maxdepth 1 -type d -printf "%p\n" | sort > packages-git/repos.lst

packages-git/mappingscache.xml: packages-git/repos.lst
	if [ ! -e $@ ]; then echo '<mappings />' > $@ ; fi
	python tools/makemappings.py $^ $@
	
lastevents:
	touch lastevents
	sh tools/addevent initial na na 

clean:
	rm -f $(PLEASEMAKE)
