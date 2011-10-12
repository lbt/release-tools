
import sys, os, urllib
import xml.dom.minidom

doc = xml.dom.minidom.parse(sys.argv[1])
count = 0
initial = [("view", "cpio")]
for x in doc.getElementsByTagName("binary"):
	if x.attributes["filename"].value.endswith("debuginfo.rpm") or x.attributes["filename"].value.endswith("debugsource.rpm"):
		continue
	if count == 48:
		print urllib.urlencode(initial)
		initial = [("view", "cpio")]
		count = 0
	
	initial.append(("binary", os.path.splitext(x.attributes["filename"].value)[0]))
	count = count + 1	
	
if count < 48:
	print urllib.urlencode(initial)