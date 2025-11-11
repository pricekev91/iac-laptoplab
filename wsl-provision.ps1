# Define variables
$DistroName = "Ubuntu-MKI"
$DistroFile = "C:\wsl\distro\ubuntu-24.04.3-wsl-amd64.gz"
$InstallLocation = "C:\wsl\instances\$DistroName"

# Check if the distro is already registered
$existingDistros = wsl --list --quiet
if ($existingDistros -contains $DistroName) {
    Write-Host "⚠️  WSL instance '$DistroName' is already registered."
    Write-Host "This will unregister and delete the existing instance at:"
    Write-Host "    $InstallLocation"
    Write-Host ""
    $confirmation = Read-Host "Type 'CONTINUE' to proceed with deletion and reinstallation"

    if ($confirmation -ne "CONTINUE") {
        Write-Host "❌ Operation cancelled."
        exit
    }

    # Unregister the existing instance
    Write-Host "🧹 Unregistering existing WSL instance..."
    wsl --unregister $DistroName

    # Remove install directory
    if (Test-Path $InstallLocation) {
        Write-Host "🧹 Removing existing install directory..."
        Remove-Item -Recurse -Force $InstallLocation
    }
}

# Create install directory if it doesn't exist
if (-Not (Test-Path $InstallLocation)) {
    New-Item -ItemType Directory -Path $InstallLocation | Out-Null
}

# Register the distro
Write-Host "📦 Importing WSL instance '$DistroName'..."
wsl --import $DistroName $InstallLocation $DistroFile --version 2

# Set as default
wsl --set-default $DistroName

Write-Host "✅ WSL instance '$DistroName' has been registered and set as default."
