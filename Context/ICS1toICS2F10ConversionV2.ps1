#If param is not set, use default
#Set-StrictMode -Version Latest
#
param(
    [String]$xmlPath,
    [String]$xmlF10Path
)

#=======================================================================
# Helper function to clean strings.
# - Returns an object containing the cleaned string and any characters
#   that were removed.
#=======================================================================
function Clean-String {
    param(
        [string]$InputString
    )
    # Return empty or null strings as they are
    if ([string]::IsNullOrEmpty($InputString)) {
        return [PSCustomObject]@{
            CleanedString     = $InputString
            RemovedCharacters = ''
        }
    }

    # REVISED: Simplified the replacements to only handle the garbled
    # multi-character encoding errors. Correct single characters like 'Ü'
    # are handled by the Normalize() method below, which is more robust.
    $replacements = @{
        'Ãœ' = 'U'; 'Ã¼' = 'u';
        'Ä°' = 'I'; 'Ä±' = 'i';
        'Åž' = 'S'; 'ÅŸ' = 's';
        'Ã‡' = 'C'; 'Ã§' = 'c';
        'Ã–' = 'O'; 'Ã¶' = 'o';
        'Äž' = 'G'; 'ÄŸ' = 'g';
    }

    $tempString = $InputString
    foreach ($key in $replacements.Keys) {
        $tempString = $tempString.Replace($key, $replacements[$key])
    }

    # Normalize to separate base characters from any remaining accents
    $normalizedString = $tempString.Normalize('FormD')

    # Use regex to remove the accent marks
    $regex = [regex]::new('\p{M}')
    $stringWithoutAccents = $regex.Replace($normalizedString, '')

    # Define the pattern for characters to be removed
    $patternToRemove = '[^a-zA-Z0-9 /.,''&()-]'

    # Find all unique characters that match the removal pattern
    $removedChars = [regex]::Matches($stringWithoutAccents, $patternToRemove).Value | Get-Unique

    # Perform the replacement
    $cleanedString = $stringWithoutAccents -replace $patternToRemove, ''
    
    # Return a custom object with the results
    return [PSCustomObject]@{
        CleanedString     = $cleanedString
        RemovedCharacters = $removedChars -join ''
    }
}

#=======================================================================
# Helper function to get a value from an XML node, clean it, and
# provide feedback to the console (for creating new files).
#=======================================================================
function Get-And-Clean-XmlNode {
    param(
        [System.Xml.XmlElement]$Node,
        [string]$FieldName,
        [string]$NodeDescription # A friendly name for logging, e.g., "Consignee"
    )
    # Check if the node itself exists before trying to access a property
    if ($null -eq $Node) {
        Write-Host "WARNING: The entire '$NodeDescription' node is missing." -ForegroundColor Red
        return ""
    }

    $rawValue = $Node.$FieldName
    if ([string]::IsNullOrEmpty($rawValue)) {
        # Handle the specific case of the 'number' field being missing or empty
        if ($FieldName -eq 'number' -or $FieldName -eq 'Number') {
             Write-Host "INFO: Missing or empty '$NodeDescription $FieldName'. Defaulting to 'N/A'." -ForegroundColor Green
             return "N/A"
        }
        Write-Host "WARNING: '$NodeDescription $FieldName' is missing or empty in the source XML." -ForegroundColor Red
        return ""
    }

    $cleaningResult = Clean-String -InputString $rawValue
    if ($cleaningResult.RemovedCharacters) {
        Write-Host "INFO: Cleaned '$NodeDescription $FieldName'. Original: '$rawValue' | Removed: '$($cleaningResult.RemovedCharacters)'" -ForegroundColor Yellow
    }
    return $cleaningResult.CleanedString
}

#=======================================================================
# Helper function to find and clean address nodes within an
# existing F10 XML file.
#=======================================================================
function Clean-XmlAddressNode {
    param(
        [System.Xml.XmlNode]$PartyNode, # e.g., the <Consignee> or <Consignor> node
        [string]$PartyType         # e.g., "Consignee", "Consignor" for logging
    )

    if ($null -eq $PartyNode) {
        Write-Host "WARNING: Could not find the <$PartyType> node in the F10 file." -ForegroundColor Red
        return
    }

    # Clean the Name node
    $nameNode = $PartyNode.SelectSingleNode("name")
    if ($nameNode) {
        $originalValue = $nameNode.InnerText
        if (-not [string]::IsNullOrEmpty($originalValue)) {
            $cleaningResult = Clean-String -InputString $originalValue
            if ($cleaningResult.RemovedCharacters) {
                Write-Host "INFO: Cleaned '$PartyType Name'. Original: '$originalValue' | Removed: '$($cleaningResult.RemovedCharacters)'" -ForegroundColor Yellow
                $nameNode.InnerText = $cleaningResult.CleanedString
            }
        }
    }

    # Clean the Address child nodes
    $addressNode = $PartyNode.SelectSingleNode("Address")
    if ($addressNode) {
        foreach ($child in $addressNode.ChildNodes) {
            $originalValue = $child.InnerText
            if (-not [string]::IsNullOrEmpty($originalValue)) {
                $cleaningResult = Clean-String -InputString $originalValue
                if ($cleaningResult.RemovedCharacters) {
                    Write-Host "INFO: Cleaned '$PartyType $($child.LocalName)'. Original: '$originalValue' | Removed: '$($cleaningResult.RemovedCharacters)'" -ForegroundColor Yellow
                    $child.InnerText = $cleaningResult.CleanedString
                }
            }
        }
        
        # NEW: Ensure the <number> tag exists and is populated
        $numberNode = $addressNode.SelectSingleNode("number")
        if ($null -eq $numberNode) {
            # If <number> tag is missing entirely, create and append it.
            Write-Host "INFO: Added missing <number> tag with value 'N/A' for '$PartyType'." -ForegroundColor Green
            $newNumberNode = $PartyNode.OwnerDocument.CreateElement("number", $addressNode.NamespaceURI)
            $newNumberNode.InnerText = "N/A"
            $addressNode.AppendChild($newNumberNode)
        } elseif ([string]::IsNullOrEmpty($numberNode.InnerText)) {
            # If <number> tag exists but is empty, populate it.
            Write-Host "INFO: Populated empty <number> tag with 'N/A' for '$PartyType'." -ForegroundColor Green
            $numberNode.InnerText = "N/A"
        }
    }
}

