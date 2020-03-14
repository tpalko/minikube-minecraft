import os
import math
import json
from mcpi.minecraft import Minecraft 
from mcpi import block
import random 

radius = 30
origin = (40.0, 30.0, 40.0,)
blocks = [block.DIRT, block.WOOD, block.OBSIDIAN, block.IRON_BLOCK, block.SNOW_BLOCK, block.STONE_BRICK, block.STONE, block.MOSS_STONE, block.DIAMOND_BLOCK, block.GLASS, block.GRASS]

def angles(degrees, radius):
  circumference = int(math.floor((degrees/180)*math.pi*radius))
  if circumference > 0:
    return [ math.radians(degrees*c/circumference) for c in range(circumference + 1) ] 
  return []
  #  - does this simplify?
  # return [ math.radians(c/180*math.pi*radius) for c in range((degrees/180)*math.pi*radius + 1) ]

surface = []

if not os.path.exists('surface.json'):

  print("Creating surface.json..")

  ring_count = math.floor(math.pi*radius)
  rings = angles(180, radius)

  print("{} rings".format(len(rings)))

  for ring in rings:
    ring_radius = radius*math.sin(ring)
    x = radius*math.cos(ring)
    ring_angles = angles(360, ring_radius)
    print("this ring: radius {} x {}".format(ring_radius, x))
    ring_points = []
    for a in ring_angles: 
      point = (ring_radius*math.sin(a), ring_radius*math.cos(a), x,)
      modified_point = zip(origin, point)
      moved_point = [ sum(p) for p in modified_point ]                                
      print(" - moved point {}".format(moved_point))
      ring_points.append(moved_point)
    if len(ring_points) > 0:
      surface.append({ 'ring': ring_points })

  with open('surface.json', 'w') as f:
    f.write(json.dumps(surface, indent=4))

else:
  print("Found surface.json..")

with open('surface.json', 'r') as f:
  surface = json.loads(f.read())

mc = Minecraft.create()

for ring in surface:
  print("Ring ({} points)".format(len(ring['ring'])))
  for ring_point in ring['ring']:
    print(" - {}".format(ring_point))
    mc.setBlock(ring_point, random.choice(blocks))

exit(0)

asc_pos = [ radius*math.sin(a) for a in angles_radians ]
des_pos = [ radius*math.cos(a) for a in angles_radians ]
asc_neg = [ -radius*math.sin(a) for a in angles_radians ]
des_neg = [ -radius*math.cos(a) for a in angles_radians ]
flat    = [ 0 for a in angles_radians ]

# - these are the 12 arcs required to describe a sphere
# - one array must be positive and one negative, as an arc starts at one axis and moves to another
ypos_zpos = zip(asc_pos, des_pos, flat)
ypos_zneg = zip(asc_pos, des_neg, flat)
yneg_zpos = zip(asc_neg, des_pos, flat)
yneg_zneg = zip(asc_neg, des_neg, flat)
zpos_xpos = zip(flat, asc_pos, des_pos)
zpos_xneg = zip(flat, asc_pos, des_neg)
zneg_xpos = zip(flat, asc_neg, des_pos)
zneg_xneg = zip(flat, asc_neg, des_neg)
ypos_xpos = zip(asc_pos, flat, des_pos)
ypos_xneg = zip(asc_pos, flat, des_neg)
yneg_xpos = zip(asc_neg, flat, des_pos)
yneg_xneg = zip(asc_neg, flat, des_neg)

eighths = {
  'ypos_xpos_zpos': { 'arc': ypos_xpos, 'z': 1 },
  'ypos_xneg_zpos': { 'arc': ypos_xneg, 'z': 1 },
  'yneg_xpos_zpos': { 'arc': yneg_xpos, 'z': 1 },
  'yneg_xneg_zpos': { 'arc': yneg_xneg, 'z': 1 },
  'ypos_xpos_zneg': { 'arc': ypos_xpos, 'z': -1 },
  'ypos_xneg_zneg': { 'arc': ypos_xneg, 'z': -1 },
  'yneg_xpos_zneg': { 'arc': yneg_xpos, 'z': -1 },
  'yneg_xneg_zneg': { 'arc': yneg_xneg, 'z': -1 }
}

surfaces = { eighth: [] for eighth in eighths } 

print(surfaces)

for eighth in eighths:
  # - for each point on the origin arc (from each point..)
  # - iterate over angles_radians
  # - keeping the y from the starting point..
  # - the radius is the starting point x
  # - z is the sine of the angle times the radius
  # - x is the cosine of the angle times the radius
  z_dir = eighths[eighth]['z']
  arc = eighths[eighth]['arc']
  for p in arc: 
    # - starting with the x-y positive arc and swinging out into positive z, draw the smaller arcs on the sphere's surface
    # - one arc into z from each point on the x-y arc
    # - y is constant, x is cos of each angle in the list, z is the sin, where h is the max x or z (start or end, respectively)
    y = p[0]
    radius = p[2]
    # - from the first point on the arc, get the max x. this is the radius for all points on this new arc into z
    # - from the first point on the arc, get y. this is the value of y for all points on this new arc into z
    for a in angles_radians:
      surfaces[eighth].append([ sum(t) for t in zip(origin, (y, z_dir*radius*math.sin(a), radius*math.cos(a),)) ])

with open("surfaces.json", "w") as f:
  f.write(json.dumps(surfaces, indent=4))

mc = Minecraft.create()

for eighth in surfaces:
  print("Drawing {}..".format(eighth))
  arc = surfaces['eighths'][e]
  print(" arcs..")
  for point in arc:
    print("   point {}".format(point))
    mc.setBlock((point[0], point[1], point[2],), block.DIRT)


