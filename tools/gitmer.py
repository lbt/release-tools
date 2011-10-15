from threading import Thread, Lock
import git
import hashlib
import csv, os
import xml.dom.minidom
from subprocess import *
from xml.dom.minidom import getDOMImplementation
import shutil
try:
    from cStringIO import StringIO
except ImportError:
    from StringIO import StringIO

myLock = Lock()

def synchronized(lock):
    """ Synchronization decorator. """

    def wrap(f):
        def newFunction(*args, **kw):
            lock.acquire()
            try:
                return f(*args, **kw)
            finally:
                lock.release()
        return newFunction
    return wrap

@synchronized(myLock)
def get_mappingscache():
     if not hasattr(get_mappingscache, "mcache"):
        get_mappingscache.mcache = xml.dom.minidom.parse("packages-git/mappingscache.xml")
        get_mappingscache.mcachetime = os.stat("packages-git/mappingscache.xml").st_mtime
     stat = os.stat("packages-git/mappingscache.xml")
     if get_mappingscache.mcachetime != stat.st_mtime:
         print "mappings cache was updated, reloading.."
         get_mappingscache.mcache = xml.dom.minidom.parse("packages-git/mappingscache.xml")
         get_mappingscache.mcachetime = os.stat("packages-git/mappingscache.xml").st_mtime   
     return get_mappingscache.mcache

#def get_mappingscache(filename):
#    if mcache.has_key(filename):
#       stat = os.stat(filename)
#       if mcache[filename][0] == stat.st_mtime:
#        return mcache[filename][1]
#    stat = os.stat(filename)
#   doc = xml.dom.minidom.parse(filename)
#    mcache[filename] = (stat.st_mtime, doc)
#    return doc

def adjust_meta(projectpath, projectname):
        meta = xml.dom.minidom.parse(projectpath + "/_meta")
        for x in meta.getElementsByTagName("project"):
            x.setAttribute("name", projectname)
        return meta.childNodes[0].toxml(encoding="us-ascii")

def build_project_index(projectpath):
        impl = getDOMImplementation()
        indexdoc = impl.createDocument(None, "directory", None)

        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            entryelm = indexdoc.createElement("entry")
            entryelm.setAttribute("name", x.attributes["name"].value)
            indexdoc.childNodes[0].appendChild(entryelm)
        for x in packagesdoc.getElementsByTagName("link"):
            entryelm = indexdoc.createElement("entry")
            entryelm.setAttribute("name", x.attributes["to"].value)
            indexdoc.childNodes[0].appendChild(entryelm)
	return indexdoc.childNodes[0].toprettyxml(encoding="us-ascii")

# Generate index XML
#print build_project_index("Base")

# Returns commit, rev, md5sum, tree
def get_package_tree_from_commit_or_rev(projectpath, packagename, commit):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")       
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                followbranch = x.attributes["followbranch"].value
                for mappingsdoc in get_mappingscache().getElementsByTagName("repo"):
                 if mappingsdoc.attributes["path"].value == x.attributes["git"].value:
                   for y in mappingsdoc.getElementsByTagName("map"):
                    if y.attributes["branch"].value != followbranch:
                        continue
                    if y.attributes["commit"].value == commit or y.attributes["srcmd5"].value == commit or y.attributes["rev"].value == commit:
                            repo = git.Repo(x.attributes["git"].value, odbt=git.GitDB)
                            return y.attributes["commit"].value, y.attributes["rev"].value, y.attributes["srcmd5"].value, repo.tree(x.attributes["commit"].value), x.attributes["git"].value
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_package_tree_from_commit_or_rev(projectpath, x.attributes["from"].value, commit)
        
        return None                    

def get_package_tree_and_commit(projectpath, packagename):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                repo = git.Repo(x.attributes["git"].value, odbt=git.GitDB)
                return x.attributes["commit"].value, repo.tree(x.attributes["commit"].value)
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_package_tree_and_commit(projectpath, x.attributes["from"].value)
        return None

def get_package_tree_for_commit_or_rev(projectpath, packagename, revorcommit):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                repo = git.Repo(x.attributes["git"].value, odbt=git.GitDB)
                return x.attributes["commit"].value, repo.tree(x.attributes["commit"].value)
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_package_tree_for_commit_or_rev(projectpath, x.attributes["from"].value, revorcommit)
        return None
        

def get_package_commit_mtime_vrev(projectpath, packagename):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                repo = git.Repo(x.attributes["git"].value, odbt=git.GitDB)
                return repo.commit(x.attributes["commit"].value).committed_date, x.attributes["vrev"].value
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_package_commit_mtime_vrev(projectpath, x.attributes["from"].value)
        return None
        

