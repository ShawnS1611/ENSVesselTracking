<#
.SYNOPSIS
Identifies XML files requiring GB customs filing, copies them, applies modifications and cleans characters.
AFTER processing, checks COPIED files for empty tags. Moves files with empty tags to a 'Problematic' subdirectory.
Accepts core values as parameters.

.DESCRIPTION
This script performs the following actions:
1. Accepts root ship directory, Voyage, Arrival Date as script parameters. The IMO is derived automatically.
2. Defines GB filing criteria (POU is GBLIV/GBBEL or later in route).
3. Iterates through XML files in expected subdirectories.
4. Determines vessel route using the derived IMO by calling an external routing function.
5. Checks files against GB filing criteria.
6. Stores details of files meeting criteria.
7. Creates 'GB-Filings' subdirectory.
8. Copies identified XML files to 'GB-Filings'.
9. Modifies the *copied* files by calling external functions for itinerary updates and applying local defaults.
10. Saves the modified copied files with formatting.
11. Checks the saved copied file for any empty tags (e.g., <Tag/> or <Tag></Tag> or <Tag>  </Tag>).
12. If empty tags are found, MOVES the file from 'GB-Filings' to 'GB-Filings\Problematic'.
13. Original files remain unchanged. Files without empty tags remain in 'GB-Filings'.

.PARAMETER RootShipDirectory
The root directory for the specific ship's XML files (e.g., \\192.168.50.2\Bor-Groupdata\Chartering\Import Control System\ICSXML\ADGA).

.PARAMETER VoyageNumber
The voyage number for the vessel (ConveyanceRefNum).

.PARAMETER ArrivalDateString
The expected arrival date in yyyyMMdd format.

.EXAMPLE
.\Prepare-ICS1GBLIVConversion.ps1 -RootShipDirectory "\\192.168.50.2\Bor-Groupdata\Chartering\Import Control System\ICSXML\ADGA123" -VoyageNumber "V001E" -ArrivalDateString "20240815"

.NOTES
Author: Shawn (Updated with Pair Programming suggestions)
Date Created: 11.04.2024
Current Version: 2.6 (Centralised itinerary logic)
Last Updated: 09.10.2025
Requires: PowerShell XML module, access to read/write files and create directories.
Depends on Get-VesselRoute.ps1 and IMONumber.ps1 at specified network paths.
Files moved to 'Problematic' require manual review.
#>

[CmdletBinding()] # Enables common parameters like -Verbose, -Debug, etc.
param(
    [Parameter(Mandatory=$true, HelpMessage="Please provide the root directory for the specific ship.")]
    [string]$RootShipDirectory,

    [Parameter(Mandatory=$true, HelpMessage="Enter the CORRECT Voyage number (ConveyanceRefNum).")]
    [string]$VoyageNumber,

    [Parameter(Mandatory=$true, HelpMessage="Enter the Arrival Date (ExpectedDateTimeOfArrival) in yyyyMMdd format.")]
    [ValidatePattern("^\d{8}$")] # Basic validation for 8 digits (yyyyMMdd)
    [string]$ArrivalDateString
)

#region Global Variables and Constants

# --- Shared Logic Locations ---
$imoHashtablePath = "\\192.168.50.2\Bor-Groupdata\Chartering\Import Control System\ICSExtract\IMONumber.ps1"
$routingScriptPath = "\\192.168.50.2\Bor-Groupdata\Chartering\Import Control System\ICSExtract\Get-VesselRoute.ps1"


# --- GB Filing Specific Defaults ---
$gbDefaultEntryPlaceRefNum = "GB000080"; $gbDefaultDeclPlace = "GBLIV"; $gbDefaultTin = "GB243408284000";
$gbTargetPort = "GBLIV"; $gbFilingsSubDir = "GB-Filings";
$gbAliasPort = "GBBEL" # Define the alias for GBLIV
# --- End GB Defaults ---

# --- Problematic Files Subdirectory ---
$problematicSubDir = "Problematic" # Name of subdir within GB-Filings
# --- End Problematic ---

