# powershell_scripts
Variety of Powershell scripts I have created

Add these to your aliases.ps1

```
Function Run-Android-Gif {pwsh -ExecutionPolicy Bypass -File (Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "android_gif.ps1") $args}
    New-Alias android_gif Run-Android-Gif

Function Run-Android-Png {pwsh -ExecutionPolicy Bypass -File (Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "android_png.ps1") $args}
    New-Alias android_png Run-Android-Png

Function Run-HDR-DoVi-Merge {pwsh -ExecutionPolicy Bypass -File (Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "hdr_dovi_merge.ps1") $args}
    New-Alias hdr_dovi_merge Run-HDR-DoVi-Merge
```
