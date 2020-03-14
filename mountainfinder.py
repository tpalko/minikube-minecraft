import json

maxHeight = None 

with open('maxheight.json', 'r') as f:
  maxHeight = json.loads(f.read())

xcur = -127
ycur = -127
block = 10

while True:
  pos = 0
  ypos = maxHeight  