#=======================================================================
# HELPER FUNCTION: Fix-XmlRouting
# - This logic was moved from Fix-XmlRoutingV2.ps1 to make this
#   script self-contained and easier to debug.
# - Corrects Itinerary and Subsequent Customs Office entries.
#=======================================================================
function Invoke-FixXmlRouting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$XmlDocument
    )

    # --- CONSTANTS AND DICTIONARIES ---
    # These are kept inside the function to make it self-contained.
    $imoNumbersWCUK = @("9242558", "9242560", "9246530", "9246554", "9354428")
    $imoNumbersWM = @("9212010", "9212034", "9429209", "1016575", "1016563")
    $imoNumbersADR = @("9390824", "9336294")

    $routingWCUK = @("CYLMS", "TRALI", "ILHFA", "ILASH", "TRISK", "EGALY", "ITSAL", "ESCAS", "PTLEI", "GBLIV", "IEDUB", "BEANR")
    $routingWM = @("CYLMS", "ILASH", "TRISK", "ILHFA", "EGALY", "TRALI", "ITSAL", "FRMRS", "ESBCN", "MACAS", "ESCAS", "ITGOA")
    $routingADR = @("FRMRS", "ESBCN", "ITGOA", "EGALY", "ILASH", "ILHFA", "CYLMS", "ITRAV", "ITVCE")

    # This dictionary MUST be complete for all EU ports listed in the routes above.
    $entryCodeDictionary = @{
        "CYLMS" = "CY000510"; "ITSAL" = "IT084100"; "ESCAS" = "ES999811"; "PTLEI" = "PT000340";
        "GBLIV" = "GB000080"; "IEDUB" = "IEDUB100"; "BEANR" = "BE101000"; "FRMRS" = "FR002730";
        "ESBCN" = "ES000811"; "ITGOA" = "IT261101"; "TRALI" = "TR330100"; "MACAS" = "ES001211";
        "ITRAV" = "IT081100"; "ITVCE" = "IT091100";
        # Non-EU ports (or ports without codes) can be omitted, but EU ports are essential.
        # Add TRISK, EGALY, ILHFA, ILASH if they have codes and are needed, but they appear to be non-EU.
    }
    # --- END CONSTANTS ---

    $corrections = [System.Collections.Generic.List[pscustomobject]]::new()
    $wasModified = $false
    $namespaceUrl = $XmlDocument.DocumentElement.NamespaceURI

    # Get the parent <EntrySummaryDeclaration> node
    $entryNode = $XmlDocument.SelectSingleNode("//*[local-name()='EntrySummaryDeclaration']")
    if (-not $entryNode) {
        Write-Warning "Could not find EntrySummaryDeclaration node in Fix-XmlRouting."
        return @{ Modified = $false; Corrections = @() }
    }

    # --- Read key values from the XML ---
    $imoNode = $entryNode.SelectSingleNode("./*[local-name()='IdeOfMeaOfTraCro']")
    $polNode = $entryNode.SelectSingleNode("./*[local-name()='PlaceOfLoading']")
    $pouNode = $entryNode.SelectSingleNode("./*[local-name()='PlaceOfUnloading']")
    $firstEntryNode = $entryNode.SelectSingleNode("./*[local-name()='CustOfficeOfFirstEntry']")

    if (-not $imoNode -or -not $polNode -or -not $pouNode -or -not $firstEntryNode) {
        Write-Warning "Missing IMO, PlaceOfLoading, PlaceOfUnloading, or CustOfficeOfFirstEntry tag. Cannot calculate route."
        return @{ Modified = $false; Corrections = @() }
    }
    
    # --- FIX: Use .Trim() to remove hidden whitespace from XML InnerText ---
    $imoValue = $imoNode.InnerText.Trim()
    $polValue = $polNode.InnerText.Trim()
    $pouValue = $pouNode.InnerText.Trim()
    $firstEntryRefNum = $firstEntryNode.SelectSingleNode("./*[local-name()='RefNum']").InnerText.Trim()
    # --- END FIX ---

    # --- Determine the correct route ---
    $selectedRouting = $null
    if ($imoNumbersWCUK -contains $imoValue) { $selectedRouting = $routingWCUK }
    elseif ($imoNumbersWM -contains $imoValue) { $selectedRouting = $routingWM }
    elseif ($imoNumbersADR -contains $imoValue) { $selectedRouting = $routingADR }
    else {
        Write-Warning "IMO '$imoValue' not found in any known routing arrays. Skipping routing correction."
        return @{ Modified = $false; Corrections = @() }
    }

    # --- Calculate the ITINERARY route slice ---
    $startIndex = [Array]::IndexOf($selectedRouting, $polValue)
    $endIndex = [Array]::IndexOf($selectedRouting, $pouValue)

    if ($startIndex -eq -1 -or $endIndex -eq -1 -or $startIndex -ge $endIndex) {
        Write-Warning "Could not calculate a valid ITINERARY route slice for POL '$polValue' to POU '$pouValue'."
        return @{ Modified = $false; Corrections = @() }
    }
    $correctItinerarySlice = $selectedRouting[$startIndex..$endIndex]

    # --- Correct the <Itinerary> section ---
    $existingItineraryNodes = $entryNode.SelectNodes("./*[local-name()='Itinerary']")
    $originalItinerary = ($existingItineraryNodes | ForEach-Object { $_.InnerText.Trim() }) -join ', '
    $correctItineraryString = ($correctItinerarySlice | ForEach-Object { $_.Substring(0, 2) }) -join ', '

    if ($originalItinerary -ne $correctItineraryString) {
        $wasModified = $true
        foreach ($node in $existingItineraryNodes) { $node.ParentNode.RemoveChild($node) | Out-Null }
        
        $referenceNode = $entryNode.SelectSingleNode("./*[local-name()='Carrier']")
        if (-not $referenceNode) { $referenceNode = $entryNode.SelectSingleNode("./*[local-name()='LodgingPerson']") }
        if (-not $referenceNode) { $referenceNode = $entryNode.SelectSingleNode("./*[local-name()='Consignee']") }

        if ($referenceNode) {
            foreach ($portCode in $correctItinerarySlice) {
                $itineraryElement = $XmlDocument.CreateElement("Itinerary", $namespaceUrl)
                $countryCodeElement = $XmlDocument.CreateElement("CountryCode", $namespaceUrl)
                $countryCodeElement.InnerText = $portCode.Substring(0, 2)
                $itineraryElement.AppendChild($countryCodeElement) | Out-Null
                $entryNode.InsertAfter($itineraryElement, $referenceNode) | Out-Null
                $referenceNode = $itineraryElement
            }
        } else {
             Write-Warning "Could not find a stable reference node; Itinerary may be appended out of order."
             foreach ($portCode in $correctItinerarySlice) {
                $itineraryElement = $XmlDocument.CreateElement("Itinerary", $namespaceUrl)
                $countryCodeElement = $XmlDocument.CreateElement("CountryCode", $namespaceUrl)
                $countryCodeElement.InnerText = $portCode.Substring(0, 2)
                $itineraryElement.AppendChild($countryCodeElement) | Out-Null
                $entryNode.AppendChild($itineraryElement) | Out-Null
            }
        }
        $corrections.Add([pscustomobject]@{
            ElementPath   = "Itinerary Section"
            OriginalValue = $originalItinerary
            CorrectedValue= $correctItineraryString
            Reason        = "Rebuilt Itinerary with 2-letter country codes based on vessel route."
        })
    }

    # --- Calculate the SUBSEQUENT route slice ---
    # Find the port code for the *first port of entry*
    # Note: $firstEntryRefNum is already trimmed from above
    $firstEntryPort = $entryCodeDictionary.Where({ $_.Value -eq $firstEntryRefNum }).Key
    if ([string]::IsNullOrEmpty($firstEntryPort)) {
        Write-Warning "The First Port of Entry '$firstEntryRefNum' is not in the routing dictionary. Cannot calculate subsequent ports."
        return @{ Modified = $wasModified; Corrections = $corrections }
    }
    
    # The subsequent slice starts *after* the first port of entry
    $subsequentStartIndex = [Array]::IndexOf($selectedRouting, $firstEntryPort)
    $subsequentEndIndex = [Array]::IndexOf($selectedRouting, $pouValue) # $pouValue is trimmed

    $correctSubsequentSlice = @()
    if ($subsequentStartIndex -ne -1 -and $subsequentEndIndex -ne -1 -and $subsequentEndIndex -gt $subsequentStartIndex) {
        $correctSubsequentSlice = $selectedRouting[($subsequentStartIndex + 1)..$subsequentEndIndex]
    }

    # --- Correct the <CustOfficeOfSubsequentEntry> section ---
    $existingSubsequentNodes = $entryNode.SelectNodes("./*[local-name()='CustOfficeOfSubsequentEntry']")
    $originalSubsequent = ($existingSubsequentNodes | ForEach-Object { $_.InnerText.Trim() }) -join ', '
    $correctSubsequentString = ($correctSubsequentSlice | ForEach-Object { if($entryCodeDictionary.ContainsKey($_)) {$entryCodeDictionary[$_]} }) -join ', '
    
    if ($originalSubsequent -ne $correctSubsequentString) {
        $wasModified = $true
        foreach ($node in $existingSubsequentNodes) { $node.ParentNode.RemoveChild($node) | Out-Null }
        
        $referenceNode = $firstEntryNode # Insert after the <CustOfficeOfFirstEntry>
        foreach ($portCode in $correctSubsequentSlice) {
            if ($entryCodeDictionary.ContainsKey($portCode)) {
                $longPortCode = $entryCodeDictionary[$portCode]
                $subsequentElement = $XmlDocument.CreateElement("CustOfficeOfSubsequentEntry", $namespaceUrl)
                $refNumElement = $XmlDocument.CreateElement("RefNum", $namespaceUrl)
                $refNumElement.InnerText = $longPortCode
                $subsequentElement.AppendChild($refNumElement) | Out-Null
                $entryNode.InsertAfter($subsequentElement, $referenceNode) | Out-Null
                $referenceNode = $subsequentElement
            }
        }
        $corrections.Add([pscustomobject]@{
            ElementPath   = "CustOfficeOfSubsequentEntry Section"
            OriginalValue = $originalSubsequent
            CorrectedValue= $correctSubsequentString
            Reason        = "Rebuilt Subsequent Entries based on vessel route."
        })
    }
    
    return @{ Modified = $wasModified; Corrections = $corrections }
}
#=======================================================================
# END OF HELPER FUNCTIONS
#=======================================================================


