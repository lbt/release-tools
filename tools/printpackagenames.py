
import sys
import xml.dom.minidom

doc = xml.dom.minidom.parse(sys.argv[1])
for x in doc.getElementsByTagName("package"):
	print x.attributes["name"].value

for x in doc.getElementsByTagName("link"):
	print x.attributes["to"].value
