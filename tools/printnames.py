
import sys
import xml.dom.minidom

doc = xml.dom.minidom.parse(sys.argv[1])
for x in doc.getElementsByTagName("entry"):
	print x.attributes["name"].value
