
import sys
import xml.dom.minidom

doc = xml.dom.minidom.parse(sys.argv[1])
latest = 0
for x in doc.getElementsByTagName("revision"):
	if int(x.attributes["rev"].value) > latest:
		latest = int(x.attributes["rev"].value)


print latest