def get_entries_from_commit(projectpath, packagename, commit):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                
                for mappingsdoc in get_mappingscache().getElementsByTagName("repo"):
                 if mappingsdoc.attributes["path"].value == x.attributes["git"].value:
                  for y in mappingsdoc.getElementsByTagName("map"):
                    if y.attributes["commit"].value == commit:
                        entries = {}
                        for z in y.getElementsByTagName("entry"):
                            entries[z.attributes["name"].value] = z.attributes["md5"].value
                        return entries
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_entries_from_commit(projectpath, x.attributes["from"].value, commit)
        return None       

def get_latest_commit(projectpath, packagename):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("package"):
            if x.attributes["name"].value == packagename:
                        return x.attributes["commit"].value
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return get_latest_commit(projectpath, x.attributes["from"].value)
        return None       

def get_package_link(projectpath, packagename):
        packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
        for x in packagesdoc.getElementsByTagName("link"):
            if x.attributes["to"].value == packagename:
                return x.attributes["to"].value
        return None

def get_package_index_supportlink(projectpath, packagename, getrev, expand):
        return get_package_index(projectpath, packagename, getrev=getrev)    

def get_package_index(projectpath, packagename, getrev=None):
        if getrev is None:
            getrev = "latest"
        if getrev == "upload":
            getrev = "latest"
        if getrev == "build":
            getrev = "latest"
        if getrev == "latest":
            getrev = get_latest_commit(projectpath, packagename)
        
        impl = getDOMImplementation()
        indexdoc = impl.createDocument(None, "directory", None)
        indexdoc.childNodes[0].setAttribute("name", packagename)
          
        commit, rev, srcmd5, tree, git = get_package_tree_from_commit_or_rev(projectpath, packagename, getrev)
        indexdoc.childNodes[0].setAttribute("srcmd5", srcmd5)

        mtime, vrev = get_package_commit_mtime_vrev(projectpath, packagename)
        entrymd5s = get_entries_from_commit(projectpath, packagename, commit)
                
#        if projectpath == "obs-projects/Core-armv7l":
#          indexdoc.childNodes[0].setAttribute("rev", str(int(rev) + 1))
#        else:
        indexdoc.childNodes[0].setAttribute("rev", rev)
        indexdoc.childNodes[0].setAttribute("vrev", vrev)
        for entry in tree:
            if entry.name == "_meta" or entry.name == "_attribute":
                continue
            entryelm = indexdoc.createElement("entry")
            entryelm.setAttribute("name", entry.name)
            entryelm.setAttribute("size", str(entry.size))
            entryelm.setAttribute("mtime", str(mtime))
            entryelm.setAttribute("md5", entrymd5s[entry.name])
                        
            indexdoc.childNodes[0].appendChild(entryelm)
        return indexdoc.childNodes[0].toprettyxml(encoding="us-ascii")        


def get_package_file_supportlink(projectpath, packagename, filename, getrev, expand):
        return get_package_file(projectpath, packagename, filename, getrev=getrev)    


def update_package_xml(packagesfile):
        packagesdoc = xml.dom.minidom.parse(packagesfile)            
        for x in packagesdoc.getElementsByTagName("package"):
           repo = git.Repo(x.attributes["git"].value, odbt=git.GitDB)
           newestcommitonbranch = repo.commit(x.attributes["followbranch"].value).hexsha
           if newestcommitonbranch != x.attributes["commit"].value:
            print "updating package " + x.attributes["name"].value + " git " + x.attributes["git"].value
           x.setAttribute("commit", newestcommitonbranch)
        newxml = packagesdoc.toxml(encoding="us-ascii")
        f = open(packagesfile, "wb")
        f.write(newxml)
        f.close()                        
        
def get_next_event():
        f = open("lastevents", 'rb')
        csvReader = csv.reader(f, delimiter='|', quotechar='"')
        last = 0
        for row in csvReader:
            last = int(row[0])
        f.close()
        return last 
           

def get_events_filtered(start, filters):
        f = open("lastevents", 'rb')
        
        impl = getDOMImplementation()
        indexdoc = impl.createDocument(None, "events", None)
        indexdoc.childNodes[0].setAttribute("next", str(get_next_event()))        
        
        csvReader = csv.reader(f, delimiter='|', quotechar='"')
        for row in csvReader:
            num = int(row[0])
            if num <= start:
                continue
            is_ok = False
            for filter in filters:
                if filter[2] is None:
                    if filter[0] == row[2] and filter[1] == row[3]:
                       is_ok = True
                elif filter[0] == row[2] and filter[1] == row[3] and filter[2] == row[4]:
                    is_ok = True
            if is_ok:
                eventelm = indexdoc.createElement("event")
                eventelm.setAttribute("type", row[2])
                if row[2] == "package":
                    prjelm = indexdoc.createElement("project")
                    prjtext = indexdoc.createTextNode(row[3])
                    prjelm.appendChild(prjtext)            
                    eventelm.appendChild(prjelm)
                    packageelm = indexdoc.createElement("package")
                    packagetext = indexdoc.createTextNode(row[4])
                    packageelm.appendChild(packagetext)
                    eventelm.appendChild(packageelm)                
                indexdoc.childNodes[0].appendChild(eventelm)                
        f.close()
