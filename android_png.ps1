#! /usr/bin/pwsh

# Author: fireph

# This script allows you to save Android screenshots to your computer with a single command. 

# For easy access, add this to your profile.ps1:
# New-Alias android_png c:\path\to\script\android_png.ps1

# Feel free to change any of the options below.
# -----------------------------

# Folder to store PNGs. Feel free to change. It will create this directory if it does not exist already.
$FOLDER = "$HOME\Pictures\android_pngs\"

# Filename for the PNG.
$FILENAME = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Minimum width/height for the screenshot (will not resize if set to -1)
$MIN_SIZE = 480

# DO NOT CHANGE BELOW THIS LINE
# -----------------------------

if (!(Test-Path $FOLDER)) {
    New-Item -ItemType directory -Path $FOLDER | Out-Null
}

$MB = 1024 * 1024

Function Test-CommandExists($command) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {if(Get-Command $command){RETURN $true}}
    Catch {Write-Host "$command does not exist"; RETURN $false}
    Finally {$ErrorActionPreference=$oldPreference}
}

$dependencies = @{
    "convert" = "imagemagick";
    "optipng" = "optipng";
    "adb" = "adb"
}

if (Test-CommandExists scoop) {
    foreach ($dep in $dependencies.GetEnumerator()) {
        if (!(Test-CommandExists $dep.Name)) {
            Read-Host -Prompt "$($dep.Value) is required for android_png. Press [Enter] to scoop install $($dep.Value)..." | Out-Null
            scoop install $dep.Value
        }
    }
} else {
    foreach ($dep in $dependencies.GetEnumerator()) {
        if (!(Test-CommandExists $dep.Name)) {
            Write-Host -ForegroundColor red "$($dep.Value) is required for android_png. Install it into your path or install scoop."
            exit
        }
    }
}

Function get_android_devices {
    $list = [System.Collections.ArrayList]::new()
    foreach ($line in adb devices -l) {
        if ($line -match ".*model:.*") {
            [void]$list.Add($line)
        }
    }
    return ,$list
}

$devices = get_android_devices

# Wait for device if none are connected
if ($devices.Count -eq 0) {
  Write-Host -ForegroundColor red "No adb devices found! Waiting for a device to be connected..."
}
do {
    Start-Sleep -s 1
    $devices = get_android_devices
} until ($devices.Count -gt 0)

# Get device ID and prompt user if there are multiple devices
$deviceindex = 0
if ($devices.Count -gt 1) {
    Write-Host "Devices:"
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $exists = $devices[$i] -match "^[0-9A-Z]+"
        $deviceid = $matches[0]
        $exists = $devices[$i] -match "model:[^ ]+"
        $model = $matches[0]
        Write-Host -ForegroundColor yellow "${i} -- ${model} id:${deviceid}"
    }
    $deviceindex = Read-Host -Prompt "Enter index of device you want to screen record (eg. 0)"
    while (!(($deviceindex -ge 0) -and ($deviceindex -lt $devices.Count))) {
        $deviceindex = Read-Host -Prompt "Invaild device index! Enter index (eg. 0)"
    }
}
$exists = $devices[$deviceindex] -match "^[0-9A-Z]+"
$deviceid = $matches[0]

# Wake up device so that screenshot can start correctly
adb -s $deviceid shell input keyevent KEYCODE_WAKEUP

$full_android_path = "/sdcard/${FILENAME}.png"
$png_path = Join-Path -Path $FOLDER -ChildPath "${FILENAME}.png"

Write-Host "Taking screenshot and downloading from device..."
adb -s $deviceid shell screencap -p $full_android_path | Out-Null
adb -s $deviceid pull $full_android_path $png_path | Out-Null
adb -s $deviceid shell rm $full_android_path | Out-Null

if ($MIN_SIZE -gt 0) {
    Write-Host "Resizing screenshot..."
    convert $png_path -geometry "${MIN_SIZE}x${MIN_SIZE}^" $png_path | Out-Null
}

Write-Host "Optimizing PNG..."
optipng -quiet $png_path | Out-Null

$png_size = (Get-Item $png_path).length
$png_size_mb = ($png_size / $MB).ToString("#.##")
Write-Host -ForegroundColor green "Generated ${png_size_mb}MB PNG at ${png_path}"
