import json
from mcpi.minecraft import Minecraft 
from mcpi import block 

x1 = -10
x2 = 10
y1 = -10
y2 = 10
z1 = -10
z2 = 10

dist = {}
mc = Minecraft.create()

for x in range(x1, x2):
  print("Scanning x {}".format(x))
  for y in range(y1, y2):
    print(" - scanning y {}".format(y))
    for z in range(z1, z2):
      b = mc.getBlock(y, z, x)
      if b not in dist:
        dist[b] = 0
      dist[b] += 1 

print(json.dumps(dist, indent=4))
