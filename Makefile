PLEASEMAKE=packages-git/mappingscache.xml lastevents obs-projects/Core


all: $(PLEASEMAKE)

obs-projects/Core:
	git clone obs-projects/Core.git obs-projects/Core

packages-git/repos.lst::
	find packages-git/mer-core packages-git/mer-crosshelpers -mindepth 1 -maxdepth 1 -type d -printf "%p\n" | sort > packages-git/repos.lst

packages-git/mappingscache.xml: packages-git/repos.lst
	python tools/makemappings.py $^ $@
	
lastevents:
	touch lastevents
	sh tools/addevent initial na na 

clean:
	rm -f $(PLEASEMAKE)
