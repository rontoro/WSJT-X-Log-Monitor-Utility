# WSJT-X Log Monitor Utility

A lightweight, fully graphical utility for monitoring, duplicating, and reporting metrics on WSJT-X ADIF (`.adi`) log files in real time. It is designed to be easy to launch on Windows without changing PowerShell execution policy, and it uses a dark-themed desktop GUI that is well suited to SOTA or POTA activations.

## File Manifest & Directory Layout

To run the application properly, place the files in the same folder on your computer:

```text
[Your Target Folder]
├── WSJT-X Monitor.vbs       <-- Double-click this to launch the utility
└── WSJT-X_Monitor.ps1       <-- Main application logic file
```

> The VBScript launcher is now the recommended entry point for users.

---

## Component Descriptions

### 1. `WSJT-X Monitor.vbs` (The Launcher)
* **Purpose**: Serves as the user-facing entry point for the utility.
* **Functionality**:
  * Launches the PowerShell script from the same folder.
  * Uses `powershell.exe` with `-ExecutionPolicy Bypass` so it can run without changing system-wide policy settings.
  * Keeps the startup experience simple for end users.

### 2. `WSJT-X_Monitor.ps1` (The Application Engine)
* **Purpose**: Handles the user interface, file tracking, and live data parsing.
* **Functionality**:
  * **Hides the Console**: Uses the native Windows `user32.dll` API to hide the background console window on launch.
  * **Graphical Prompts**: Displays native Windows dialog boxes and input fields instead of text-based prompts.
  * **Automated Timestamps**: Creates custom filenames pre-filled with the current UTC date string (for example, `20260728_xxxxx.adi`).
  * **Delta-Tracking Sync**: Monitors the original WSJT-X log file safely and mirrors new contacts into the selected output file.
  * **Metrics Aggregation**: Scans the file for standard ADIF `<call:X>` values and keeps a count of unique callsigns.
  * **Dynamic UI Dashboard**: Updates the dashboard in real time as new contacts are logged.

---

## Technical Specifications

| Metric | Specification |
| :--- | :--- |
| **Interface Framework** | Dark Mode Native GUI (`System.Windows.Forms`) |
| **Resource Management** | Low CPU/RAM footprint; idle loop handled by background timers |
| **Regex Match Engine** | `(?i)<call:\d+>([a-z0-9/]+)` (supports standard and portable/mobile indicators) |
| **File Sharing Protocol** | `[System.IO.FileShare]::ReadWrite` (avoids file-lock conflicts) |
| **Process Cleanup** | Stops background monitoring loops when the dashboard is closed |

---

## How to Use

1. Copy `WSJT-X Monitor.vbs` and `WSJT-X_Monitor.ps1` into your preferred directory.
2. Double-click `WSJT-X Monitor.vbs`.
3. Choose whether you want to create a new `.adi` log file for the current session:
   * **Click No**: The dashboard opens and monitors your existing default `wsjtx_log.adi` file.
   * **Click Yes**: Enter a custom suffix for the filename. The tool creates the file, switches the dashboard target to it, and mirrors incoming contacts from WSJT-X into it in real time.
4. Close the dashboard window at any time to fully stop monitoring and exit the program.

### Configuration
On its first run, the utility automatically generates a `config.json` file in the application directory.
* To change the target log directory, edit `config.json` and update the `OriginalFilePath` string.
* Ensure you use double backslashes (`\\`) in the JSON path value.
