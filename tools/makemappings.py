import sys, gitmer

f = open(sys.argv[1], "r")
repos = []
for x in f.readlines():
    x = x.strip('\r')
    x = x.strip('\n')
    repos.append(x)
f.close()

mappings = gitmer.generate_mappings(repos)
f = open(sys.argv[2], "w+")

f.write(mappings)
f.close()