#Set Variables Below
$UserName = $ENV:USERNAME
if ($xmlPath -eq $null -or $xmlPath -eq "") {
    $xmlInputDir = "F:\ICS2\Queues\$UserName\XMLInput"
}
else {
    $xmlInputDir = $xmlPath
}

if ($xmlF10Path -eq $null -or $xmlF10path -eq "") {
    $xmlUpload = "F:\ICS2\Queues\$UserName\Upload"
}
else { 
     $xmlUpload = $xmlF10Path 
}
$xmlOutputDir = "F:\ICS2\XMLOutput"
$xmlFailedDir = "F:\ICS2\Queues\Failed"
$HSCodeFailedDir = "F:\ICS2\Queues\HSCode_Failed"
$LogFile = "F:\ICS2\ICS2_log.txt"
$xmlInputProcessed = "F:\ICS2\Queues\XMLInput\Processed"

#$xmlOutfile


$VesselIMOCountry =@{
    "9354428"="PT"
    "9231834"="AG"
    "9242560"="AG"
    "9246530"="AG"
    "9242558"="AG"
    "9336294"="AG"
    "9436202"="PT"
    "9212034"="MH"
    "9212010"="MH"
    "9390824"="AG"
    "9429209"="FI"
    "9215311"="MH"
    "9246554"="AG"
    "9628180"="MT"
    "1016575"="PT"
    "1016563"="PT"
    "1016587"="PT"
}

#Containertype lookup 
. F:\ICS2\ContainerType.ps1
#HSCode lookup 
. F:\ICS2\HSCodes.ps1

# --- REMOVED ---
# The dot-sourcing block for Fix-XmlRoutingV2.ps1 was here.
# Its function has been moved into this script, above.
# --- END REMOVED ---


#& "F:\ICS2\Queues\Peter2104\XMLInput\fnr.exe" --cl --dir "F:\ICS2\Queues\Peter2104\XMLInput" --fileMask "*.*"  --excludeFileMask "*.dll, *.exe" --find "   <CustOfficeOfSubsequentEntry>\n     <RefNum>GB000080</RefNum>\n   </CustOfficeOfSubsequentEntry>\n" --replace ""
& "F:\ICS2\Queues\Peter2104\XMLInput\fnr.exe" --cl --dir "F:\ICS2\Queues\Peter2104\XMLInput" --fileMask "*.*"  --excludeFileMask "*.dll, *.exe" --find "<CustOfficeOfSubsequentEntry>\n         <RefNum>GB000080</RefNum>\n         </CustOfficeOfSubsequentEntry>\n" --replace ""
    
