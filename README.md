# Remove Logi Options+ from macOS

This script removes **Logi Options+** and its local data from a Mac. It is intended for people who want a clean removal, including the background services and Keychain items that can remain after deleting the app. It does **not** uninstall other Logitech products.

## Before you run it

- This permanently deletes local Options+ settings and customizations. Make a backup first if you may want them later.
- Run it from the macOS account that used Options+, **without** prefixing the command with `sudo`. You need administrator access for system files; the script asks for it when needed.
- The default run is a preview. Read its list of paths and Keychain items before choosing to delete anything.
- If several macOS accounts used Options+, run the script once from each account. System files need to be removed only once, but each account has its own settings and Keychain.

## Run

Open Terminal in this repository's directory and run:

```sh
./uninstall-logi-options-plus.sh
```

This **preview makes no changes**. It lists the files and Keychain items found for your account. The `[system]` entries require administrator access; `[user]` entries belong to the current account; `[Keychain]` entries are credentials identified by their metadata. The preview does not display passwords.

If the list matches what you want to remove, run:

```sh
./uninstall-logi-options-plus.sh --execute
```

The script stops the Options+ launch agents and updater, removes the listed files, deletes matching generic-password entries from accessible user Keychains, and attempts to reset permissions for the Options+ bundle IDs. It reports deletion failures and exits with an error if a file or Keychain item could not be removed. **Restart the Mac afterward** so macOS can clear cached background and login items.

## Scope and limits

The cleanup covers the app, Options+ driver installer, its `launchd` agent and daemon, system and user Application Support data, preferences, caches, logs, saved state, and matching Keychain items. It searches selected Library directories for names tied to Options+; the preview shows the exact matches on your Mac.

Shared Logitech components such as `LogiPluginService` and `LogiRightSightForWebcams` are left in place because other Logitech software may use them. The script does not delete an entire Keychain or other users' data. A locked or inaccessible Keychain may prevent its items from being found; unlock it and rerun the preview and cleanup if needed. macOS may continue to show a stale login item until after the restart.
