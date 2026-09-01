Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Debug: Show startup message
Write-Host "WSJT-X Monitor starting - QSO count badge feature active" -ForegroundColor Cyan

# Win32 API to hide the background console window instantly
$ShowWindowAsyncCode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$Win32ShowWindowAsync = Add-Type -MemberDefinition $ShowWindowAsyncCode -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru
$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
$consoleHandle = $currentProcess.MainWindowHandle

# Hide console right away
if ($consoleHandle -ne [IntPtr]::Zero) {
    $null = $Win32ShowWindowAsync::ShowWindowAsync($consoleHandle, 0)
}

# --- CONFIGURATION FILE HANDLING ---
$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$filePath = ""

# Load config if it exists
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $filePath = $config.OriginalFilePath
    } catch {
        # Silent fallback if JSON is corrupted
    }
}

# If no path found or file doesn't exist, prompt with File Browser Dialogue
if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path $filePath)) {
    $fileBrowser = New-Object System.Windows.Forms.OpenFileDialog
    $fileBrowser.Title = "Select your original WSJT-X .adi log file"
    $fileBrowser.Filter = "ADIF Files (*.adi)|*.adi|All Files (*.*)|*.*"
    $fileBrowser.InitialDirectory = [Environment]::GetFolderPath("LocalApplicationData")
    
    $browserResult = $fileBrowser.ShowDialog()
    
    if ($browserResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $filePath = $fileBrowser.FileName
        # Save choice to config.json
        $configObject = @{ "OriginalFilePath" = $filePath }
        $configObject | ConvertTo-Json | Out-File $configPath -Encoding utf8
    } else {
        # User closed browser without picking a file; close application gracefully
        Stop-Process -Id $PID
    }
}

$folder = Split-Path $filePath

# --- WINDOWS-BASED YES/NO PROMPT ---
$msgBoxResult = [System.Windows.Forms.MessageBox]::Show(
    "Do you want to create a secondary .adi file for logging this session?", 
    "Create New Log File", 
    [System.Windows.Forms.MessageBoxButtons]::YesNo, 
    [System.Windows.Forms.MessageBoxIcon]::Question,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2
)

$newFileActive = $false
$newFilePath = ""

