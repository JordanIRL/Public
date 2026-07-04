# Get-M365UsersAndLicenses.ps1
# Description: This script queries Microsoft 365 via Microsoft Graph API to retrieve a list of all users and their assigned licenses.

# ===============================================================
# PREREQUISITES & SETUP
# ===============================================================
# Ensure the Microsoft Graph PowerShell module is installed:
# Install-Module Microsoft.Graph -Scope CurrentUser

# Required Scopes for connection: 
# User.Read.All (to read user properties) and LicenseAssignment.Read (to read license assignments).
# You must be authenticated with permissions granting these scopes.
# ===============================================================

function Get-M365UsersAndLicenses {
    [CmdletBinding()]
    param()

    Write-Host "Attempting to connect to Microsoft Graph..." -ForegroundColor Yellow

    try {
        # Connect using the recommended method. This will prompt for interactive login if not already authenticated.
        Connect-MgGraph -Scopes "User.Read.All", "LicenseAssignment.Read" | Out-Null
        Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green

        $Users = Get-MgUser -All -Property Id, DisplayName, Mail, UserPrincipalName, AssignedLicenses

        if (-not $Users) {
            Write-Warning "No users found in the directory."
            return @()
        }

        $Results = foreach ($User in $Users) {
            # Initialize license details
            $LicenseList = @()

            # Iterate through assigned licenses and extract meaningful information
            if ($User.AssignedLicenses -ne $null) {
                foreach ($LicenseAssignment in $User.AssignedLicenses) {
                    # Note: To get the friendly name of the SKU, you often need to call another endpoint 
                    # or reference a known Graph schema ID. This example fetches the raw SKUID.
                    $SkuId = $LicenseAssignment.SkuId

                    # A real-world script would perform an additional lookup here (e.g., Get-MgSubscribedSku) 
                    # to map SkuId to friendly names, but we provide a basic structure for demonstration.
                    $LicenseList += [PSCustomObject]@{
                        SKUId = $SkuId
                        # Placeholder for License Name - requires additional API call or local lookup
                        LicenseName = "Unknown SKU ($SkuId)" 
                    }
                }
            }

            # Construct the final custom object for this user
            [PSCustomObject]@{
                UserPrincipalName = $User.UserPrincipalName
                DisplayName       = $User.DisplayName
                Email             = $User.Mail
                LicenseDetails    = ($LicenseList | Select-Object SKUId, LicenseName) # Output license details as a nested object/array
            }
        }

        Write-Host "`nSuccessfully retrieved data for $($Users.Count) users." -ForegroundColor Green
        return $Results

    } catch {
        Write-Error "An error occurred while connecting or retrieving user data: $($_.Exception.Message)"
        Write-Warning "Please ensure you have the necessary permissions and are correctly authenticated with Connect-MgGraph."
        return $null
    } finally {
        # Optional: Disconnect when done
        # Disconnect-MgGraph -Confirm:$false 
    }
}

# ===============================================================
# EXECUTION BLOCK
# ===============================================================

# Execute the function and store results
$UserLicenseData = Get-M365UsersAndLicenses

if ($UserLicenseData) {
    Write-Host "`n--- User and License Data Retrieved ---" -ForegroundColor Cyan
    
    # Display a summary table of users (Note: complex nested objects like license details 
    # may not display cleanly in basic PowerShell tables, so CSV export is recommended.)
    $UserLicenseData | Format-Table -AutoSize

    # Export the detailed data to a CSV file for easier consumption and analysis
    $ExportPath = "M365_Users_and_Licenses.csv"
    Write-Host "`nExporting detailed results to: $ExportPath" -ForegroundColor Cyan
    
    # We need to handle nested objects before exporting cleanly, flattening the structure if possible, 
    # but for this initial script, we export the custom object as is.
    $UserLicenseData | Export-Csv -Path $ExportPath -NoTypeInformation

    Write-Host "`nProcess complete. Data saved to $ExportPath" -ForegroundColor Green
} else {
     Write-Host "`nScript execution failed or returned no data." -ForegroundColor Red
}