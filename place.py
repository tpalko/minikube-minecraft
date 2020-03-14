from mcpi.minecraft import Minecraft
import json 
import sys 

if len(sys.argv) < 2:
  exit(1)

mc = Minecraft.create()

places = {}

with open('places.json', 'r') as f:
  places = json.loads(f.read())

place = sys.argv[1]
pos = None 

if place in places:
  pos = places[place]

if pos:
  mc.player.setPos(pos.x, pos.y, pos.z)
else:
  print("No pos by that name")
