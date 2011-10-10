
import sys
import xml.dom.minidom

doc = xml.dom.minidom.parse(sys.argv[1])
for x in doc.getElementsByTagName("binary"):
	print x.attributes["filename"].value
