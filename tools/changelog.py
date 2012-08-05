import gitmer
import sys
import xml.dom.minidom
import time
import git

# usage : changelog.py /path/to/project-core tagold tagnew

# Assumes that the git repo mentioned in the 'git' attribute of
# packages.xml is relative to pwd
# ie packages-git/mer-* should be present

# Yes it would be sensible to wrap an exception handler around these...
repo = git.Repo(sys.argv[1])
c1 = repo.commit(sys.argv[2])
c2 = repo.commit(sys.argv[3])

gitmer.changelog((c1.tree/"packages.xml").data_stream, (c2.tree/"packages.xml").data_stream)