if ($msgBoxResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    $createNewFileChosen = $false

    while (-not $createNewFileChosen) {
        $inputForm = New-Object System.Windows.Forms.Form
        $inputForm.Text = "New Log Filename"
        $inputForm.Size = New-Object System.Drawing.Size(400, 160)
        $inputForm.StartPosition = "CenterScreen"
        $inputForm.FormBorderStyle = "FixedDialog"
        $inputForm.MaximizeBox = $false
        $inputForm.MinimizeBox = $false
        $inputForm.TopMost = $true

        $utcDateStr = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
        $defaultName = "${utcDateStr}_"

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = "Enter a name for the new file:"
        $lblInput.Location = New-Object System.Drawing.Point(20, 15)
        $lblInput.Size = New-Object System.Drawing.Size(340, 20)
        $inputForm.Controls.Add($lblInput)

        $txtInput = New-Object System.Windows.Forms.TextBox
        $txtInput.Text = $defaultName
        $txtInput.Location = New-Object System.Drawing.Point(20, 40)
        $txtInput.Size = New-Object System.Drawing.Size(340, 25)
        $txtInput.SelectionStart = $txtInput.Text.Length
        $inputForm.Controls.Add($txtInput)

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.Location = New-Object System.Drawing.Point(200, 80)
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $inputForm.AcceptButton = $btnOk
        $inputForm.Controls.Add($btnOk)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(285, 80)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $inputForm.CancelButton = $btnCancel
        $inputForm.Controls.Add($btnCancel)

        $dialogResult = $inputForm.ShowDialog()
        $userInput = $txtInput.Text
        $inputForm.Dispose()

        if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($userInput)) {
            break
        }

        if ($userInput -eq $defaultName) { $userInput += "session" }
        if ($userInput -notlike "*.adi") { $userInput += ".adi" }

        $newFilePath = Join-Path $folder $userInput

        if (Test-Path $newFilePath) {
            $overwriteForm = New-Object System.Windows.Forms.Form
            $overwriteForm.Text = "Warning: File Exists"
            $overwriteForm.Size = New-Object System.Drawing.Size(430, 190)
            $overwriteForm.StartPosition = "CenterScreen"
            $overwriteForm.FormBorderStyle = "FixedDialog"
            $overwriteForm.MaximizeBox = $false
            $overwriteForm.MinimizeBox = $false
            $overwriteForm.TopMost = $true

            $lblOverwrite = New-Object System.Windows.Forms.Label
            $lblOverwrite.Text = "The file '$userInput' already exists.`n`nChoose an action:"
            $lblOverwrite.Location = New-Object System.Drawing.Point(20, 15)
            $lblOverwrite.Size = New-Object System.Drawing.Size(380, 60)
            $overwriteForm.Controls.Add($lblOverwrite)

            $btnOverwrite = New-Object System.Windows.Forms.Button
            $btnOverwrite.Text = "Overwrite"
            $btnOverwrite.Location = New-Object System.Drawing.Point(20, 95)
            $btnOverwrite.Size = New-Object System.Drawing.Size(110, 32)
            $btnOverwrite.DialogResult = [System.Windows.Forms.DialogResult]::Yes
            $overwriteForm.Controls.Add($btnOverwrite)

            $btnNo = New-Object System.Windows.Forms.Button
            $btnNo.Text = "Cancel"
            $btnNo.Location = New-Object System.Drawing.Point(145, 95)
            $btnNo.Size = New-Object System.Drawing.Size(110, 32)
            $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No
            $overwriteForm.Controls.Add($btnNo)

            $btnMonitor = New-Object System.Windows.Forms.Button
            $btnMonitor.Text = "Monitor This File"
            $btnMonitor.Location = New-Object System.Drawing.Point(270, 95)
            $btnMonitor.Size = New-Object System.Drawing.Size(140, 32)
            $btnMonitor.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $overwriteForm.Controls.Add($btnMonitor)

            $overwriteResult = $overwriteForm.ShowDialog()
            $overwriteForm.Dispose()

            if ($overwriteResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                [System.IO.File]::WriteAllText($newFilePath, "")
                $global:lastOriginalSize = (Get-Item $filePath).Length
                $newFileActive = $true
                $global:originalLogPath = $filePath
                $filePath = $newFilePath
                $createNewFileChosen = $true
                break
            }

            if ($overwriteResult -eq [System.Windows.Forms.DialogResult]::Cancel) {
                $global:lastOriginalSize = (Get-Item $filePath).Length
                $global:monitoredFilePath = $newFilePath
                $global:originalLogPath = $filePath
                $global:newFilePathCopy = $newFilePath
                $global:fileCreationUtc = (Get-Item $newFilePath).CreationTimeUtc
                $newFileActive = $true
                $filePath = $newFilePath
                $createNewFileChosen = $true
                break
            }

            continue
        }

        New-Item -Path $newFilePath -ItemType "File" -Force | Out-Null
        $global:lastOriginalSize = (Get-Item $filePath).Length
        $newFileActive = $true
        $global:originalLogPath = $filePath
        $filePath = $newFilePath
        $createNewFileChosen = $true
        break
    }
}

# Capture metadata
$global:monitoredFilePath = $filePath
if (-not $newFileActive) {
    $global:originalLogPath = $filePath
    $global:lastOriginalSize = (Get-Item $global:originalLogPath).Length
} else {
    $global:lastOriginalSize = (Get-Item $global:originalLogPath).Length
}
$global:fileCreationUtc = (Get-Item $global:monitoredFilePath).CreationTimeUtc

# --- TRAY ICON SETUP ---
# Create tray icon that will show the badge
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Visible = $true
$trayIcon.Text = "QSOs: 0 - WSJT-X Log Monitor"

# Create tray icon context menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$showMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$showMenuItem.Text = "Show"
$showMenuItem.Add_Click({
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Show()
    $form.Activate()
})
$contextMenu.Items.Add($showMenuItem)

$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitMenuItem.Text = "Exit"
$exitMenuItem.Add_Click({
    $form.Close()
})
$contextMenu.Items.Add($exitMenuItem)

$trayIcon.ContextMenuStrip = $contextMenu

# Double-click to show window
$trayIcon.Add_DoubleClick({
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Show()
    $form.Activate()
})

# --- MAIN WINDOWS FORMS GUI INITIALIZATION ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "QSOs: 0 - WSJT-X Log Monitor"
$form.Size = New-Object System.Drawing.Size(530, 280)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

# Add Load event to update dashboard after form is shown
$form.Add_Load({
    Start-Sleep -Milliseconds 100
    Update-GuiDashboard
})

$labelFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$valueFont = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Regular)

function Add-DashboardRow ($text, $top, $valueColor) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(20, $top)
    $label.Size = New-Object System.Drawing.Size(150, 25)
    $label.ForeColor = [System.Drawing.Color]::DarkGray
    $label.Font = $labelFont
    $form.Controls.Add($label)

    $valLabel = New-Object System.Windows.Forms.Label
    $valLabel.Location = New-Object System.Drawing.Point(170, $top)
    $valLabel.Size = New-Object System.Drawing.Size(280, 25)
    $valLabel.ForeColor = $valueColor
    $valLabel.Font = $valueFont
    $form.Controls.Add($valLabel)
    return $valLabel
}

