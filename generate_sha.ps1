# SHA-1 & SHA-256 Certificate Generator for Google Sign-In / Firebase
# PowerShell Script for Windows

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SHA-1 & SHA-256 Certificate Generator" -ForegroundColor Yellow
Write-Host "for Google Sign-In / Firebase" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if keytool is available
$keytool = Get-Command keytool -ErrorAction SilentlyContinue

if (-not $keytool) {
    Write-Host "ERROR: keytool not found!" -ForegroundColor Red
    Write-Host "Please ensure Java JDK is installed and added to PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "You can find keytool in your Java installation, typically at:" -ForegroundColor Yellow
    Write-Host "C:\Program Files\Java\jdk-XX\bin\keytool.exe" -ForegroundColor Yellow
    exit 1
}

Write-Host "1. Debug Keystore SHA Keys:" -ForegroundColor Green
Write-Host "-------------------------------------------"

# Debug keystore location (default for Windows)
$debugKeystore = "$env:USERPROFILE\.android\debug.keystore"

if (Test-Path $debugKeystore) {
    Write-Host "Location: $debugKeystore" -ForegroundColor Cyan
    Write-Host ""
    
    $output = & keytool -list -v -keystore $debugKeystore -alias androiddebugkey -storepass android -keypass android 2>&1
    
    $output | Select-String -Pattern "SHA1:|SHA256:" | ForEach-Object {
        Write-Host $_.Line -ForegroundColor White
    }
    Write-Host ""
} else {
    Write-Host "Warning: Debug keystore not found at: $debugKeystore" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host ""
Write-Host "2. Release Keystore SHA Keys (if exists):" -ForegroundColor Green
Write-Host "-------------------------------------------"

# Check for release keystore in common locations
$releaseKeystoreLocations = @(
    "android\app\upload-keystore.jks",
    "android\app\release-keystore.jks",
    "android\app\key.jks",
    "android\keystore.jks"
)

$foundRelease = $false

foreach ($keystore in $releaseKeystoreLocations) {
    if (Test-Path $keystore) {
        Write-Host "Found release keystore: $keystore" -ForegroundColor Cyan
        
        $keystorePassword = Read-Host "Enter the keystore password" -AsSecureString
        $keystorePasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keystorePassword)
        )
        
        $keyAlias = Read-Host "Enter the key alias"
        Write-Host ""
        
        $output = & keytool -list -v -keystore $keystore -alias $keyAlias -storepass $keystorePasswordPlain 2>&1
        
        $output | Select-String -Pattern "SHA1:|SHA256:" | ForEach-Object {
            Write-Host $_.Line -ForegroundColor White
        }
        Write-Host ""
        
        $foundRelease = $true
        break
    }
}

if (-not $foundRelease) {
    Write-Host "Warning: No release keystore found in common locations" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Instructions:" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "1. Copy the SHA-1 fingerprint from above"
Write-Host "2. Go to Firebase Console:"
Write-Host "   https://console.firebase.google.com" -ForegroundColor Blue
Write-Host "3. Select your project: waste-collection-truck-tracker"
Write-Host "4. Go to Project Settings -> Your apps"
Write-Host "5. Select your Android app (com.example.driver_app)"
Write-Host "6. Add the SHA-1 certificate fingerprint"
Write-Host "7. Download the updated google-services.json"
Write-Host "8. Replace android/app/google-services.json"
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