#  XXX add support for project events and repository events
#        print indexdoc.childNodes[0].toxml(encoding="us-ascii")
        
        return indexdoc.childNodes[0].toxml(encoding="us-ascii")

def file_fix_meta(realproject, packagename, metastr, ifdisable):
    meta = xml.dom.minidom.parseString(metastr)
    for x in meta.getElementsByTagName("package"):
        x.setAttribute("project", realproject)
        x.setAttribute("name", packagename)
    if ifdisable:
        buildelm = None
        for x in meta.getElementsByTagName("build"):
          buildelm = x
        if buildelm is None:
          buildelm = meta.createElement("build")
          meta.childNodes[0].appendChild(buildelm)
        disableelm = meta.createElement("disable")
        disableelm.setAttribute("arch", "i586")
        buildelm.appendChild(disableelm)             
            
    out = meta.childNodes[0].toxml(encoding="utf-8")
    return len(out), out

def get_if_disable(projectpath, packagename):
    packagesdoc = xml.dom.minidom.parse(projectpath + "/packages.xml")            
    if packagesdoc.childNodes[0].attributes.has_key("disablei586"):
      for x in packagesdoc.getElementsByTagName("package"):
         if x.attributes["name"].value != packagename:
           continue
         if x.attributes.has_key("enablei586"):
           return False 
      for x in packagesdoc.getElementsByTagName("link"):
         if x.attributes["to"].value != packagename:
          continue
         if x.attributes.has_key("enablei586"):
           return False
      return True
    return False

def get_package_file(realproject, projectpath, packagename, filename, getrev):
        if getrev is None:
            getrev = "latest"
        if getrev == "upload":
            getrev = "latest"
        if getrev == "build":
            getrev = "latest"        
        if getrev == "latest":
            getrev = get_latest_commit(projectpath, packagename)
        impl = getDOMImplementation()
        indexdoc = impl.createDocument(None, "directory", None)
        indexdoc.childNodes[0].setAttribute("name", packagename)
        commit, rev, srcmd5, tree, git = get_package_tree_from_commit_or_rev(projectpath, packagename, getrev)
        ifdisable = get_if_disable(projectpath, packagename)
        for entry in tree:
            if entry.name == filename:
              if filename == "_meta":
               return file_fix_meta(realproject, packagename, git_cat(git, entry.hexsha), ifdisable)
              else:
               return entry.size, git_cat(git, entry.hexsha)
        return None

def git_cat(gitpath, object):
    return Popen(["git", "--git-dir=" + gitpath, "cat-file", "blob", object], stdout=PIPE).communicate()[0]

def generate_mappings(repos):
        impl = getDOMImplementation()
        indexdoc = impl.createDocument(None, "maps", None)
        
        for x in repos:
                pkgelement = indexdoc.createElement("repo")
                pkgelement.setAttribute("path", x)
                
                repo = git.Repo(x, odbt=git.GitDB)
                for branch in repo.heads:
                    toprev = 0
                    for xz in repo.iter_commits(branch):
                      toprev = toprev + 1
                    rev = 0

                    for cm in repo.iter_commits(branch):
                      entries = {}
                      for entry in cm.tree:
                         if entry.name == "_meta" or entry.name == "_attribute":
                              continue
                         st = git_cat(x, entry.hexsha)
                         assert len(st) == entry.size
                         m = hashlib.md5(st)
                         entries[entry.name] = m.hexdigest()
                      sortedkeys = sorted(entries.keys())
                      meta = ""
                      for y in sortedkeys:
                         meta += entries[y]
                         meta += "  "
                         meta += y
                         meta += "\n"
    
                      m = hashlib.md5(meta)
                      mapelm = indexdoc.createElement("map")
                      mapelm.setAttribute("branch", branch.name)
                      mapelm.setAttribute("commit", cm.hexsha)
                      mapelm.setAttribute("srcmd5", m.hexdigest())
                      mapelm.setAttribute("rev", str(toprev-rev))
                      for y in sortedkeys:
                          entryelm = indexdoc.createElement("entry")
                          entryelm.setAttribute("name", y)
                          entryelm.setAttribute("md5", entries[y])
                          mapelm.appendChild(entryelm)
                      pkgelement.appendChild(mapelm)   
                      rev = rev + 1     
                indexdoc.childNodes[0].appendChild(pkgelement)
                rev = rev + 1     
        return indexdoc.childNodes[0].toprettyxml()

#generate_mappings("Base")        
        
# Normal package
#for entry in get_package_tree_and_commit("Base", "acl")[1]:
#    print entry.name
        
# Linked package
#for entry in get_package_tree_and_commit("Base", "rpm-python")[1]:
#    print entry.name
 
# Get package index
#print get_package_index("Base", "acl")