ForEach ($File in Get-ChildItem "$xmlInputDir" *.xml)
{
    Write-Host "--- Processing File: $($File.Name) ---" -ForegroundColor Cyan
    # REFACTORED: Read the file content once, perform all replacements in memory, and then write it back once.
    # This is much more efficient than reading and writing for every single replacement.
    $fileContent = Get-Content $File -Raw
    
    $fileContent = $fileContent.Replace('&;', ' and ').Replace("'", '').Replace('&', ' and ')
    $fileContent = $fileContent.Replace('`r`n', ' ').Replace('`n', ' ').Replace('`r', ' ')
    $fileContent = $fileContent -replace '\s{2,}', ' ' # Replace multiple whitespace chars with a single space
    $fileContent = $fileContent.Replace(' <CustOfficeOfSubsequentEntry> <RefNum>GB000080</RefNum> </CustOfficeOfSubsequentEntry> ', '')
    $fileContent = $fileContent.Replace('<number>00</number>', '<number>N/A</number>')
    $fileContent = $fileContent.Replace('<NotifyParty>', '<Consignee>')
    $fileContent = $fileContent.Replace('</NotifyParty>', '</Consignee>')

    Set-Content -Path $File -Value $fileContent
    
    [xml]$xmlInput  = Get-Content -Path $File

    # Define namespace for XPath queries
    $namespace = "http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration"
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlInput.NameTable)
    $nsManager.AddNamespace("ens", $namespace)

    # --- NEW: Pre-process all seals into a lookup table for the current file ---
    $containerSealLookup = @{}
    $allSeals = $xmlInput.Envelope.EntrySummaryDeclaration.SelectNodes("ens:Seal", $nsManager) # Use ens namespace
    if ($null -ne $allSeals) {
        foreach ($sealNode in $allSeals) {
            $sealID = $sealNode.SelectSingleNode("ens:SealID", $nsManager).InnerText
            $sealContainerNumber = $sealNode.SelectSingleNode("ens:ContainerNumber", $nsManager).InnerText
            if (-not [string]::IsNullOrEmpty($sealContainerNumber) -and -not [string]::IsNullOrEmpty($sealID)) {
                # If multiple seals for one container, take the first one found.
                if (-not $containerSealLookup.ContainsKey($sealContainerNumber)) {
                    $containerSealLookup[$sealContainerNumber] = $sealID
                }
            }
        }
    }
    # UPDATED: Add error handling for DocType detection to support both file formats
    $DocType = $null
    try {
        $DocType = $xmlInput.Envelope.Body.SMFENS2.SMFAPI.docType
    } catch {
        # If the above path fails, it's likely the original format, not an F10.
        # We'll treat it as a file to be converted.
        Write-Host "INFO: Could not find F10 DocType path. Assuming original format for conversion." -ForegroundColor Green
        $DocType = "Convert" 
    }

    write-Host "Document Type: $Doctype"

    # If the file is already an F10, clean it and move it.
    if ($DocType -eq "F10") {
        Write-Host "File is already an F10 document. Cleaning address fields..." -ForegroundColor Green

        # Navigate to the correct parent node
        $houseLevel = $xmlInput.Envelope.Body.SMFENS2.SMFENS2FilingBody.ConsignmentMasterLevel.ConsignmentHouseLevel

        if ($houseLevel) {
            # Clean Consignee, Consignor
            Clean-XmlAddressNode -PartyNode $houseLevel.Consignee -PartyType "Consignee"
            Clean-XmlAddressNode -PartyNode $houseLevel.Consignor -PartyType "Consignor"

            # Clean Buyer, Seller
            $goodsShipment = $houseLevel.GoodsShipment
            if ($goodsShipment) {
                Clean-XmlAddressNode -PartyNode $goodsShipment.Buyer -PartyType "Buyer"
                Clean-XmlAddressNode -PartyNode $goodsShipment.Seller -PartyType "Seller"
            } else {
                Write-Host "WARNING: Could not find <GoodsShipment> node in F10 file." -ForegroundColor Red
            }
        } else {
            Write-Host "WARNING: Could not find <ConsignmentHouseLevel> node in F10 file." -ForegroundColor Red
        }

        # Save the cleaned XML back to the file
        $xmlInput.Save($File.FullName)

        Write-Host "F10 file cleaned. Moving to upload folder." -ForegroundColor Green
        Move-Item $File.FullName $xmlUpload -Force
    }
    # Otherwise, it's an original format file that needs conversion.
    else {
        
        # --- NEW ---
        # File is not an F10. Apply XML routing fixes before conversion.
        # This modifies the $xmlInput object in memory by calling the
        # function now embedded in this script.
        Write-Host "INFO: File is not an F10. Applying XML routing fixes before conversion..." -ForegroundColor Yellow
        try {
            $fixResult = Invoke-FixXmlRouting -XmlDocument $xmlInput
            if ($fixResult.Modified) {
                Write-Host "INFO: Fix-XmlRoutingV2 applied $($fixResult.Corrections.Count) corrections." -ForegroundColor Green
                # Optional: Log the specific corrections
                $fixResult.Corrections | ForEach-Object { 
                    Write-Host "  - Fixed '$($_.ElementPath)'. Original: '$($_.OriginalValue)' | New: '$($_.CorrectedValue)'" 
                }
            } else {
                Write-Host "INFO: Fix-XmlRoutingV2 found no routing issues to correct."
            }
        }
        catch {
             Write-Host "WARNING: Invoke-FixXmlRouting function failed." -ForegroundColor Red
             Write-Host $_.Exception.Message -ForegroundColor Red
             # Continue with conversion anyway, but log the error
          }  # --- END NEW ---

        #Get KeyInfo (Original script continues here, reading from the now-modified $xmlInput)
        $InterchangeReference  = $xmlInput.Envelope.Interchange.InterchangeReference
        $LocalReferenceNumber = $xmlInput.Envelope.EntrySummaryDeclaration.LocalReferenceNumber
        $xmlOutfile = $LocalReferenceNumber + "_F10"
        
        $NumGoodsItems = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Count
        $NumCountriesRouted = $xmlInput.Envelope.EntrySummaryDeclaration.Itinerary.Count
        $NumContainers = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Container.Count 
       # header 1 Info 
    
        $Header1 = '<?xml version="1.0" encoding="utf-8"?>
        <S:Envelope xmlns:S="http://www.w3.org/2003/05/soap-envelope" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing" xmlns:ebi="http://www.myvan.descartes.com/ebi/2004/r1">
            <S:Header>
            <wsa:From>
            <wsa:Address>urn:zz:210035945</wsa:Address>
            </wsa:From>
            <wsa:To>urn:zz:EU_ICS2</wsa:To>
            <wsa:Action>urn:myvan:ICS2_EDI</wsa:Action>
            <ebi:TestIndicator>P</ebi:TestIndicator>
            <ebi:CorrelationId>5297aeef-7711-4e2f-8d84-7d198a624cb4</ebi:CorrelationId>
        </S:Header>
        <S:Body>
            <SMFENS2 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                <SMFAPI>
                    <senderID>210035945</senderID>
                    <recipientID>EU_ICS2</recipientID>
                    <docType>F10</docType>
                </SMFAPI>
                <SMFENS2FilingBody>'
    
        $Header1 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  
        $DeclDateTime = $xmlInput.Envelope.EntrySummaryDeclaration.DeclDateTime
        $DocIssueDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        #$DocIssueDate2 = ($DocIssueDate).ToString("yyyy-MM-dd-THH:mm:ssZ") 
        $Body1 = "                               <LRN>$LocalReferenceNumber</LRN>
                                            <ConveyanceRefNum></ConveyanceRefNum>
                                            <documentIssueDate>$DocIssueDate</documentIssueDate>
                                            <specificCircumstanceIndicator>F10</specificCircumstanceIndicator>
                                            <reEntryIndicator>0</reEntryIndicator>
                                            <SplitConsignment>
                                            <splitConsignmentIndicator>0</splitConsignmentIndicator>
                                            </SplitConsignment>"
    
        $Body1 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
    
        $identificationNumber = $xmlInput.Envelope.EntrySummaryDeclaration.IdeOfMeaOfTraCro
        $nationality = $VesselIMOCountry.$identificationNumber
        $DeclDateTime = $xmlInput.Envelope.EntrySummaryDeclaration.DeclDateTime
        $DepartureDate = [datetime]::ParseExact($DeclDateTime, "yyyyMMddHHmm", $null)
        #write-host $DepartureDate
        $DepartureDate2 = ($DepartureDate.AddDays(-3)).ToString("yyyy-MM-ddTHH:mm:ssZ")
        #$DepartureDate2 = ($DepartureDate2)
        $ExpectedDateTimeOfArrival = $xmlInput.Envelope.EntrySummaryDeclaration.CustOfficeOfFirstEntry.ExpectedDateTimeOfArrival
        $ExpectedDateTimeofArrival = ($ExpectedDateTimeOfArrival).replace(' ','')
        $ArrivalDate = [datetime]::ParseExact($ExpectedDateTimeOfArrival, "yyyyMMddHHmm", $null)
        #write-host $ArrivalDate 
        $ArrivalDate2 = ($ArrivalDate).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    
        $Body2 = "             <ActiveBorderTransportMeans>
                                    <identificationNumber>IMO$identificationNumber</identificationNumber>
                                    <typeOfIdentification>10</typeOfIdentification>
                                    <typeOfMeansOfTransport>150</typeOfMeansOfTransport>
                                    <nationality>$nationality</nationality>
                                    <modeOfTransport>1</modeOfTransport>
                                    <estimatedDateAndTimeOfDeparture>$DepartureDate2</estimatedDateAndTimeOfDeparture>
                                    <estimatedDateAndTimeOfArrival>$ArrivalDate2</estimatedDateAndTimeOfArrival> "
                                            
        $Body2 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
    #Country Routing
        # NOTE: This loop now reads from the ITINERARY section that was
        # potentially corrected by Invoke-FixXmlRouting
        for ($i=0; $i -le $NumCountriesRouted -1; $i++) {
            $y = $i+1
            $Country =  $xmlInput.Envelope.EntrySummaryDeclaration.Itinerary[$i].CountryCode 
            $CountriesOfRouting = "                  <CountriesOfRoutingOfMeansOfTransport>
                                                    <sequenceNumber>$y</sequenceNumber>
                                                    <country>$Country</country>
                                            </CountriesOfRoutingOfMeansOfTransport> "  
    
            $CountriesOfRouting | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
        }
    
        $Body3 = "                       </ActiveBorderTransportMeans>"
        $Body3 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
        $Body4 = "              <ConsignmentMasterLevel>
                <Carrier>
                <name>BORCHARD LINES LTD</name>
                <identificationNumber>XI243408284000</identificationNumber>
                <Address>
                    <city>LONDON</city>
                    <country>GB</country>
                    <street>BEVIS MARKS</street>
                    <postCode>EC3A 7JB</postCode>
                    <number>24</number>
                    </Address>
                </Carrier>"
        $Body4 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
        $TotalGrossMass = $xmlInput.Envelope.EntrySummaryDeclaration.TotalGrossWeight
        $PlaceOfAcceptance = $xmlInput.Envelope.EntrySummaryDeclaration.Declplace
        
        # Get and Clean Consignee data with feedback
        $ConsigneeNode = $xmlInput.Envelope.EntrySummaryDeclaration.Consignee
        $Consignee = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "Name" -NodeDescription "Consignee"
        $ConsigneeCity = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "City" -NodeDescription "Consignee"
        $ConsigneeCountry = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "Country" -NodeDescription "Consignee"
        $ConsigneeStreet = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "Address" -NodeDescription "Consignee"
        $ConsigneePostCode = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "ZipCode" -NodeDescription "Consignee"
        $ConsigneeNumber = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "number" -NodeDescription "Consignee"
        
        $Body5 = "              <ConsignmentHouseLevel>
                    <containerIndicator>1</containerIndicator>
                    <totalGrossMass>$TotalGrossMass</totalGrossMass>
                    <PlaceOfAcceptance>
                        <unlocode>$PlaceOfAcceptance</unlocode>
                    </PlaceOfAcceptance>
                    <Consignee>
                    <name>$Consignee</name>
                        <typeOfPerson>2</typeOfPerson>
                        <Address>
                           <city>$ConsigneeCity</city>
                            <country>$ConsigneeCountry</country>
                            <street>$ConsigneeStreet</street>
                            <postCode>$ConsigneePostCode</postCode>
                            <number>$ConsigneeNumber</number>
                    </Address>
                </Consignee>"
    
        $Body5 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
    
        #GoodsItems
        Write-Host "Number of Goods Items: $NumGoodsItems"
        Write-Host "Number of Containers: $NumContainers"
    
        #Fix Container Vars
        $Status = "B"
        $Type = "2"
    #Only 1 Goods Item
        if ($NumGoodsItems -eq 1 ) {
            # Clean the GoodsDescription field
            $originalGoodsDescription = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Description # Corrected to GoodsItem
            $cleaningResult = Clean-String -InputString $originalGoodsDescription
            $GoodsDescription = $cleaningResult.CleanedString
            if ($cleaningResult.RemovedCharacters) {
                Write-Host "INFO: Cleaned 'GoodsItem Description'. Original: '$originalGoodsDescription' | Removed: '$($cleaningResult.RemovedCharacters)'" -ForegroundColor Yellow
            }
            $GoodsItemNumOfContainers = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Container.Count
            Write-Host "GoodsItem 1 NumberofContainers: $GoodsItemNumOfContainers" # Corrected logging
            $GoodsHSCode = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.TariffNumber
            #Test if harmonizedSystemSubHeadingCode used rather than Tariff Number 
            If ($xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.harmonizedSystemSubHeadingCode -ne $null) 
                 {$GoodsHSCode = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.harmonizedSystemSubHeadingCode }
            if ($GoodsHSCode -eq $null) { 
                $GoodsHSCode = $HSCodes.$GoodsDescription
            }
            #Move to Failed Queue if HS code not 6 chars
            Write-Host "HS code Length" $GoodsHSCode.length
            If ($GoodsHSCode.length -ne 6 ) 
            { 
            Write-Output "$(Get-Date) $file Failed HS Code Check" | Out-file $Logfile -append -encoding UTF8
            
            #Send HS Code corrector
            $EmailAddress = "p.mccreath@borlines.com"
           . F:\ICS2\ICSErrorMessage.ps1 -file $file -emailaddress $EmailAddress
            Move-Item $file $HSCodeFailedDir
            Continue
            }
            $GoodsunNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.UnDangerousGoodsCode # Corrected to GoodsItem
            $GoodsWeight = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.GrossWeight # Corrected to GoodsItem
            $GoodsMarks =  $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Package.Marks # Corrected to GoodsItem
            $GoodsNumPackages = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Package.NumberOfPackages # Corrected to GoodsItem
            $GoodsKindOfPackages = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Package.KindOfPackage # Corrected to GoodsItem
            $DocumentType = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.ProducedDocument.DocumentType # Corrected to GoodsItem
    
            $GoodsItem = "              <GoodsItem>
                    <goodsItemNumber>1</goodsItemNumber>
                    <Commodity>
                        <descriptionOfGoods>$GoodsDescription</descriptionOfGoods>
                    <CommodityCode>
                        <harmonizedSystemSubHeadingCode>$GoodsHSCode</harmonizedSystemSubHeadingCode>
                    </CommodityCode>
                    <DangerousGoods>
                        <unNumber>$GoodsunNumber</unNumber>
                    </DangerousGoods>
                    </Commodity>
                    <Weight>
                    <grossMass>$GoodsWeight</grossMass>
                    </Weight>
                    <Packaging>
                    <shippingMarks>$GoodsMarks</shippingMarks>
                    <numberOfPackages>$GoodsNumPackages</numberOfPackages>
                    <typeOfPackages>$GoodsKindOfPackages</typeOfPackages>
                    </Packaging> "
    
            $GoodsItem | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
    
            if ($GoodsItemNumOfContainers -eq 1 ) {
                $GoodsContainerNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Container.ContainerNumber
                $ContainerSizeAndType = $ContainerType.$GoodsContainerNumber
            
                if ([string]::IsNullOrEmpty($ContainerSizeAndType ))
                     {$ContainerSizeAndType = "18"}
            
                # --- NEW SEAL LOGIC ---
                $SealNum = "None"
                $NumOfSeals = 0
                if ($containerSealLookup.ContainsKey($GoodsContainerNumber)) {
                    $SealNum = $containerSealLookup[$GoodsContainerNumber]
                    $NumOfSeals = 1
                }
                # --- END NEW SEAL LOGIC ---
                if ($NumOfSeals -eq 0) { 
                    $SealNum = "None"
                }  
                $GoodsContainerNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Container.ContainerNumber
                $GoodsItemContainer = "            <TransportEquipment>
                    <containerSizeAndType>$ContainerSizeAndType</containerSizeAndType>
                    <containerPackedStatus>$Status</containerPackedStatus>
                    <containerSupplierType>$Type</containerSupplierType>
                    <containerIdentificationNumber>$GoodsContainerNumber</containerIdentificationNumber> 
                     <numberOfSeals>$NumOfSeals</numberOfSeals>
                     <Seal>
                        <identifier>$SealNum</identifier>
                     </Seal>  
                    </TransportEquipment>" 
    
                $GoodsItemContainer | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
                $Body5a = "                        </GoodsItem>"
                $Body5a | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append }
            Else {
                for ($x=0; $x -le $GoodsItemNumOfContainers -1 ; $x++) {
                    $GoodsContainerNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.Container[$x].ContainerNumber
                    $ContainerSizeAndType = $ContainerType.$GoodsContainerNumber
    
                    if ([string]::IsNullOrEmpty($ContainerSizeAndType)) {$ContainerSizeAndType = "18"}
                    
                    # --- NEW SEAL LOGIC ---
                    $SealNum = "None"
                    $NumOfSeals = 0
                    if ($containerSealLookup.ContainsKey($GoodsContainerNumber)) {
                        $SealNum = $containerSealLookup[$GoodsContainerNumber]
                        $NumOfSeals = 1
                    }
                    # --- END NEW SEAL LOGIC ---
                        $GoodsItemContainer = "            <TransportEquipment>
                    <containerSizeAndType>$ContainerSizeAndType</containerSizeAndType>
                    <containerPackedStatus>$Status</containerPackedStatus>
                    <containerSupplierType>$Type</containerSupplierType>
                    <containerIdentificationNumber>$GoodsContainerNumber</containerIdentificationNumber> 
                     <numberOfSeals>$NumOfSeals</numberOfSeals>
                     <Seal>
                        <identifier>$SealNum</identifier>
                     </Seal>  
                    </TransportEquipment>" 
    
               $GoodsItemContainer | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
            
               
        }
        $Body5a = "      </GoodsItem>"
        $Body5a | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
        }
    }
        else {
    Write-Host "Number of Goods Items $NumGoodsItems "      
             for ($i=0; $i -le $NumGoodsItems -1 ; $i++) {
                  $y = $i+1
                  # Clean the GoodsDescription field for each item
                  $originalGoodsDescription = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Description # Corrected to GoodsItem
                  $cleaningResult = Clean-String -InputString $originalGoodsDescription
                  $GoodsDescription = $cleaningResult.CleanedString
                  if ($cleaningResult.RemovedCharacters) {
                      Write-Host "INFO: Cleaned 'GoodsItem[$i] Description'. Original: '$originalGoodsDescription' | Removed: '$($cleaningResult.RemovedCharacters)'" -ForegroundColor Yellow
                  }
                  $GoodsItemNumOfContainers = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Container.Count
                  Write-Host "GoodsItem $i NumberofContainers" $GoodsItemNumOfContainers
                  $GoodsHSCode = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].TariffNumber
                   #Test if harmonizedSystemSubHeadingCode used rather than Tariff Number 
                  If ($xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem.harmonizedSystemSubHeadingCode -ne $null) 
                      {$GoodsHSCode = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].harmonizedSystemSubHeadingCode }
                      if ($GoodsHSCode -eq $null) { 
                           $GoodsHSCode = $HSCodes.$GoodsDescription
                      }   
                $GoodsHSCodeLength = ($GoodsHSCode).Length 
            #   #Move to Failed Queue if HS code not 6 chars
                  Write-Host $GoodsHSCodeLength
                  If ($GoodsHSCodeLength -ne 6 ) 
                  { 
                       Write-Output "$(Get-Date) $file Failed HS Code Check" | Out-file $Logfile -append -encoding UTF8
                       Move-Item $file $HSCodeFailedDir
             Continue
                  }   
                  $GoodsunNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].UnDangerousGoodsCode # Corrected to GoodsItem
                  $GoodsWeight = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].GrossWeight # Corrected to GoodsItem
                  $GoodsMarks =  $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Package.Marks # Corrected to GoodsItem
                  $GoodsNumPackages = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Package.NumberOfPackages # Corrected to GoodsItem
                  $GoodsKindOfPackages = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Package.KindOfPackage # Corrected to GoodsItem
    
                  $GoodsItem = "              <GoodsItem>
                    <goodsItemNumber>$y</goodsItemNumber>
                     <Commodity>
                        <descriptionOfGoods>$GoodsDescription</descriptionOfGoods>
                    <CommodityCode>
                        <harmonizedSystemSubHeadingCode>$GoodsHSCode</harmonizedSystemSubHeadingCode>
                    </CommodityCode>
                    <DangerousGoods>
                        <unNumber>$GoodsunNumber</unNumber>
                    </DangerousGoods>
                    </Commodity>
                    <Weight>
                    <grossMass>$GoodsWeight</grossMass>
                    </Weight>
                    <Packaging>
                    <shippingMarks>$GoodsMarks</shippingMarks>
                    <numberOfPackages>$GoodsNumPackages</numberOfPackages>
                    <typeOfPackages>$GoodsKindOfPackages</typeOfPackages>
                    </Packaging> "
    
            $GoodsItem | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append
        #} Moved to line # 
                   
       # for ($x=0; $x -le $GoodsItemNumOfContainers  ; $x++) {
        #Use next two vars until defined
            $Status = "B"
            $Type = "2"
           
           
            if ($GoodsItemNumOfContainers -eq 1) { # Corrected typo from -eq- 1
                $GoodsContainerNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Container.ContainerNumber # Corrected access
                $ContainerSizeAndType = $ContainerType.$GoodsContainerNumber
                if ([string]::IsNullOrEmpty($ContainerSizeAndType)) 
                     {$ContainerSizeAndType = "18"}
                
                # --- NEW SEAL LOGIC ---
                $SealNum = "None"
                $NumOfSeals = 0
                if ($containerSealLookup.ContainsKey($GoodsContainerNumber)) {
                    $SealNum = $containerSealLookup[$GoodsContainerNumber]
                    $NumOfSeals = 1
                }
                # --- END NEW SEAL LOGIC ---
                     $GoodsItemContainer = "           <TransportEquipment>
                    <containerSizeAndType>$ContainerSizeAndType</containerSizeAndType>
                    <containerPackedStatus>$Status</containerPackedStatus>
                    <containerSupplierType>$Type</containerSupplierType>
                    <containerIdentificationNumber>$GoodsContainerNumber</containerIdentificationNumber> 
                    <numberOfSeals>$NumOfSeals</numberOfSeals>
                    <Seal>
                        <identifier>$SealNum</identifier>
                     </Seal>  
                    </TransportEquipment>" 
    
               $GoodsItemContainer | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
               $Body5a = "                        </GoodsItem>"
             $Body5a | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
            }       
            else {
                for ($x=0; $x -le $GoodsItemNumOfContainers -1 ; $x++) {
                    $GoodsContainerNumber = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[$i].Container.ContainerNumber
                    $ContainerSizeAndType = $ContainerType.$GoodsContainerNumber
                    if ([string]::IsNullOrEmpty($ContainerSizeAndType)) 
                           {$ContainerSizeAndType = "18"}
                    
                    # --- NEW SEAL LOGIC ---
                    $SealNum = "None"
                    $NumOfSeals = 0
                    if ($containerSealLookup.ContainsKey($GoodsContainerNumber)) {
                        $SealNum = $containerSealLookup[$GoodsContainerNumber]
                        $NumOfSeals = 1
                    }
                    # --- END NEW SEAL LOGIC ---
                    $GoodsItemContainer = "           <TransportEquipment>
                    <containerSizeAndType>$ContainerSizeAndType</containerSizeAndType>
                    <containerPackedStatus>$Status</containerPackedStatus>
                    <containerSupplierType>$Type</containerSupplierType>
                    <containerIdentificationNumber>$GoodsContainerNumber</containerIdentificationNumber> 
                    <numberOfSeals>$NumOfSeals</numberOfSeals>
                    <Seal>
                        <identifier>$SealNum</identifier>
                     </Seal>  
                    </TransportEquipment>" 
    
               $GoodsItemContainer | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
               $Body5a = "                        </GoodsItem>"
             $Body5a | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
                }       
    
    
    
    
            }
    
        #   }
        }
         #  $Body5a = "                        </GoodsItem>"
         #  $Body5a | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
       }
    
        # Get and Clean Consignor data with feedback
        $ConsignorNode = $xmlInput.Envelope.EntrySummaryDeclaration.Consignor
        $Consignor = Get-And-Clean-XmlNode -Node $ConsignorNode -FieldName "Name" -NodeDescription "Consignor"
        $ConsignorCity = Get-And-Clean-XmlNode -Node $ConsignorNode -FieldName "City" -NodeDescription "Consignor"
        $ConsignorCountry = Get-And-Clean-XmlNode -Node $ConsignorNode -FieldName "Country" -NodeDescription "Consignor"
        $ConsignorStreet = Get-And-Clean-XmlNode -Node $ConsignorNode -FieldName "Address" -NodeDescription "Consignor"
        $ConsignorPostCode = Get-And-Clean-XmlNode -Node $ConsigneeNode -FieldName "ZipCode" -NodeDescription "Consignor" # Corrected this line, was using $ConsigneeNode
        $ConsignorNumber = Get-And-Clean-XmlNode -Node $ConsignorNode -FieldName "Number" -NodeDescription "Consignor"
    
        $TransportChargesMethodofPayment = $xmlInput.Envelope.EntrySummaryDeclaration.TransportChargesMethodOfPayment
        $PlaceOfDelivery = $xmlInput.Envelope.EntrySummaryDeclaration.PlaceOfUnloading
        $Body6 = "  <Consignor>
                    <name>$Consignor</name>
                    <typeOfPerson>2</typeOfPerson>
                    <Address>
                        <city>$ConsignorCity</city>
                        <country>$ConsignorCountry</country>
                        <street>$ConsignorStreet</street>
                        <postCode>$ConsignorPostCode</postCode>
                        <number>$ConsignorNumber</number>
                    </Address>
                </Consignor> 
                <TransportCharges>
                <methodOfPayment>$TransportChargesMethodofPayment</methodOfPayment>
                </TransportCharges>
                <PlaceOfDelivery>
                    <unlocode>$PlaceOfDelivery</unlocode>
                </PlaceOfDelivery>
             <GoodsShipment>
             <Buyer>
            <name>$Consignee</name>
            <typeOfPerson>2</typeOfPerson>
            <Address>
                <city>$ConsigneeCity</city>
                <country>$ConsigneeCountry</country>
                <street>$ConsigneeStreet</street>
                <postCode>$ConsigneePostCode</postCode>
                <number>$ConsigneeNumber</number>
             </Address>
             </Buyer>
    <Seller>
        <name>$Consignor</name>
        <typeOfPerson>2</typeOfPerson>
        <Address>
            <city>$ConsignorCity</city>
            <country>$ConsignorCountry</country>
            <street>$ConsignorStreet</street>
            <postCode>$ConsignorPostCode</postCode>
            <number>$ConsignorNumber</number>
    </Address>
    </Seller>
    </GoodsShipment>
    
                </ConsignmentHouseLevel>"
    
        $Body6 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
    
        $PlaceOfLoading = $xmlInput.Envelope.EntrySummaryDeclaration.PlaceOfLoading
        $DocumentNumber = $xmlInput.Envelope.EntrySummaryDeclaration.CommercialRefNum
        #$DocumentType = $xmlInput.Envelope.EntrySummaryDeclaration.GoodsItem[0].ProducedDocument.DocumentType
        $PlaceOfUnloading = $xmlInput.Envelope.EntrySummaryDeclaration.PlaceOfUnloading
    
        $Body7 = "                    <PlaceOfLoading>
                                <unlocode>$PlaceOfLoading</unlocode>
                    </PlaceOfLoading>
                    <TransportDocumentMasterLevel>
                        <documentNumber>$DocumentNumber</documentNumber>
                        <type>$DocumentType</type>
                    </TransportDocumentMasterLevel>
                    <PlaceOfUnloading>
                        <unlocode>$PlaceOfUnloading</unlocode>
                    </PlaceOfUnloading>
                    </ConsignmentMasterLevel>"
    
                     $Body7 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append   
          
        $CustOfficeOfFirstEntry = $xmlInput.Envelope.EntrySummaryDeclaration.CustOfficeOfFirstEntry.RefNum
        $NumCustOfficeOfSubsequentEntry = $xmlInput.Envelope.EntrySummaryDeclaration.CustOfficeOfSubsequentEntry.Count                 
        $Body8 ="            <Declarant>
                        <name>BORCHARD LINES LTD</name>
                        <identificationNumber>XI243408284000</identificationNumber>
                        <Address>
                            <city>LONDON</city>
                            <country>GB</country>
                            <street>BEVIS MARKS</street>
                            <postCode>EC3A 7JB</postCode>
                            <number>24</number>
                        </Address>
                        <Communication>
                            <identifier>ics2@borlines.com</identifier>
                            <type>EM</type>
                        </Communication>
                    </Declarant>
                    <CustomsOfficeOfFirstEntry>
                        <referenceNumber>$CustOfficeOfFirstEntry</referenceNumber>
                    </CustomsOfficeOfFirstEntry>"                 
        $Body8 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append  
    
        # NOTE: This loop now reads from the SUBSEQUENT ENTRY section that was
        # potentially corrected by Invoke-FixXmlRouting
        for ($i=0; $i -le $NumCustOfficeOfSubsequentEntry  -1; $i++) {
        $RefNum = $xmlInput.Envelope.EntrySummaryDeclaration.CustOfficeOfSubsequentEntry[$i].RefNum
        $Body9 = "<CustOfficeOfSubsequentEntry>
              <RefNum>$RefNum</RefNum>
              </CustOfficeOfSubsequentEntry>"
    
        $Body9 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append  
        }
    
        $Body10 = "        </SMFENS2FilingBody>
            </SMFENS2>
         </S:Body>
         </S:Envelope>"
    
        $Body10 | Out-File -FilePath $xmlOutputdir\$xmlOutFile.xml  -append 
    #   
        
    #Write-Output "$(Get-Date) $file Moved to Upload" | Out-file $Logfile -append -encoding UTF8
    Move-Item $xmlOutputdir\$xmlOutFile.xml $xmlUpload -Force
    Move-Item $File $xmlInputProcessed
    }
   
#Upload XML:.f10 file
#. F:\ICS2\FTPUpload.ps1 -xmlF10 "$xmlOutFile.xml" 

    Write-Host "--- Finished File: $($File.Name) ---`n" -ForegroundColor Cyan


}