# --- Expected Subdirectories ---
#$expectedDirectories = @("ESCAS","PTLEI","ITSAL")
$expectedDirectories = @("CYLMS","EGALY","ILASH","ILHFA","ITSAL","TRISK","ESCAS","PTLEI")
# --- End Expected Subdirectories ---

# --- XML Namespace ---
$namespaceUrl = "http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration"; $namespacePrefix = "ns";
# --- End Namespace ---

# --- Special Character Regex ---
$specialCharsRegex = '[&#$%*]'
# --- End Special Character Regex ---

#endregion

#region Helper Functions

function Set-XmlNodeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Xml.XmlDocument]$XmlDocument,

        [Parameter(Mandatory=$true)]
        [System.Xml.XmlNamespaceManager]$NamespaceManager,

        [Parameter(Mandatory=$true)]
        [string]$XPath,

        [Parameter(Mandatory=$true)]
        [string]$NewValue,

        [Parameter(Mandatory=$true)]
        [string]$NodeDescription, # e.g., "IdeOfMeaOfTraCro" for logging

        [Parameter(Mandatory=$true)]
        [ref]$ChangesMade # Pass the boolean flag by reference
    )

    try {
        $node = $XmlDocument.SelectSingleNode($XPath, $NamespaceManager)
        if ($null -ne $node) {
            if ($node.InnerText -ne $NewValue) {
                $node.InnerText = $NewValue
                Write-Verbose "   - Set <$NodeDescription> to '$NewValue'" # Changed to Write-Verbose
                $ChangesMade.Value = $true # Update the original variable
            }
        } else {
            Write-Warning "   - Node <$NodeDescription> not found using XPath '$XPath'."
        }
    } catch {
        Write-Warning "   - Error accessing node <$NodeDescription> with XPath '$XPath': $($_.Exception.Message)"
    }
}

#endregion Helper Functions

#region Initial Setup (using Parameters)

$xmlDirectory = $RootShipDirectory
if (-not (Test-Path $xmlDirectory -PathType Container)) {
    Write-Error "...Directory '$xmlDirectory' not found. Exiting."
    exit 1 # Explicitly exit with an error code
}

# --- Derive IMO from Directory ---
try {
    . $imoHashtablePath
    $fullVesselCode = (Split-Path $RootShipDirectory -Leaf).ToUpper()
    # The vessel code in the directory might include numbers (e.g., ADGA123), but the hashtable key is just the 4 letters.
    $vesselCode = $fullVesselCode.Substring(0, 4)
    $ImoNumber = $IMONumber[$vesselCode]
    if (-not $ImoNumber) {
        Write-Error "Could not find an IMO number for vessel code '$vesselCode' (derived from '$fullVesselCode') in the hashtable. Please check the directory path and IMONumber.ps1 file."
        exit 1
    }
} catch {
    Write-Error "Failed to load or process the IMO hashtable from '$imoHashtablePath'. Error: $($_.Exception.Message)"
    exit 1
}
# --- End IMO Derivation ---

# --- Load Routing Logic ---
try {
    . $routingScriptPath
} catch {
    Write-Error "Failed to load the routing logic from '$routingScriptPath'. Error: $($_.Exception.Message)"
    exit 1
}
# --- End Loading Routing Logic ---

# Assign parameters to variables used throughout the script (if preferred, or use parameters directly)
$userInputImo = $ImoNumber
$userInputVoyage = $VoyageNumber
$userInputArrivalDateTime = $ArrivalDateString + "0000"

Write-Host "`nProcessing files with the following parameters:" -ForegroundColor Yellow
Write-Host "Root Directory: $xmlDirectory" -ForegroundColor Cyan
Write-Host "Derived IMO: $userInputImo, Voyage: $userInputVoyage, Arrival: $userInputArrivalDateTime" -ForegroundColor Cyan

#endregion

#region Scan for Files

