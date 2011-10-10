import sys, gitmer

f = open(sys.argv[1], "r")
repos = []
for x in f.readlines():
    x = x.strip('\r')
    x = x.strip('\n')
    repos.append(x)
f.close()

f = open(sys.argv[2], "w+")
f.write(gitmer.generate_mappings(repos))
f.close()
