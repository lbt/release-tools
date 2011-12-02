"""Simple HTTP Server.

This module builds on BaseHTTPServer by implementing the standard GET
and HEAD requests in a fairly straightforward manner.

"""


__version__ = "0.6"

__all__ = ["SimpleHTTPRequestHandler"]

import os, sys
import posixpath
import SocketServer
import BaseHTTPServer
import urllib
import cgi
import time
import shutil
import mimetypes
import urlparse
import uuid
import gitmer
import subprocess
import xml.dom.minidom
import os
import traceback

try:
    from cStringIO import StringIO
except ImportError:
    from StringIO import StringIO

class SimpleHTTPRequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    server_version = "fakeobs/" + __version__

    def do_GET(self):
        """Serve a GET request."""
        f = None
        try:
            f = self.send_head()
        except: 
            self.send_response(500)
            print "500: " + self.path
            traceback.print_exc(file=sys.stdout)
            self.end_headers()
        if f:
            self.copyfile(f, self.wfile)
            if hasattr(f, "close"):
               f.close()

    def do_HEAD(self):
        """Serve a HEAD request."""
        f = self.send_head()
        if f:
          if hasattr(f, "close"):
            f.close()

    def do_POST(self):
        f = self.send_head()
        if f:
          self.copyfile(f, self.wfile)
          if hasattr(f, "close"):
            f.close()             

    # Always returns a stream
    def send_head(self):
        def lookup_path(projectname):
            doc = xml.dom.minidom.parse("mappings.xml")            
            for x in doc.getElementsByTagName("mapping"):
                if x.attributes["project"].value == projectname:
                    return x.attributes["path"].value
            return None
        def lookup_binariespath(projectname):
            doc = xml.dom.minidom.parse("mappings.xml")            
            for x in doc.getElementsByTagName("mapping"):
                if x.attributes["project"].value == projectname:
                    return x.attributes["binaries"].value
            return None
        def string2stream(thestr):
            content = StringIO()
            content.write(thestr)
            content.seek(0, os.SEEK_END)
            contentsize = content.tell()
            content.seek(0, os.SEEK_SET)
            return contentsize, content
        def file2stream(path):
            f = open(path, 'rb')
            fs = os.fstat(f.fileno())
            return fs[6], fs.st_mtime, f
                    
        content = None
        contentsize = 0
        contentmtime = 0
        contenttype = None
                
        pathparsed = urlparse.urlparse(self.path)
        path = pathparsed[2] 

        if self.headers.getheader('Content-Length') is not None:
            data = self.rfile.read(int(self.headers.getheader('Content-Length')))
            query = urlparse.parse_qs(data)
        elif pathparsed[4] is not None:
            query = urlparse.parse_qs(pathparsed[4])
        else:
            query = {}

        if path.startswith("/public/lastevents"):
            if query.has_key("start"):
                if int(query["start"][0]) == gitmer.get_next_event():
                        # Normally OBS would block here, but we just 503 and claim we're busy, 
                        # hoping it comes back
                        self.send_response(503)
                        self.end_headers()
                        return None
                
                filters = []
                
                if query.has_key("filter"):
                    for x in query["filter"]:
                        spl = x.split('/')
                        if len(spl) == 2:
                            filters.append((urllib.unquote(spl[0]), urllib.unquote(spl[1]), None))
                        else:
                            filters.append((urllib.unquote(spl[0]), urllib.unquote(spl[1]), urllib.unquote(spl[2])))
                contentsize, content = string2stream(gitmer.get_events_filtered(int(query["start"][0]), filters))
                contenttype = "text/html"
                contentmtime = time.time()
            else:
                output = '<events next="' + str(gitmer.get_next_event()) + '" sync="lost" />\n'
                
                contentsize, content = string2stream(output)
                contenttype = "text/html"
                contentmtime = time.time()
            
        elif path.startswith("/public/source/"):
            pathparts = path.split("/")
            pathparts = pathparts[1:]
            for x in range(0, len(pathparts)):
                pathparts[x] = urllib.unquote(pathparts[x])
            realproject = None
            if len(pathparts) >= 3:
               realproject = pathparts[2]
               pathparts[2] = lookup_path(pathparts[2])
               
               if pathparts[2] is None:
                    pathparts[2] = "--UNKNOWNPROJECT"
            
            # /source/project/
            if len(pathparts) == 3:
                if os.path.isfile(pathparts[2] + "/packages.xml"):
                      contentsize, content = string2stream(gitmer.build_project_index(pathparts[2]))
                      contenttype = "text/xml"
                      contentmtime = time.time()
            # package or metadata for project
            elif len(pathparts) == 4:
                if pathparts[3] == "_config":
                    contentsize, contentmtime, content = file2stream(pathparts[2] + "/" + pathparts[3])
                    contenttype = "text/plain"
                elif pathparts[3] == "_meta":
                    contentsize, content = string2stream(gitmer.adjust_meta(pathparts[2], realproject))
                    contenttype = "text/xml"
                    contentmtime = time.time()
                elif pathparts[3] == "_pubkey":
                    content = None # 404 it
                elif pathparts[3] == "_pattern":
                    content = None # 404 it
                else:
                    expand = 0
                    rev = None
                    if query.has_key("expand"):
                        expand = int(query["expand"][0])
                    if query.has_key("rev"):
                        rev = query["rev"][0]
                    
                    contentsize, content = string2stream(gitmer.get_package_index_supportlink(pathparts[2], pathparts[3], rev, expand))
                    contenttype = "text/xml"
                    contentmtime = time.time()
            elif len(pathparts) == 5:
                rev = None
                expand = 0
                if query.has_key("expand"):
                        expand = int(query["expand"][0])
                if query.has_key("rev"):
                        rev = query["rev"][0]
                contentsize, contentst = gitmer.get_package_file(realproject, pathparts[2], pathparts[3], pathparts[4], rev)
                contentz, content = string2stream(contentst)
                contenttype = "application/octet-stream"
                contentmtime = time.time()
        elif path.startswith("/public/build"):
            pathparts = path.split("/")
            pathparts = pathparts[1:]
            print pathparts
            #/public/build/Mer:Trunk:Base/standard/i586/_repository?view=cache
            if len(pathparts) >= 3:
                pathparts[2] = lookup_binariespath(pathparts[2])
                if pathparts[2] is None:
                    pathparts[2] = "--UNKNOWNPROJECT"
            if len(pathparts) == 6 and pathparts[5] == "_repository":
                # pathparts[2]  == project
                #          [3]  == repository
                #          [4]  == scheduler
                if query.has_key("view") and query["view"][0] == "cache":
                    if os.path.isfile(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=cache"):
                        contentsize, contentmtime, content = file2stream(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=cache")
                        contenttype = "application/octet-stream"
                    else:
                        contentsize, contentmtime, content = file2stream("tools/emptyrepositorycache.cpio")
                        contenttype = "application/octet-stream"
                elif query.has_key("view") and query["view"][0] == "solvstate":
                    if os.path.isfile(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=solvstate"):
                        contentsize, contentmtime, content = file2stream(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=solvstate")
                        contenttype = "application/octet-stream"
                    else:
                        contentsize, contentmtime, content = file2stream("tools/emptyrepositorycache.cpio")
                        contenttype = "application/octet-stream"
                elif query.has_key("view") and query["view"][0] == "cpio":
                    binaries = ""
                    for x in query["binary"]:
                        if os.path.isfile(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/" + os.path.basename(x) + ".rpm"):
                            assert "" + pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/" + os.path.basename(x) + ".rpm was not found"
                        binaries = binaries + os.path.basename(x) + ".rpm\n"
                    
                    print binaries

                    cpiooutput = subprocess.Popen(["tools/createcpio", pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4]], stdin=subprocess.PIPE, stdout=subprocess.PIPE).communicate(binaries)[0]
#                    cpiooutput = subprocess.Popen(["/usr/bin/curl", "http://192.168.100.213:81/public/build/Core:i586/Core_i586/i586/_repository?" + pathparsed[4]], stdin=subprocess.PIPE, stdout=subprocess.PIPE).communicate()[0]
                    contentsize, content = string2stream(cpiooutput)
                    print contentsize
                    contentmtime = time.time()
                    contenttype = "application/x-cpio"
                    ##
                elif query.has_key("view") and query["view"][0] == "names":
                    if os.path.isfile(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=names"):
                        doc = xml.dom.minidom.parse(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=names")
                        removables = []
                        for x in doc.getElementsByTagName("binary"):
                            if not os.path.splitext(x.attributes["filename"].value)[0] in query["binary"]:
                                removables.append(x)
                        for x in removables:
                            doc.childNodes[0].removeChild(x)
                        contentsize, content = string2stream(doc.childNodes[0].toxml())
                        contentmtime = time.time()
                        contenttype = "text/html"                    
                    else:
                        contentsize, content = string2stream("<binarylist />")
                        contenttype = "text/html"
                        contentmtime = time.time()
                    ##
                elif query.has_key("view") and query["view"][0] == "binaryversions":                   
                    if os.path.isfile(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=cache"):
                        doc = xml.dom.minidom.parse(pathparts[2] + "/" + pathparts[3] + "/" + pathparts[4] + "/_repository?view=binaryversions")
                        removables = []
                        for x in doc.getElementsByTagName("binary"):
                            if not os.path.splitext(x.attributes["name"].value)[0] in query["binary"]:
                                removables.append(x)
                        for x in removables:
                            doc.childNodes[0].removeChild(x)
                        contentsize, content = string2stream(doc.childNodes[0].toxml())
                        contentmtime = time.time()
                        contenttype = "text/html"                    
                    else:
                        contentsize, content = string2stream("<binaryversionlist />")
                        contenttype = "text/html"
                        contentmtime = time.time()
                
        if content is None:
              print "404: path"
              self.send_error(404, "File not found")
              return None
              
        self.send_response(200)
        self.send_header("Content-type", contenttype)
        self.send_header("Content-Length", contentsize)
        self.send_header("Last-Modified", self.date_time_string(contentmtime))
        self.end_headers()
        return content

    def copyfile(self, source, outputfile):
        """Copy all data between two file objects.

        The SOURCE argument is a file object open for reading
        (or anything with a read() method) and the DESTINATION
        argument is a file object open for writing (or
        anything with a write() method).

        The only reason for overriding this would be to change
        the block size or perhaps to replace newlines by CRLF
        -- note however that this the default server uses this
        to copy binary data as well.

        """
        shutil.copyfileobj(source, outputfile)

class XFSPWebServer(SocketServer.ThreadingMixIn, BaseHTTPServer.HTTPServer):
        pass

PORT = int(sys.argv[1])

httpd = XFSPWebServer(("0.0.0.0", PORT), SimpleHTTPRequestHandler)
httpd.serve_forever()