Write-Host "`nScanning for XML files in expected subdirectories..." -ForegroundColor Cyan
$allXmlFilesToCheck = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($expectedDir in $expectedDirectories) {
    $currentDirPath = Join-Path -Path $xmlDirectory -ChildPath $expectedDir
    if (Test-Path $currentDirPath -PathType Container) {
        # Ensure $foundFiles is always an array, even if Get-ChildItem returns a single object or $null
        $foundFiles = @(Get-ChildItem -Path $currentDirPath -Filter *.xml -File -ErrorAction SilentlyContinue)
        if ($foundFiles.Count -gt 0) { # Check if the array has items
            foreach ($fileInstance in $foundFiles) { # Iterate and add each file individually
                $allXmlFilesToCheck.Add($fileInstance)
            }
            Write-Host "Found $($foundFiles.Count) XML file(s) in $expectedDir" -ForegroundColor DarkGray
        }
        # No 'else' needed here for the case where no files are found in a specific directory; loop continues.
    } else {
        Write-Host "Expected directory '$expectedDir' not found, skipping." -ForegroundColor DarkGray
    }
}

if ($allXmlFilesToCheck.Count -eq 0) { Write-Host "No XML files found in any expected subdirectories. Nothing to process." -ForegroundColor Yellow; exit }
else { Write-Host "Found a total of $($allXmlFilesToCheck.Count) XML files to check..." -ForegroundColor Cyan }

#endregion

#region Identify Files for GB Filing (Using Derived IMO for Routing and GBBEL alias)

Write-Host "`nIdentifying files requiring GB filing (POU '$gbTargetPort'/'$gbAliasPort' or later based on route for IMO '$userInputImo')..." -ForegroundColor Cyan
$filesForGBFilingInfo = @()

# --- Determine Route by calling external function ---
$routeInfo = Get-VesselRoute -ImoNumber $userInputImo
if (-not $routeInfo) {
    Write-Error "Error: Derived IMO '$userInputImo' not found in any known routing arrays (via Get-VesselRoute.ps1). Cannot proceed."
    exit 1
}
$selectedRouting = $routeInfo.SelectedRouting
$vesselType = $routeInfo.VesselType
Write-Host "Determined route based on derived IMO '$userInputImo' is: $vesselType" -ForegroundColor DarkGray
# --- End Route Determination ---

