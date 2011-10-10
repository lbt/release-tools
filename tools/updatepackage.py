import gitmer
import sys
import xml.dom.minidom
import time

doc = xml.dom.minidom.parse("mappings.xml")            

def newevent(project, package):
    newevent= "" + str(gitmer.get_next_event() + 1) + "|" + str(int(time.time())) + "|package|" + project + "|" + package + "\n"

    f = open("lastevents", "a")
    f.write(newevent)
    f.close()


for x in doc.getElementsByTagName("mapping"):
     packagesdoc = xml.dom.minidom.parse(x.attributes["path"].value + "/packages.xml")            
     for y in packagesdoc.getElementsByTagName("package"):
            if y.attributes["git"].value == sys.argv[1]:
                gitmer.update_package_xml(x.attributes["path"].value, y.attributes["name"].value)
            
