#! /usr/bin/pwsh

# Author: fireph

# This script allows you to save an Android screen recording to your computer into a GIF that is less than 10MB. 
# The 10MB limit is imposed by Github but can be changed directly in the code.
# Gif optimizations were possible thanks to these resources:
# - https://cassidy.codes/blog/2017/04/25/ffmpeg-frames-to-gif-optimization/ 
# - https://engineering.giphy.com/how-to-make-gifs-with-ffmpeg/
# - https://www.lcdf.org/gifsicle/man.html

# Based on bash version here: https://gist.github.com/sdjidjev/8b720e75ba3892233f19ff078a2abc7f

# For easy access, add this to your profile.ps1:
# New-Alias android_gif c:\path\to\script\android_gif.ps1

# Feel free to change any of the options below.
# -----------------------------

# Folder to store GIFs. Feel free to change. It will create this directory if it does not exist already.
$FOLDER = "$HOME\Videos\android_gifs\"

# Filename for the converted GIF.
$FILENAME = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Maximum output GIF file size in MB.
$MAX_FILE_SIZE_MB = 10

# If set to $true, the video file in $FOLDER will not be delete when GIF conversion is finished.
$KEEP_VIDEO = $false

# Will enable "show_touches" system setting during the recording if set to $true
$SHOW_TOUCHES = $true

# Possible output sizes/framerates (width,fps).
$GIF_DIMENS = @(480,30),@(480,15),@(360,15),@(240,15)

# Possible lossy values for gifsicle.
$GIFSICLE_LOSSY_VALS = 20,40,60,80,100,120,140,160,180,200

# Maximum number of Powershell threads. Only change this if you are running into issues.
$MAX_THREADS = 50

# The bitrate of the video that is recorded on device. Only change this if you are running into issues.
$VIDEO_BITRATE = 8000000

# DO NOT CHANGE BELOW THIS LINE
# -----------------------------

if (!(Test-Path $FOLDER)) {
    New-Item -ItemType directory -Path $FOLDER | Out-Null
}

$MB = 1024 * 1024

$MAXFILESIZE = $MAX_FILE_SIZE_MB * $MB

Function Test-CommandExists($command) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {if(Get-Command $command){RETURN $true}}
    Catch {Write-Host "$command does not exist"; RETURN $false}
    Finally {$ErrorActionPreference=$oldPreference}
}

if (!(Get-Module -ListAvailable -Name ThreadJob)) {
    Write-Host -ForegroundColor red "Module ThreadJob must be installed. Run 'Install-Module -Name ThreadJob' in an Admin Powershell."
    exit
}

$dependencies = "ffmpeg","gifsicle","adb"

