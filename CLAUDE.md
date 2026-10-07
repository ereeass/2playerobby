# Rules for Claude in this repo

This is a Roblox game ("Scooter Duo 2 player obby") with **two places** in one experience, synced to Roblox Studio with Rojo.

## Layout
- `src/shared/` – code used by **both** places. Put changes here by default.
- `src/world1/` – code only for World 1 (Scooter Duo 2 player obby).
- `src/world2/` – code only for World 2.
- `world1.project.json` / `world2.project.json` – one Rojo project per place.

In Studio, each service gets a `Shared` folder (from `src/shared/...`) and a `Place` folder (from `src/worldN/...`). Shared code can `require` `ReplicatedStorage.Place.<Module>` to read place-specific settings.

File names: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.

## Rules (always follow)
1. **Never wipe player save data.** Never change DataStore names, keys or scopes, never call RemoveAsync or overwrite saves with empty or default data, and keep new save formats backwards-compatible with old saves.
2. **Don't touch anything the user didn't ask about.** No unrequested refactors, renames, reformatting or "cleanups".
3. **"Audit only" means change nothing.** Just report what you find.
4. **Every change works in both places** unless the user says otherwise. Prefer `src/shared/`, and check both `worldN` folders for anything the change affects.
5. **After every change, tell the user:**
   - what to test in World 1 and what to test in World 2
   - anything they must do by hand in Studio (parts, GUIs or settings that aren't in this repo)
   - anything to **delete by hand in Studio**: Rojo does not delete things in Studio, so removed or renamed scripts leave old copies behind.
