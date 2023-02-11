#!/usr/bin/env python3 

import sys 
import json 

opt_lookup = {
    '-w': 'world_name',    
    '-h': 'hash',
    '-m': 'gamemode',
    '-p': 'target_platform'
}

def _usage():
    print(f'Usage:')
    print(f'\t{sys.argv[0]} add -v VERSION [OPTION]..')
    print(f'\t{sys.argv[0]} update -v VERSION [OPTION]..')
    print(f'\t{sys.argv[0]} delete -v VERSION')
    print(f'\t{sys.argv[0]} list')
    print(f'\n\tOPTIONS:')
    print('\t\t%s' % "\n\t\t".join([ "%s: %s" % (key, opt_lookup[key]) for (i, key) in enumerate(opt_lookup) ]))

def _update_world(world, opts):
    for opt in opts.keys():
        world[opt] = opts[opt] 

def _lookup_world(worlds, version):
    version_worlds = [ w for w in worlds if w['version'] == version ]
    if len(version_worlds) > 0:
        return version_worlds[0]            
    return None 

if len(sys.argv) < 2:
    _usage()
    sys.exit(1)

action = sys.argv[1]
version = None 
opts = {}

skip = False 
for i, arg in enumerate(sys.argv[2:], 2):
    if skip:
        skip = False 
        continue
    if arg in opt_lookup.keys():
        opts[opt_lookup[arg]] = sys.argv[i+1]
        skip = True 
    elif arg == '-v':
        version = sys.argv[i+1]
        skip = True 

if (not version and action in ['add', 'update', 'delete']) or action not in ['add', 'update', 'delete', 'list']:
    _usage()
    sys.exit(1)

env = {}

with open('.jenv', 'r') as f:
    env = json.loads(f.read())

if 'worlds' in env:
    
    version_world = _lookup_world(env['worlds'], version)
    
    if action == 'update' and not version_world:
        raise Exception(f'No world for version {version} to update')
    elif action == 'add' and version_world:
        raise Exception(f'World for version {version} already exists')
    elif action == 'delete' and not version_world:
        raise Exception(f'No world for version {version} to delete')

    if action == 'list':
        print(json.dumps(env['worlds'], indent=4))
    else:
        if action == 'delete':
            env['worlds'] = [ w for w in env['worlds'] if w['version'] != version ]
        else:
            if not version_world:
                version_world = {
                    'version': version 
                }
                env['worlds'].append(version_world)
            _update_world(version_world, opts)

        print(json.dumps(env, indent=4))

        with open('.jenv', 'wb') as f:
            f.write(json.dumps(env, indent=4).encode('utf-8'))