$lblFile     = Add-DashboardRow "File Name:" 20 ([System.Drawing.Color]::White)
$lblCreated  = Add-DashboardRow "Created (UTC):" 55 ([System.Drawing.Color]::White)
$lblElapsed  = Add-DashboardRow "Elapsed Time:" 90 ([System.Drawing.Color]::LightGreen)
$lblUnique   = Add-DashboardRow "Unique Calls:" 125 ([System.Drawing.Color]::Gold)

$btnOpenFile = New-Object System.Windows.Forms.Button
$btnOpenFile.Text = "Open File"
$btnOpenFile.Location = New-Object System.Drawing.Point(20, 180)
$btnOpenFile.Size = New-Object System.Drawing.Size(120, 32)
$btnOpenFile.ForeColor = [System.Drawing.Color]::White
$btnOpenFile.Add_Click({
    if (Test-Path $global:monitoredFilePath) {
        Start-Process -FilePath $global:monitoredFilePath | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("The monitored file could not be found.", "Open File") | Out-Null
    }
})
$form.Controls.Add($btnOpenFile)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(290, 180)
$btnClose.Size = New-Object System.Drawing.Size(120, 32)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.Add_Click({
    $form.Close()
})
$form.Controls.Add($btnClose)

$btnOpenDir = New-Object System.Windows.Forms.Button
$btnOpenDir.Text = "Open Directory"
$btnOpenDir.Location = New-Object System.Drawing.Point(155, 180)
$btnOpenDir.Size = New-Object System.Drawing.Size(120, 32)
$btnOpenDir.ForeColor = [System.Drawing.Color]::White
$btnOpenDir.Add_Click({
    $fileDir = Split-Path $global:monitoredFilePath
    if (Test-Path $fileDir) {
        explorer.exe $fileDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("The file directory could not be found.", "Open Directory") | Out-Null
    }
})
$form.Controls.Add($btnOpenDir)

# --- REFRESH ENGINE ---
function Update-TaskbarBadge {
    param([int]$Count)
    
    # Update window title with QSO count
    if ($null -ne $form -and -not $form.IsDisposed) {
        try {
            $form.Text = "QSOs: $Count - WSJT-X Log Monitor"
        } catch {
            # Silent fail
        }
    }
    
    # Update tray icon tooltip with QSO count at the start
    if ($null -ne $trayIcon -and -not $trayIcon.IsDisposed) {
        try {
            $trayIcon.Text = "QSOs: $Count - WSJT-X Log Monitor"
        } catch {
            # Silent fail
        }
    }
}

function Get-UniqueCallCount {
    param(
        [string]$Path
    )

    $uniqueCalls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path $Path)) { return 0 }

    $attempts = 0
    while ($attempts -lt 5) {
        try {
            $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $reader.Dispose()
            } finally {
                $stream.Dispose()
            }

            $matches = [regex]::Matches($content, '(?i)<\s*call:\d+>\s*([a-z0-9/]+)')
            foreach ($match in $matches) {
                $null = $uniqueCalls.Add($match.Groups[1].Value)
            }
            return $uniqueCalls.Count
        } catch {
            $attempts++
            if ($attempts -ge 5) { return $uniqueCalls.Count }
            Start-Sleep -Milliseconds 250
        }
    }

    return $uniqueCalls.Count
}

function Update-GuiDashboard {
    try {
        $uniqueCount = Get-UniqueCallCount $global:monitoredFilePath
        $duration = (Get-Date).ToUniversalTime() - $global:fileCreationUtc
        $hours = [math]::Floor($duration.TotalHours)
        $minutes = $duration.Minutes
        
        $lblFile.Text    = Split-Path $global:monitoredFilePath -Leaf
        $lblCreated.Text = $global:fileCreationUtc.ToString("yyyy-MM-dd HH:mm:ss")
        $lblElapsed.Text = "${hours} hrs, ${minutes} mins"
        $lblUnique.Text  = $uniqueCount.ToString()
        
        # Update taskbar badge
        Update-TaskbarBadge $uniqueCount
    } catch {}
}

# --- BACKGROUND MONITORING TIMERS & WATCHERS ---
$guiTimer = New-Object System.Windows.Forms.Timer
$guiTimer.Interval = 5000 
$guiTimer.Add_Tick({ Update-GuiDashboard })
$guiTimer.Start()

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = Split-Path $global:monitoredFilePath
$watcher.Filter = Split-Path $global:monitoredFilePath -Leaf
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$watcherAction = {
    $form.Invoke([Action]{ Update-GuiDashboard })
}
foreach ($eventName in @("Changed", "Created", "Deleted", "Renamed")) {
    Register-ObjectEvent $watcher $eventName -Action $watcherAction | Out-Null
}