foreach ($file in $allXmlFilesToCheck) {
    Write-Host "Checking file: $($file.Name)" -ForegroundColor White -NoNewline
    $requiresGBFiling = $false
    $errorMessage = $null
    $placeOfUnloading = $null

    try {
        [xml]$xmlContentCheck = Get-Content -Path $file.FullName -ErrorAction Stop
        $namespaceManagerCheck = New-Object System.Xml.XmlNamespaceManager($xmlContentCheck.NameTable)
        $namespaceManagerCheck.AddNamespace($namespacePrefix, $namespaceUrl)

        $placeOfUnloadingNode = $xmlContentCheck.SelectSingleNode("//$($namespacePrefix):PlaceOfUnloading", $namespaceManagerCheck)
        $placeOfUnloading = if ($null -ne $placeOfUnloadingNode) { $placeOfUnloadingNode.InnerText } else { $null }

        if (-not $placeOfUnloading) { $errorMessage = "Missing PlaceOfUnloading in file"; throw }

        $effectivePou = $placeOfUnloading
        if ($placeOfUnloading -eq $gbAliasPort) {
            $effectivePou = $gbTargetPort
            Write-Host " (POU is '$gbAliasPort', treating as '$gbTargetPort' for check)" -ForegroundColor DarkYellow -NoNewline
        }

        $gblivIndex = [Array]::IndexOf($selectedRouting, $gbTargetPort)
        $pouIndex = [Array]::IndexOf($selectedRouting, $effectivePou)

        if ($gblivIndex -eq -1) { Write-Host " - '$gbTargetPort' not in determined $vesselType route. Skipping." -ForegroundColor DarkGray }
        elseif ($pouIndex -eq -1) { $errorMessage = "Effective POU '$effectivePou' (Original: '$placeOfUnloading') from file not found in determined $vesselType route."; throw }
        elseif ($pouIndex -ge $gblivIndex) {
            $requiresGBFiling = $true
            Write-Host " - Meets criteria (Effective POU '$effectivePou' at index $pouIndex vs '$gbTargetPort' at index $gblivIndex in $vesselType route)." -ForegroundColor Green
        } else {
            Write-Host " - Does not meet criteria (Effective POU '$effectivePou' at index $pouIndex precedes '$gbTargetPort' at index $gblivIndex)." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host " - Error checking file $($file.Name): $($_.Exception.Message) $errorMessage" -ForegroundColor Red
    }

    if ($requiresGBFiling) {
        $fileInfo = [PSCustomObject]@{
            OriginalFullName = $file.FullName
            FileName         = $file.Name
            PlaceOfUnloading = $placeOfUnloading
            SelectedRouting  = $selectedRouting
        }
        $filesForGBFilingInfo += $fileInfo
    }
}

if ($filesForGBFilingInfo.Count -eq 0) { Write-Host "`nNo files identified requiring GB filing based on derived IMO route and POU check." -ForegroundColor Yellow; exit }
else { Write-Host "`nIdentified $($filesForGBFilingInfo.Count) file(s) for GB Filing." -ForegroundColor Cyan }

#endregion

#region Setup Output Directories

$gbFilingDirPath = Join-Path -Path $xmlDirectory -ChildPath $gbFilingsSubDir
Write-Host "`nEnsuring '$gbFilingsSubDir' directory exists at '$gbFilingDirPath'..." -ForegroundColor Cyan
if (-not (Test-Path $gbFilingDirPath -PathType Container)) {
    try {
        New-Item -Path $gbFilingDirPath -ItemType Directory -ErrorAction Stop | Out-Null
        Write-Host "Created directory: '$gbFilingDirPath'" -ForegroundColor Green
    } catch { Write-Error "Error creating directory '$gbFilingDirPath': $($_.Exception.Message). Exiting."; exit 1 }
} else { Write-Host "Directory '$gbFilingDirPath' already exists." -ForegroundColor DarkGray }

$problematicDirPath = Join-Path -Path $gbFilingDirPath -ChildPath $problematicSubDir
Write-Host "Ensuring '$problematicSubDir' directory exists at '$problematicDirPath'..." -ForegroundColor Cyan
if (-not (Test-Path $problematicDirPath -PathType Container)) {
    try {
        New-Item -Path $problematicDirPath -ItemType Directory -ErrorAction Stop | Out-Null
        Write-Host "Created directory: '$problematicDirPath'" -ForegroundColor Green
    } catch {
        Write-Warning "Error creating directory '$problematicDirPath': $($_.Exception.Message). Problematic files cannot be moved if this directory is not available."
        # Do not exit, but the problematic move functionality will fail later if dir still not available.
    }
} else { Write-Host "Directory '$problematicDirPath' already exists." -ForegroundColor DarkGray }

#endregion Setup Output Directories

#region Copy Files to GB-Filings Directory (and track copied paths)

$copiedFileDetails = @()
Write-Host "`nCopying identified files to '$gbFilingDirPath'..."
foreach ($fileInfo in $filesForGBFilingInfo) {
    $destinationPath = Join-Path -Path $gbFilingDirPath -ChildPath $fileInfo.FileName
    try {
        Copy-Item -Path $fileInfo.OriginalFullName -Destination $destinationPath -Force -ErrorAction Stop
        Write-Host "Copied '$($fileInfo.FileName)' to '$gbFilingsSubDir'" -ForegroundColor Green
        $detail = $fileInfo | Select-Object *
        $detail | Add-Member -MemberType NoteProperty -Name CopiedPath -Value $destinationPath
        $copiedFileDetails += $detail
    } catch {
        Write-Warning "Error copying file '$($fileInfo.FileName)' to '$destinationPath': $($_.Exception.Message)"
    }
}

if ($copiedFileDetails.Count -eq 0) { Write-Host "`nNo files were successfully copied. Nothing further to process." -ForegroundColor Yellow; exit }
elseif ($copiedFileDetails.Count -ne $filesForGBFilingInfo.Count) { Write-Warning "`nNot all identified files could be copied." }
else { Write-Host "`nSuccessfully copied $($copiedFileDetails.Count) file(s)." -ForegroundColor Cyan }

#endregion

#region Modify Copied Files & Check for Empty Tags

Write-Host "`nModifying copied files in '$gbFilingsSubDir' and checking for empty tags..." -ForegroundColor Cyan
$filesMovedToProblematic = 0

foreach ($detail in $copiedFileDetails) {
    Write-Host "--- Processing: $($detail.FileName) ---" -ForegroundColor White
    $changesMade = $false
    $foundEmptyTag = $false
    $currentFilePath = $detail.CopiedPath

    try {
        [xml]$xmlContent = Get-Content -Path $currentFilePath -Raw -ErrorAction Stop
        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
        $namespaceManager.AddNamespace($namespacePrefix, $namespaceUrl)

        # --- Apply User Input Values ---
        Write-Verbose "  Applying user-provided values..." # Changed to Write-Verbose for section header
        Set-XmlNodeValue -XmlDocument $xmlContent -NamespaceManager $namespaceManager -XPath "//${namespacePrefix}:IdeOfMeaOfTraCro" -NewValue $userInputImo -NodeDescription "IdeOfMeaOfTraCro" -ChangesMade ([ref]$changesMade)
        Set-XmlNodeValue -XmlDocument $xmlContent -NamespaceManager $namespaceManager -XPath "//${namespacePrefix}:ConveyanceRefNum" -NewValue $userInputVoyage -NodeDescription "ConveyanceRefNum" -ChangesMade ([ref]$changesMade)
        Set-XmlNodeValue -XmlDocument $xmlContent -NamespaceManager $namespaceManager -XPath "//${namespacePrefix}:ExpectedDateTimeOfArrival" -NewValue $userInputArrivalDateTime -NodeDescription "ExpectedDateTimeOfArrival" -ChangesMade ([ref]$changesMade)

        # --- Apply GB Defaults ---
        Write-Verbose "  Applying GB defaults..." # Changed to Write-Verbose
        Set-XmlNodeValue -XmlDocument $xmlContent -NamespaceManager $namespaceManager -XPath "//${namespacePrefix}:DeclPlace" -NewValue $gbDefaultDeclPlace -NodeDescription "DeclPlace" -ChangesMade ([ref]$changesMade)
        Set-XmlNodeValue -XmlDocument $xmlContent -NamespaceManager $namespaceManager -XPath "//${namespacePrefix}:CustOfficeOfFirstEntry/${namespacePrefix}:RefNum" -NewValue $gbDefaultEntryPlaceRefNum -NodeDescription "CustOfficeOfFirstEntry/RefNum" -ChangesMade ([ref]$changesMade)
        
        $tinNodes = $xmlContent.SelectNodes("//$($namespacePrefix):LodgingPerson/$($namespacePrefix):TIN | //$($namespacePrefix):Carrier/$($namespacePrefix):TIN", $namespaceManager)
        if ($null -ne $tinNodes -and $tinNodes.Count -gt 0) {
            $updatedCount = 0
            foreach ($tinNode in $tinNodes) {
                if ($tinNode.InnerText -ne $gbDefaultTin) {
                    $tinNode.InnerText = $gbDefaultTin
                    $updatedCount++
                    $changesMade = $true
                }
            }
            if ($updatedCount -gt 0) { Write-Verbose "   - Set $updatedCount <TIN> node(s) to '$gbDefaultTin'" }
        } else {
            Write-Warning "   - No <TIN> nodes found under LodgingPerson or Carrier."
        }

        # --- Subsequent Office Logic (Now handled by the external module) ---
        Set-VesselItinerary -XmlDocument $xmlContent -NamespaceManager $namespaceManager -ImoNumber $userInputImo -ChangesMade ([ref]$changesMade)
        
        # --- Item Number Sequencing Logic ---
        Write-Verbose "  Applying Item Number sequencing..."
        $itemNumberNodes = $null; $itemCount = 0
        try { $itemNumberNodes = $xmlContent.SelectNodes("//$($namespacePrefix):ItemNumber", $namespaceManager) }
        catch { Write-Warning "   - Error selecting ItemNumber nodes: $($_.Exception.Message)"; throw } # Re-throw to stop processing this file if critical
        
        if ($null -ne $itemNumberNodes) { $itemCount = $itemNumberNodes.Count; Write-Verbose "   - Found $itemCount <ItemNumber> tags." }
        else { Write-Verbose "   - No <ItemNumber> tags found." }
        
        if ($itemCount -gt 0) {
            $itemsUpdated = 0
            for ($i = 0; $i -lt $itemCount; $i++) {
                $sequenceNumber = $i + 1
                if ($itemNumberNodes[$i].InnerText -ne $sequenceNumber.ToString()) {
                    $itemNumberNodes[$i].InnerText = $sequenceNumber.ToString() # Ensure it's a string
                    $itemsUpdated++
                    $changesMade = $true
                }
            }
            if ($itemsUpdated -gt 0) { Write-Verbose "   - Updated $itemsUpdated <ItemNumber> tags sequentially." }
        }
        
        $totalNumberOfItemsNode = $null
        try { $totalNumberOfItemsNode = $xmlContent.SelectSingleNode("//$($namespacePrefix):TotalNumberOfItems", $namespaceManager) }
        catch { Write-Warning "   - Error selecting TotalNumberOfItems node: $($_.Exception.Message)" }
        
        if ($null -ne $totalNumberOfItemsNode) {
            if ($totalNumberOfItemsNode.InnerText -ne $itemCount.ToString()) {
                $totalNumberOfItemsNode.InnerText = $itemCount.ToString() # Ensure it's a string
                Write-Verbose "   - <TotalNumberOfItems> tag updated with value: $itemCount"
                $changesMade = $true
            }
        } elseif ($itemCount -gt 0) { # Only warn if there were items but no total tag
            Write-Warning "   - Could not find <TotalNumberOfItems> tag to update, but $itemCount items were found."
        }

        # --- Clean Special Characters from Tag Content ---
        Write-Verbose "  Checking and cleaning special characters '$($specialCharsRegex -replace '[\[\]]',' ')' from text content..."
        $nodesCleanedCount = 0; $cleanedSomethingInThisFile = $false
        try {
            $textNodes = $xmlContent.SelectNodes("//text()", $namespaceManager) # Select all text nodes
            if ($null -ne $textNodes) {
                foreach ($node in $textNodes) {
                    $originalText = $node.Value
                    if (-not [string]::IsNullOrWhiteSpace($originalText) -and $originalText -match $specialCharsRegex) {
                        $cleanedText = $originalText -replace $specialCharsRegex, ''
                        if ($originalText -ne $cleanedText) {
                            # $parentTagName = $node.ParentNode.Name # Get parent tag name for logging if needed
                            # Write-Verbose "     - Cleaned content in node '$parentTagName': '$originalText' -> '$cleanedText'" # Very verbose
                            $node.Value = $cleanedText
                            $nodesCleanedCount++
                            $cleanedSomethingInThisFile = $true
                        }
                    }
                }
            }
        } catch { Write-Warning "   - Error during special character cleanup: $($_.Exception.Message)" }
        
        if ($cleanedSomethingInThisFile) { Write-Verbose "   - Cleaned content from $nodesCleanedCount text node(s)."; $changesMade = $true }
        else { Write-Verbose "   - No specified special characters found in text content to clean." }

        # --- Save Changes (if any were made) BEFORE checking for empty tags ---
        if ($changesMade) {
            Write-Verbose "  Saving changes with formatting..."
            $writer = $null
            try {
                $item = Get-Item -Path $currentFilePath -ErrorAction Stop
                if ($item.IsReadOnly) { Set-ItemProperty -Path $currentFilePath -Name IsReadOnly -Value $false -ErrorAction Stop }
                
                $settings = New-Object System.Xml.XmlWriterSettings
                $settings.Indent = $true
                $settings.IndentChars = "  " # Two spaces for indent
                $settings.NewLineOnAttributes = $false
                $settings.Encoding = [System.Text.Encoding]::UTF8
                
                $writer = [System.Xml.XmlWriter]::Create($currentFilePath, $settings)
                $xmlContent.Save($writer)
                Write-Host "  Successfully saved and formatted: $($detail.FileName)" -ForegroundColor Green
            } catch {
                Write-Error "   - Failed to save or format XML file '$($detail.FileName)': $($_.Exception.Message)"
                # Optionally, decide if this error should stop processing this file or attempt empty tag check anyway
            } finally {
                if ($null -ne $writer) { $writer.Close() }
            }
        } else {
            Write-Host "  No modifications detected for this file. Not re-saved." -ForegroundColor DarkGray
        }

        # --- NOW, Check the content (potentially re-read if save failed but want to check original copy) for Empty Tags ---
        # For simplicity, we'll check the $xmlContent in memory. If saving failed, this might be the pre-save state.
        Write-Verbose "  Checking for empty tags..."
        try {
            $allElements = $xmlContent.SelectNodes("//*", $namespaceManager)
            if ($null -ne $allElements) {
                foreach ($element in $allElements) {
                    $hasElementChildNodes = $false
                    if ($element.HasChildNodes) {
                        foreach($child in $element.ChildNodes) {
                            if($child.NodeType -eq [System.Xml.XmlNodeType]::Element){
                                $hasElementChildNodes = $true; break
                            }
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($element.InnerText) -and !$hasElementChildNodes) {
                        Write-Host "    - Found empty tag: <$($element.Name)>" -ForegroundColor Yellow
                        $foundEmptyTag = $true
                        break 
                    }
                }
            } else { Write-Verbose "    - Could not select any elements for empty tag check." }
        } catch { Write-Warning "   - Error during empty tag check: $($_.Exception.Message)" }

        # --- Move to Problematic if Empty Tag Found ---
        if ($foundEmptyTag) {
            if (Test-Path $problematicDirPath -PathType Container) { # Check again in case it failed to create earlier but user fixed it
                $problematicDestPath = Join-Path -Path $problematicDirPath -ChildPath $detail.FileName
                Write-Host "  - MOVING '$($detail.FileName)' to '$problematicSubDir' due to empty tags." -ForegroundColor Magenta
                try {
                    Move-Item -Path $currentFilePath -Destination $problematicDestPath -Force -ErrorAction Stop
                    $filesMovedToProblematic++
                    $currentFilePath = $problematicDestPath # Update path if needed for any future logic within this iteration
                } catch {
                    Write-Error "   - FAILED to move '$($detail.FileName)' to '$problematicSubDir': $($_.Exception.Message)"
                }
            } else {
                Write-Warning "   - Problematic directory '$problematicDirPath' not found or inaccessible. Cannot move file '$($detail.FileName)'."
            }
        } else {
            Write-Verbose "  - No empty tags found."
        }

    } catch { # Catch errors during the entire processing of a single file
        Write-Error "  - Unhandled error processing file '$($detail.FileName)' at path '$currentFilePath': $($_.Exception.Message)"
        Write-Warning "  - Skipping further processing for this file due to error."
    } finally {
        if ($foundEmptyTag) {
            Write-Host "--- Finished processing (moved): $($detail.FileName) ---`n" -ForegroundColor White
        } else {
            Write-Host "--- Finished processing (kept): $($detail.FileName) ---`n" -ForegroundColor White
        }
    }
} # End foreach detail loop

# --- Final Summary ---
Write-Host "`nFinished processing all applicable files." -ForegroundColor Cyan
if ($filesMovedToProblematic -gt 0) {
    Write-Host "$filesMovedToProblematic file(s) were moved to the '$problematicSubDir' directory due to empty tags." -ForegroundColor Magenta
} else {
    Write-Host "No files were moved to the '$problematicSubDir' directory." -ForegroundColor Cyan
}
#endregion Modify Copied Files & Check for Empty Tags

Write-Host "`nScript complete." -ForegroundColor Green

