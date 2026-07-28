# WSJT-X Log Monitor Utility

A lightweight, fully graphical toolset designed to monitor, duplicate, and report metrics on WSJT-X ADIF (`.adi`) log files in real time. This utility bypasses restrictive Windows execution policies and operates entirely out of a native, dark-themed Windows desktop GUI. Especially great for SOTA or POTA activations.

## File Manifest & Directory Layout

To run the application properly, place both files in the **exact same folder** on your computer:

```text
[Your Target Folder]
 ├── Run_Monitor.cmd        <-- Double-click this to launch the application
 └── WSJT-X_Monitor.ps1     <-- Main application logic file
```

---

## Component Descriptions

### 1. `Run_Monitor.cmd` (The Launcher)
* **Purpose**: Serves as the safe entry point for the utility.
* **Functionality**: 
  * Automatically targets the directory where it resides, making the tool fully portable.
  * Launches PowerShell with a temporary security flag (`-ExecutionPolicy Bypass`), allowing the script to run without altering your system's permanent security policies.
  * Safely hands off execution to the background engine and closes itself cleanly.

### 2. `WSJT-X_Monitor.ps1` (The Application Engine)
* **Purpose**: Handles the user interface, file tracking, and live data parsing.
* **Functionality**:
  * **Hides the Console**: Utilizes the native Windows `user32.dll` API to instantly hide the command prompt window upon launch, keeping your workspace clean.
  * **Graphical Prompts**: Displays native Windows dialogue boxes and input fields for session configuration instead of text-based console prompts.
  * **Automated Timestamps**: Dynamically generates custom filenames pre-filled with the active UTC date string (e.g., `20260727_xxxxx.adi`).
  * **Delta-Tracking Sync**: Safely monitors the primary WSJT-X log file without causing file-lock conflicts. When WSJT-X writes a new contact, the engine isolates only the new data bytes and streams them to your custom log.
  * **Metrics Aggregation**: Scans the file using a case-insensitive regex engine targeting the standard `<call:X>` ADIF tag to maintain an accurate count of unique callsigns.
  * **Dynamic UI Dashboard**: Hosts a dark-mode GUI frame that updates metrics instantly when new rows are logged, while refreshing the session timer precisely every 60 seconds.

---

## Technical Specifications

| Metric | Specification |
| :--- | :--- |
| **Interface Framework** | Dark Mode Native GUI (`System.Windows.Forms`) |
| **Resource Management** | Low CPU/RAM footprint; idle loop handled via background hardware timers |
| **Regex Match Engine** | `(?i)<call:\d+>([a-z0-9/]+)` (Supports standard and portable/mobile indicators) |
| **File Sharing Protocol** | `[System.IO.FileShare]::ReadWrite` (Eliminates app conflicts and locking errors) |
| **Process Cleanup** | Absolute termination of background loops (`Stop-Process -Id $PID`) upon closing the window |

---

## How to Use

1. Copy both `Run_Monitor.cmd` and `WSJT-X_Monitor.ps1` into your preferred directory.
2. Double-click `Run_Monitor.cmd`.
3. Choose whether you want to create a new `.adi` log file for your current session:
   * **Click No**: The dashboard opens and monitors your default `wsjtx_log.adi` file.
   * **Click Yes**: Enter a custom suffix for your filename. The tool creates the file, switches the dashboard target to it, and mirrors all incoming contacts from WSJT-X into it in real time.
4. Close the dashboard window at any time to fully stop monitoring and exit the program.
