# run-jml.ps1 - runs the whole JML engine in order. Used by the scheduled task "PDS JML Engine",
# which runs as the gMSA PDS\gmsa-jml$ with: powershell.exe -NoProfile -NonInteractive -File run-jml.ps1
$Log = "C:\PDS\logs\jml-run-$(Get-Date -Format yyyy-MM-dd_HHmm).log"
Start-Transcript -Path $Log | Out-Null
"=== PDS JML engine | running as $(whoami) | $(Get-Date) ==="

foreach ($s in "03-joiner.ps1", "04-mover.ps1", "05-leaver.ps1", "06-sod-check.ps1") {
    "`n--- $s ---"
    try   { & "C:\PDS\scripts\$s" -Apply }
    catch { "ERROR in $s : $($_.Exception.Message)" }
}

"`n=== done $(Get-Date) ==="
Stop-Transcript | Out-Null