if (Test-CommandExists scoop) {
    foreach ($dep in $dependencies) {
        if (!(Test-CommandExists $dep)) {
            Read-Host -Prompt "${dep} is required for android_gif. Press [Enter] to scoop install ${dep}..." | Out-Null
            scoop install $dep
        }
    }
} else {
    foreach ($dep in $dependencies) {
        if (!(Test-CommandExists $dep)) {
            Write-Host -ForegroundColor red "${dep} is required for android_gif. Install it into your path or install scoop."
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

$video
$argpath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($args[0])
if (Test-Path -Path $argpath -PathType leaf) {
    $video = $argpath
    $FILENAME = (Get-Item $video).Basename + "_" + $FILENAME
    $KEEP_VIDEO = $true
} else {
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

    # Wake up device so that recording can start correctly
    adb -s $deviceid shell input keyevent KEYCODE_WAKEUP

    $prev_show_touches = adb shell settings get system show_touches
    if ($SHOW_TOUCHES) {
        adb shell settings put system show_touches 1 | Out-Null
    }

    $full_android_path = "/sdcard/${FILENAME}.mp4"

    # Wrap in try/finally so that cleanup still happens when you Ctrl-C 
    try {
        # start recording job
        $adb_job = Start-ThreadJob -ScriptBlock {
            Param($deviceid, $full_android_path, $VIDEO_BITRATE)
            adb -s $deviceid shell screenrecord --bit-rate $VIDEO_BITRATE $full_android_path
        } -ArgumentList $deviceid,$full_android_path,$VIDEO_BITRATE
        Write-Host -ForegroundColor green "Recording started on device!"
        # Upon a key press
        Read-Host -Prompt "Press [Enter] to stop recording..." | Out-Null
        Write-Host "Waiting for video on device..."
        # Kills the recording process
        Remove-Job -Job $adb_job -Force
        # Waiting for the device to compile the video
        Start-Sleep -s 3
        # Download the video
        adb -s $deviceid pull $full_android_path $FOLDER
    } finally {
        # Delete the video from the device
        adb -s $deviceid shell rm $full_android_path

        # revert "show_touches" setting
        if ($SHOW_TOUCHES) {
            adb shell settings put system show_touches $prev_show_touches | Out-Null
        }
    }
    $video = Join-Path -Path $FOLDER -ChildPath "${FILENAME}.mp4"
}

# Wrap in try/finally so that cleanup still happens when you Ctrl-C 
try {
    Function show_progress($jobs, $activity) {
        $total_jobs = $jobs.Count
        $completed_jobs = 0
        while ($completed_jobs -lt $total_jobs) {
            $completed_jobs = 0
            foreach ($j in $jobs) {
                if (@("Completed", "Failed") -contains $j.State) {
                    $completed_jobs += 1
                }
            }
            [int]$percent_complete = ($completed_jobs / $total_jobs) * 100
            Write-Progress -Activity $activity -Status "${percent_complete}% Complete:" -PercentComplete $percent_complete
            Start-Sleep -Seconds 0.5
        }
    }

    Function get_working_folder($gif_dimen) {
        $width = $gif_dimen[0]
        $fps = $gif_dimen[1]
        return Join-Path -Path $FOLDER -ChildPath "${FILENAME}_${width}_${fps}"
    }

    Function generate_gifsicles($ffmpeg_gif) {
        $working_folder = Split-Path -Path $ffmpeg_gif -Parent
        $gifsicle_jobs = [System.Collections.ArrayList]::new()
        foreach ($lossy_val in $GIFSICLE_LOSSY_VALS) {
            [void]$gifsicle_jobs.Add(
                (Start-ThreadJob -ScriptBlock {
                    Param(
                        $ffmpeg_gif,
                        $working_folder,
                        $lossy_val
                    )

                    Function create_gifsicle_gif($inputfile, $outputfile, $lossy) {
                        $threads = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
                        gifsicle -O2 --threads=$threads --no-conserve-memory --lossy=$lossy $inputfile -o $outputfile
                    }

                    $gif_path = Join-Path -Path $working_folder -ChildPath "${lossy_val}.gif"
                    create_gifsicle_gif $ffmpeg_gif $gif_path $lossy_val
                    return $gif_path
                } -ThrottleLimit $MAX_THREADS -ArgumentList $ffmpeg_gif,$working_folder,$lossy_val)
            )
        }
        return $gifsicle_jobs
    }

    # ffmpeg does not like it when the video is super short
    if ((Get-Item $video).length -gt 102400) {
        # Convert video to gif to be small enough to attach to GHE PRs
        $start_time = (Get-Date)

        $video_width,$video_height = (ffprobe -v error -select_streams v:0 -show_entries stream="width,height" -of csv=p=0 $video).Split(",")
        $aspect = $video_width / $video_height

        $ffmpeg_jobs = [System.Collections.ArrayList]::new()
        foreach ($gif_dimen in $GIF_DIMENS) {
            $working_folder = get_working_folder $gif_dimen
            [void]$ffmpeg_jobs.Add(
                (Start-ThreadJob -ScriptBlock {
                    Param(
                        $video,
                        $working_folder,
                        $gif_dimen,
                        $aspect
                    )
                    $width = $gif_dimen[0]
                    $fps = $gif_dimen[1]

                    if (!(Test-Path $working_folder)) {
                        New-Item -ItemType directory -Path $working_folder | Out-Null
                    }

                    Function create_ffmpeg_gif($inputfile, $outputfile, $fps, $width) {
                        $scale = "${width}:-1"
                        if ($aspect -gt 1) {
                            $scale = "-1:${width}"
                        }
                        ffmpeg -v error -i $inputfile -filter_complex "[0:v] fps=${fps},scale=${scale}:flags=lanczos,split [a][b];[a] palettegen=stats_mode=diff [p];[b][p] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y $outputfile
                        return $outputfile
                    }

                    $ffmpeg_gif = Join-Path -Path $working_folder -ChildPath "ffmpeg.gif"
                    return create_ffmpeg_gif $video $ffmpeg_gif $fps $width
                } -ThrottleLimit $MAX_THREADS -ArgumentList $video,$working_folder,$gif_dimen,$aspect)
            )
        }

        # Show progress ffmpeg
        show_progress $ffmpeg_jobs "(1/2) Converting video to gif with ffmpeg" | Out-Null

        $ffmpeg_gif_paths = $ffmpeg_jobs | Wait-Job | Receive-Job

        $gifsicle_jobs = [System.Collections.ArrayList]::new()
        foreach ($ffmpeg_gif_path in $ffmpeg_gif_paths) {
            $ffmpeg_gif_size = (Get-Item $ffmpeg_gif_path).length
            if ($ffmpeg_gif_size -gt $MAXFILESIZE) {
                [void]$gifsicle_jobs.AddRange(
                    (generate_gifsicles $ffmpeg_gif_path)
                )
            } else {
                # placeholder job since the ffmpeg gif is below max size
                [void]$gifsicle_jobs.Add(
                    (Start-ThreadJob -ScriptBlock {
                        Param($ffmpeg_gif_path)
                        return $ffmpeg_gif_path
                    } -ThrottleLimit $MAX_THREADS -ArgumentList $ffmpeg_gif_path)
                )
            }
        }

        # Show progress gifsicle
        show_progress $gifsicle_jobs "(2/2) Optimizing gif with gifsicle" | Out-Null

        $gifsicle_gif_paths = $gifsicle_jobs | Wait-Job | Receive-Job

        $gif_path = ""
        $gif_size = 0
        foreach ($gifsicle_gif_path in $gifsicle_gif_paths) {
            $gif_path = $gifsicle_gif_path
            $gif_size = (Get-Item $gif_path).length
            if ($gif_size -lt $MAXFILESIZE) {
                break
            }
        }

        $final_gif_path = Join-Path -Path $FOLDER -ChildPath "${FILENAME}.gif"
        Copy-Item $gif_path -Destination $final_gif_path

        if ($gif_size -gt $MAXFILESIZE) {
            Write-Host -ForegroundColor red "Unable to reduce gif size below ${MAX_FILE_SIZE_MB}MB!"
        }

        $end_time = (Get-Date)
        $elapsed_time_seconds = (New-TimeSpan $start_time $end_time).Seconds

        $gif_size_mb = ($gif_size / $MB).ToString("#.##")
        Write-Host -ForegroundColor green "Generated ${gif_size_mb}MB gif in ${elapsed_time_seconds} seconds at ${final_gif_path}"
    } else {
        Write-Host -ForegroundColor red "Recording is too short. Record a longer video."
    }
} finally {
    # Remove working files
    Remove-Item -Path (Join-Path -Path $FOLDER -ChildPath "${FILENAME}_*") -Recurse

    if (!($KEEP_VIDEO)) {
        Remove-Item -Path $video
    }
}
