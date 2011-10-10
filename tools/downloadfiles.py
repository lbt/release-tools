
import sys
import xml.dom.minidom

doc1 = xml.dom.minidom.parse(sys.argv[1])
doc1entries = []

for x in doc1.getElementsByTagName("directory"):
	rev1 = x.attributes["rev"].value
	pkg = x.attributes["name"].value

for x in doc1.getElementsByTagName("entry"):
	tuple = (x.attributes["name"].value, x.attributes["md5"].value, x.attributes["size"].value, x.attributes["mtime"].value)
	print 'wget -nd -nH -cr "%s/source/%s/%s/%s"' % (sys.argv[2], sys.argv[3], pkg, tuple[0])
		
		
