# Importing and exporting profiles

This article explains how to save a profile to a JSON file and how to load a profile from a file.

Use export and import to keep a copy of a profile, to share it, or to move it to a different Mac.

## Export a profile

1. Open the **Profiles** pane.
1. Select the profile.
1. Click **Profile actions**, then select **Export**.
1. Select a folder and a file name. The default name is `PROFILE-NAME.json`.
1. Click **Save**.

The command line equivalent prints the profile JSON, or writes it to a file. The examples use the `ojd` alias. For more information, see [Using the command line](../command-line/using-the-command-line.md).

```shell
ojd map export PROFILE --output FILE.json
```

## Import a profile

1. Open the **Profiles** pane.
1. Click **Import profile**.
1. Select a JSON file.
1. Click **Open**.

The command line equivalent is:

```shell
ojd map import FILE.json
```

OJD checks the file before it adds the profile. OJD rejects a file with unknown keys, values out of range, or a size above 4 MiB.

## What happens on import

- If the library has a profile with the same `id`, the imported profile replaces it.
- If the library has no profile with that `id`, OJD adds the imported profile.
- If a different profile already uses the same name, OJD rejects the import.
- If the replaced profile was active and the imported profile has a different controller model, OJD deactivates it.

A new imported profile is not active until you activate it. For more information, see [Creating a profile](creating-a-profile.md).

## Further reading

- [Profile file reference](profile-file-reference.md)
- [App crashes or does not start](../troubleshooting/app-crashes-or-does-not-start.md)
