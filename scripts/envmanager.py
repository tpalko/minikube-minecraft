#!/usr/bin/env python3 

import sys 
import json 

if len(sys.argv) < 3:
    raise Exception("Sorry")

version = sys.argv[1]
new_world_name = sys.argv[2]

env = {}

with open('.jenv', 'r') as f:
    env = json.loads(f.read())

if 'worlds' in env:
    worlds = env['worlds']
    version_world = [ w for w in worlds if w['version'] == version ]
    version_world[0]['world_name'] = new_world_name 

print(json.dumps(env, indent=4))

with open('.jenv', 'wb') as f:
    f.write(json.dumps(env, indent=4).encode('utf-8'))

