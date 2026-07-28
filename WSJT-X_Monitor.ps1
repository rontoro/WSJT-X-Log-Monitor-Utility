Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    "Do you want to create a new .adi file?", 
    "Create New Log File", 
    [System.Windows.Forms.MessageBoxButtons]::YesNo, 
    [System.Windows.Forms.MessageBoxIcon]::Question,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2
)

$newFileActive = $false
$newFilePath = ""

if ($msgBoxResult -eq [System.Windows.Forms.DialogResult]::Yes) {
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

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($userInput)) {
        if ($userInput -eq $defaultName) { $userInput += "session" }
        if ($userInput -notlike "*.adi") { $userInput += ".adi" }
        
        $newFilePath = Join-Path $folder $userInput
        
        if (Test-Path $newFilePath) {
            $overwriteResult = [System.Windows.Forms.MessageBox]::Show(
                "The file '$userInput' already exists.`n`nDo you want to overwrite it and clear its contents?", 
                "Warning: File Exists", 
                [System.Windows.Forms.MessageBoxButtons]::YesNo, 
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )
            if ($overwriteResult -ne [System.Windows.Forms.DialogResult]::Yes) {
                # Fall back to monitoring the original file safely
                $global:monitoredFilePath = $filePath
                $global:fileCreationUtc = (Get-Item $filePath).CreationTimeUtc
                Update-GuiDashboard
                return
            }
        }
        
        New-Item -Path $newFilePath -ItemType "File" -Force | Out-Null
        $global:lastOriginalSize = (Get-Item $filePath).Length
        $newFileActive = $true
        $global:originalLogPath = $filePath
        $filePath = $newFilePath
    }

}

# Capture metadata
$global:monitoredFilePath = $filePath
$global:fileCreationUtc = (Get-Item $filePath).CreationTimeUtc

# --- MAIN WINDOWS FORMS GUI INITIALIZATION ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSJT-X Log Monitor Dashboard"
$form.Size = New-Object System.Drawing.Size(480, 240)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

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

$lblFile     = Add-DashboardRow "1. File Name:" 20 ([System.Drawing.Color]::White)
$lblCreated  = Add-DashboardRow "2. Created (UTC):" 55 ([System.Drawing.Color]::White)
$lblElapsed  = Add-DashboardRow "3. Elapsed Time:" 90 ([System.Drawing.Color]::LightGreen)
$lblUnique   = Add-DashboardRow "4. Unique Calls:" 125 ([System.Drawing.Color]::Gold)

# --- REFRESH ENGINE ---
function Update-GuiDashboard {
    try {
        $uniqueCalls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if (Test-Path $global:monitoredFilePath) {
            $stream = New-Object System.IO.FileStream($global:monitoredFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            
            $matches = [regex]::Matches($content, '(?i)<call:\d+>([a-z0-9/]+)')
            foreach ($match in $matches) {
                # Pull raw inner regex capture group values accurately
                $null = $uniqueCalls.Add($match.Groups[1].Value)
            }
        }
        $duration = (Get-Date).ToUniversalTime() - $global:fileCreationUtc
        $hours = [math]::Floor($duration.TotalHours)
        $minutes = $duration.Minutes
        
        $lblFile.Text    = Split-Path $global:monitoredFilePath -Leaf
        $lblCreated.Text = $global:fileCreationUtc.ToString("yyyy-MM-dd HH:mm:ss")
        $lblElapsed.Text = "${hours} hrs, ${minutes} mins"
        $lblUnique.Text  = $uniqueCalls.Count.ToString()
    } catch {}
}

# --- BACKGROUND MONITORING TIMERS & WATCHERS ---
$guiTimer = New-Object System.Windows.Forms.Timer
$guiTimer.Interval = 5000 
$guiTimer.Add_Tick({ Update-GuiDashboard })
$guiTimer.Start()

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = Split-Path $filePath
$watcher.Filter = Split-Path $filePath -Leaf
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$watcherAction = {
    $form.Invoke([Action]{ Update-GuiDashboard })
}
Register-ObjectEvent $watcher "Changed" -Action $watcherAction | Out-Null

if ($newFileActive) {
    $global:newFilePathCopy = $newFilePath
    $origWatcher = New-Object System.IO.FileSystemWatcher
    $origWatcher.Path = Split-Path $global:originalLogPath
    $origWatcher.Filter = Split-Path $global:originalLogPath -Leaf
    $origWatcher.EnableRaisingEvents = $true
    
    $copyAction = {
        try {
            $currentSize = (Get-Item $global:originalLogPath).Length
            if ($currentSize -gt $global:lastOriginalSize) {
                $origStream = New-Object System.IO.FileStream($global:originalLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $origStream.Seek($global:lastOriginalSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = New-Object System.IO.StreamReader($origStream)
                $newContent = $reader.ReadToEnd()
                $reader.Close()
                $origStream.Close()
                
                if (-not [string]::IsNullOrEmpty($newContent)) {
                    $targetStream = New-Object System.IO.FileStream($global:newFilePathCopy, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                    $writer = New-Object System.IO.StreamWriter($targetStream)
                    $writer.Write($newContent)
                    $writer.Close()
                    $targetStream.Close()
                }
                $global:lastOriginalSize = $currentSize
            }
        } catch {}
    }
    Register-ObjectEvent $origWatcher "Changed" -Action $copyAction | Out-Null
}

# Initial Population & Load UI Window Loop
Update-GuiDashboard
[System.Windows.Forms.Application]::Run($form)

$watcher.Dispose()
if ($newFileActive) { $origWatcher.Dispose() }

Stop-Process -Id $PID
