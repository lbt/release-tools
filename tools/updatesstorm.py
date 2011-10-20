import gitmer
import sys
import xml.dom.minidom
import time

doc = xml.dom.minidom.parse("mappings.xml")            

def newevent(type, project, package, x1):
    newevent= "" + str(gitmer.get_next_event() + 1) + "|" + str(int(time.time())) + "|" + type + "|" + project + "|" + package + "|" + x1 + "\n"

    f = open("lastevents", "a")
    f.write(newevent)
    f.close()

for x in doc.getElementsByTagName("mapping"):
     packagesdoc = xml.dom.minidom.parse(x.attributes["path"].value + "/packages.xml")            
     for y in packagesdoc.getElementsByTagName("package"):
         newevent("package", x.attributes["project"].value, y.attributes["name"].value, "")
     for z in packagesdoc.getElementsByTagName("link"):
         newevent("package", x.attributes["project"].value, z.attributes["to"].value, "")
     newevent("project", x.attributes["project"].value, "", "")
     if x.attributes.has_key("reponame"):
      newevent("repository", x.attributes["project"].value, x.attributes["reponame"].value, "i586")
      newevent("repository", x.attributes["project"].value, x.attributes["reponame"].value, "armv7el")
      newevent("repository", x.attributes["project"].value, x.attributes["reponame"].value, "armv8el")
