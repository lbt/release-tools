import gitmer
import sys
import xml.dom.minidom
import time

if len(sys.argv) > 2:
  gitmer.update_package_xml(sys.argv[1], package=sys.argv[2])
else:
  gitmer.update_package_xml(sys.argv[1])
            
