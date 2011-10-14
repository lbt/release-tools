PLEASEMAKE=packages-git/mappingscache.xml lastevents obs-projects/Core
GIT_PROTOCOL:=git

ifeq ($(GIT_PROTOCOL),git)
GIT_URL=git://gitorious.org/merproject/project-core.git
else
GIT_URL=https://git.gitorious.org/merproject/project-core.git
endif

all: $(PLEASEMAKE)

updatepackages:
	rsync -aHx --verbose --exclude=repos.lst --exclude=mappingscache.xml --exclude=.keep --delete-after rsync://monster.tspre.org/mer-releases/packages-git/ packages-git

updatecore:
	cd obs-projects/Core; git pull

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