if ($newFileActive) {
    $global:newFilePathCopy = $newFilePath
    $origWatcher = New-Object System.IO.FileSystemWatcher
    $origWatcher.Path = Split-Path $global:originalLogPath
    $origWatcher.Filter = Split-Path $global:originalLogPath -Leaf
    $origWatcher.EnableRaisingEvents = $true
    
    $copyAction = {
        try {
            $currentSize = (Get-Item $global:originalLogPath).Length
            if ($currentSize -le $global:lastOriginalSize) { return }

            $attempts = 0
            while ($attempts -lt 10) {
                try {
                    $origStream = New-Object System.IO.FileStream($global:originalLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $origStream.Seek($global:lastOriginalSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $reader = New-Object System.IO.StreamReader($origStream)
                        $newContent = $reader.ReadToEnd()
                        $reader.Dispose()
                    } finally {
                        $origStream.Dispose()
                    }

                    if (-not [string]::IsNullOrEmpty($newContent)) {
                        $targetStream = New-Object System.IO.FileStream($global:newFilePathCopy, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                        try {
                            $writer = New-Object System.IO.StreamWriter($targetStream)
                            $writer.Write($newContent)
                            $writer.Flush()
                            $writer.Dispose()
                        } finally {
                            $targetStream.Dispose()
                        }
                    }

                    $global:lastOriginalSize = $currentSize
                    return
                } catch {
                    $attempts++
                    if ($attempts -ge 10) { return }
                    Start-Sleep -Milliseconds 100
                }
            }
        } catch {}
    }
    foreach ($eventName in @("Changed", "Created", "Renamed")) {
        Register-ObjectEvent $origWatcher $eventName -Action $copyAction | Out-Null
    }
}

# --- BACKGROUND MONITORING TIMERS & WATCHERS ---
$guiTimer = New-Object System.Windows.Forms.Timer
$guiTimer.Interval = 5000 
$guiTimer.Add_Tick({ Update-GuiDashboard })
$guiTimer.Start()

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = Split-Path $global:monitoredFilePath
$watcher.Filter = Split-Path $global:monitoredFilePath -Leaf
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$watcherAction = {
    $form.Invoke([Action]{ Update-GuiDashboard })
}
foreach ($eventName in @("Changed", "Created", "Deleted", "Renamed")) {
    Register-ObjectEvent $watcher $eventName -Action $watcherAction | Out-Null
}

if ($newFileActive) {
    $global:newFilePathCopy = $newFilePath
    $origWatcher = New-Object System.IO.FileSystemWatcher
    $origWatcher.Path = Split-Path $global:originalLogPath
    $origWatcher.Filter = Split-Path $global:originalLogPath -Leaf
    $origWatcher.EnableRaisingEvents = $true
    
    $copyAction = {
        try {
            $currentSize = (Get-Item $global:originalLogPath).Length
            if ($currentSize -le $global:lastOriginalSize) { return }

            $attempts = 0
            while ($attempts -lt 10) {
                try {
                    $origStream = New-Object System.IO.FileStream($global:originalLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $origStream.Seek($global:lastOriginalSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $reader = New-Object System.IO.StreamReader($origStream)
                        $newContent = $reader.ReadToEnd()
                        $reader.Dispose()
                    } finally {
                        $origStream.Dispose()
                    }

                    if (-not [string]::IsNullOrEmpty($newContent)) {
                        $targetStream = New-Object System.IO.FileStream($global:newFilePathCopy, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                        try {
                            $writer = New-Object System.IO.StreamWriter($targetStream)
                            $writer.Write($newContent)
                            $writer.Flush()
                            $writer.Dispose()
                        } finally {
                            $targetStream.Dispose()
                        }
                    }

                    $global:lastOriginalSize = $currentSize
                    return
                } catch {
                    $attempts++
                    if ($attempts -ge 10) { return }
                    Start-Sleep -Milliseconds 100
                }
            }
        } catch {}
    }
    foreach ($eventName in @("Changed", "Created", "Renamed")) {
        Register-ObjectEvent $origWatcher $eventName -Action $copyAction | Out-Null
    }
}

# Display form and run application loop
[System.Windows.Forms.Application]::Run($form)

# Cleanup
$trayIcon.Visible = $false
$trayIcon.Dispose()
$watcher.Dispose()
if ($newFileActive) { $origWatcher.Dispose() }

Stop-Process -Id $PID
