"""Rebuild world1.project.json and world2.project.json from the src/ folders.

Each script file maps to the same path in Studio, e.g.
  src/shared/ReplicatedStorage/ScooterSystem/Horn.luau -> ReplicatedStorage.ScooterSystem.Horn
A place gets everything in src/shared plus its own src/worldN folder.
Folders, GUIs and models around the scripts are NOT synced: their class comes
from tools/containers.json and every node ignores unknown instances, so Rojo
leaves everything else in Studio alone.

Run after adding, removing or renaming a script:  python3 tools/gen_projects.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACES = {"world1": 34872, "world2": 34873}
SUFFIXES = [".server.luau", ".client.luau", ".luau"]
containers = json.load(open(os.path.join(ROOT, "tools", "containers.json")))


def scripts_in(folder):
    base = os.path.join(ROOT, "src", folder)
    for dirpath, _, files in os.walk(base):
        for f in files:
            suffix = next((s for s in SUFFIXES if f.endswith(s)), None)
            if suffix is None:
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), base).replace(os.sep, "/")
            parts = rel[: -len(suffix)].split("/")
            yield parts, "src/" + folder + "/" + rel


def build(place):
    tree = {"$className": "DataModel"}
    owner = {}
    for folder in ("shared", place):
        for parts, file in scripts_in(folder):
            key = "/".join(parts)
            if key in owner:
                sys.exit(f"{key} is in both {owner[key]} and {file}")
            owner[key] = file
            node = tree
            for i, name in enumerate(parts):
                node = node.setdefault(name, {})
                node["$ignoreUnknownInstances"] = True
                if i == len(parts) - 1:
                    node["$path"] = file
                elif "$path" not in node and "$className" not in node:
                    sub = "/".join(parts[: i + 1])
                    cls = containers.get(sub) or (name if i == 0 else None)
                    if cls is None:
                        sys.exit(f"Add the class of {sub} to tools/containers.json")
                    node["$className"] = cls
    # a node that is a script with script children must not also carry $className
    def clean(node):
        for k, v in node.items():
            if isinstance(v, dict):
                if "$path" in v:
                    v.pop("$className", None)
                clean(v)
    clean(tree)
    return {"name": place, "servePort": PLACES[place], "tree": tree}


for place in PLACES:
    with open(os.path.join(ROOT, place + ".project.json"), "w", newline="\n") as f:
        json.dump(build(place), f, indent=2, sort_keys=True)
        f.write("\n")
    print("wrote", place + ".project.json")
