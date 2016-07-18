for ($i=1; $i -le 10; $i++) {
    Write-Host "`nIteration Number=$i" -ForegroundColor Yellow
    .\run-command-linux.ps1 -ImageName 'amzn-ami-hvm-*gp2'

    Write-Host "`nIteration Number=$i" -ForegroundColor Yellow
    .\run-command-linux.ps1 -ImageName 'ubuntu/images/hvm-ssd/ubuntu-*-14.*'

    Write-Host "`nIteration Number=$i" -ForegroundColor Yellow
    .\run-command-windows.ps1 -ImageName 'WINDOWS_2012R2_BASE'
}
