# Rules for Claude in this repo

This is a Roblox game ("Scooter Duo 2 player obby") with **two places** in one experience, synced to Roblox Studio with Rojo.

## Layout
- `src/shared/` – scripts used by **both** places (identical in each). Put changes here by default.
- `src/world1/` – scripts only in World 1 (Scooter Duo 2 player obby), or that differ from World 2.
- `src/world2/` – scripts only in World 2, or that differ from World 1.
- `world1.project.json` / `world2.project.json` – one Rojo project per place. **Generated, don't hand-edit.**
- `tools/gen_projects.py` – rebuilds both project files. Run `python3 tools/gen_projects.py` after adding, removing or renaming any script, and commit the result.
- `tools/containers.json` – Roblox class of every folder, GUI or model that holds a script. Add an entry when a script goes into a new container.

Folders under `src/<x>/` mirror the exact path in Studio, e.g. `src/shared/ReplicatedStorage/ScooterSystem/Horn.luau` is `ReplicatedStorage.ScooterSystem.Horn`. A path must exist in only one of `shared` or a `worldN` folder. To make a shared script place-specific, move it from `shared` into **both** `world1` and `world2`.

File names: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.

Only scripts are synced. Parts, models, GUIs, RemoteEvents, Sounds etc. stay in Studio (Rojo ignores them), so changes to those must be done by hand in Studio. `ServerStorage` (backups and builder tools) is not in the repo.

## Rules (always follow)
1. **Never wipe player save data.** Never change DataStore names, keys or scopes, never call RemoveAsync or overwrite saves with empty or default data, and keep new save formats backwards-compatible with old saves.
2. **Don't touch anything the user didn't ask about.** No unrequested refactors, renames, reformatting or "cleanups".
3. **"Audit only" means change nothing.** Just report what you find.
4. **Every change works in both places** unless the user says otherwise. Prefer `src/shared/`, and check both `worldN` folders for anything the change affects.
5. **After every change, tell the user:**
   - what to test in World 1 and what to test in World 2
   - anything they must do by hand in Studio (parts, GUIs or settings that aren't in this repo)
   - anything to **delete by hand in Studio**: Rojo does not delete things in Studio, so removed or renamed scripts leave old copies behind.
