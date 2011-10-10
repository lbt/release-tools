
import sys
import xml.dom.minidom

doc1 = xml.dom.minidom.parse(sys.argv[1])
doc1entries = []

for x in doc1.getElementsByTagName("directory"):
	rev1 = x.attributes["rev"].value
	pkg = x.attributes["name"].value

for x in doc1.getElementsByTagName("entry"):
	tuple = (x.attributes["name"].value, x.attributes["md5"].value, x.attributes["size"].value, x.attributes["mtime"].value)
	print 'if [ ! -e "%s/%s-%s" ]; then' % (pkg, tuple[0], tuple[1])
	print '   mkdir -p %s' % (pkg)
	print '   cd %s' % (pkg)
	print '   wget -nd -nH -cr "%s/source/%s/%s/%s?rev=%s"' % (sys.argv[2], sys.argv[3], pkg, tuple[0], rev1)
	print '   mv "%s?rev=%s" "%s-%s"' % (tuple[0], rev1, tuple[0], tuple[1])
	print '   cd ..' 
        print 'fi'
		
		
