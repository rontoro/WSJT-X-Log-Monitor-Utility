# WSJT-X Log Monitor Utility

A lightweight Windows utility for monitoring WSJT-X ADIF (`.adi`) log files in real time. It opens a compact dark-themed dashboard that shows file activity, elapsed time, and a live count of unique callsigns.

## Files in This Repository

```text
[Your Target Folder]
├── WSJT-X Monitor.vbs       <-- Double-click this to launch the tool
├── WSJT-X_Monitor.ps1       <-- Main application logic
├── config.json              <-- Stores the selected original log path
└── README.md                <-- This documentation
```

## How It Works

The utility starts by asking you to choose the original WSJT-X ADIF file to monitor. If the file path was used previously, it will reuse the saved value from `config.json`.

From there, you can choose whether to:

- monitor the existing original file directly, or
- create a new `.adi` file for the current session.

If you choose to create a new file, the script prompts for a filename. If that file already exists, you can choose one of three actions:

- `Overwrite` - clear the existing file and start monitoring it
- `Cancel` - return to the filename prompt so you can choose a different name
- `Monitor This File` - start monitoring the existing file directly without creating or overwriting anything

## Dashboard Features

The dashboard displays:

- the monitored file name
- the file creation time in UTC
- elapsed time since monitoring started
- the current count of unique callsigns found in the file

It also includes two action buttons:

- `Open File` - opens the currently monitored file in its default editor/app
- `Close` - stops the monitor and closes the dashboard

## Running the Utility

1. Copy the files from this folder to your preferred working directory.
2. Double-click `WSJT-X Monitor.vbs`.
3. Follow the prompts to select the WSJT-X `.adi` file and choose whether to create a new session file.
4. Close the dashboard window at any time to stop monitoring and exit the program.

## Configuration

On first run, the utility saves the selected original file path to `config.json`.

Example:

```json
{
  "OriginalFilePath": "C:\\Users\\YourName\\AppData\\Local\\WSJT-X\\wsjtx_log.adi"
}
```

If you want to change the monitored source file later, edit `config.json` and update the `OriginalFilePath` value.

## Notes

- The script uses native Windows dialogs and a dark-themed Windows Forms interface.
- It watches the selected file and updates the dashboard automatically as new entries appear.
- The utility is designed for Windows and is intended to be launched without changing PowerShell execution policy.
