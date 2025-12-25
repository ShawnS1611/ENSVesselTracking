#requires -version 5.1
<#
.SYNOPSIS
    A WinForms GUI to batch-update ICS1 Entry Summary XML files.

.DESCRIPTION
    This script provides a graphical user interface to perform the batch updates
    originally handled by the console script 'Update-ICS1EntrySummaryXml.ps1'.

    The user can select a root directory and provide the values to be updated.
    The script then iterates through all .xml files in that directory and its subfolders,
    applying the specified changes and performing validation checks.

.NOTES
    Author: Gemini Code Assist
    Date: 15/10/2025
    Version: 1.0
#>

# ---------------------------------------------------------------------------------
# --- WinForms Assembly Loading ---
# ---------------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    # Added for tariff validation tab
    Add-Type -AssemblyName System.Xml.Linq
    Add-Type -AssemblyName System.Text.RegularExpressions

}
catch {
    Write-Error "Failed to load required .NET assemblies. Please ensure you are running this on a Windows system with .NET Framework."
    exit 1
}

# ---------------------------------------------------------------------------------
# --- Global Variables ---
# ---------------------------------------------------------------------------------
$script:SelectedFolderPath = $null
$script:XmlFilePaths = @() # Store full paths of XML files
$script:TargetNamespaceURI = "http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration"
$script:NamespaceManager = New-Object System.Xml.XmlNamespaceManager(New-Object System.Xml.NameTable)
$script:NamespaceManager.AddNamespace("ens", $script:TargetNamespaceURI)

# --- Tariff Validation Tab Globals ---
$script:CurrentlySelectedFailedFile = $null
$script:CurrentlySelectedGoodsItemIndexForTariff = -1


# ---------------------------------------------------------------------------------
# --- Core Logic Functions (from original script) ---
# ---------------------------------------------------------------------------------

# A helper function to UPDATE an existing XML node's value.
function Update-XmlNode {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsManager,
        [string]$XPath,
        [string]$NewValue,
        [string]$TagNameForLogging,
        [ref]$changesMade
    )

    if ([string]::IsNullOrWhiteSpace($NewValue)) {
        return
    }

    $node = $XmlDoc.SelectSingleNode($XPath, $NsManager)
    if ($null -ne $node) {
        if ($node.InnerText -ne $NewValue) {
            $node.InnerText = $NewValue
            Write-UIText "  - Updated <$TagNameForLogging> tag."
            $changesMade.Value = $true
        }
    }
    else {
        Write-UIText "  - WARNING: Tag <$TagNameForLogging> not found for update in this file."
    }
}

# A helper function to ADD an XML node if it doesn't already exist.
function Ensure-XmlNodeExists {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNamespaceManager]$NsManager,
        [string]$NamespaceUri,
        [string]$ParentXPath,
        [string]$ChildTagName,
        [string]$ChildTagValue,
        [string]$InsertAfterTagName,
        [ref]$changesMade
    )

    if ([string]::IsNullOrWhiteSpace($ChildTagValue)) {
        return
    }

    $parentNode = $XmlDoc.SelectSingleNode($ParentXPath, $NsManager)
    if ($null -eq $parentNode) {
        Write-UIText "  - WARNING: Parent node for '$ChildTagName' not found using XPath '$ParentXPath'."
        return
    }

    $existingChild = $parentNode.SelectSingleNode("ens:$ChildTagName", $NsManager)
    if ($null -ne $existingChild) {
        return # Node already exists
    }

    Write-UIText "  - Adding missing <$ChildTagName> tag with value '$ChildTagValue' to $($ParentXPath.Replace('//ens:','')) section."
    $newNode = $XmlDoc.CreateElement($ChildTagName, $NamespaceUri)
    $newNode.InnerText = $ChildTagValue
    $referenceNode = $parentNode.SelectSingleNode("ens:$InsertAfterTagName", $NsManager)

    if ($null -ne $referenceNode) {
        [void]$parentNode.InsertAfter($newNode, $referenceNode)
    }
    else {
        [void]$parentNode.AppendChild($newNode)
    }
    $changesMade.Value = $true
}

# ---------------------------------------------------------------------------------
# --- GUI Helper Functions ---
# ---------------------------------------------------------------------------------

# Writes messages to the UI's output log textbox
function Write-UIText {
    param([string]$Message)
    if ($outputTextBox -and $outputTextBox.IsHandleCreated) {
        $outputTextBox.AppendText("$(Get-Date -Format 'HH:mm:ss') - $Message`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# Helper to create Label/Textbox pairs
function Add-FormRow {
    param($ParentControl, $LabelText, $ControlName, $Y, $DefaultValue = "")
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $LabelText
    $lbl.Location = New-Object System.Drawing.Point(15, ($Y + 3)) 
    $lbl.Size = New-Object System.Drawing.Size(200, 20)
    $ParentControl.Controls.Add($lbl)
    
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Name = $ControlName
    $txt.Location = New-Object System.Drawing.Point(220, $Y)
    $txt.Size = New-Object System.Drawing.Size(280, 20)
    $txt.Text = $DefaultValue
    $ParentControl.Controls.Add($txt)
    
    return $txt
}

# ---------------------------------------------------------------------------------
# --- Form and Control Definitions ---
# ---------------------------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "ICS1 XML Batch Updater"
$form.Size = New-Object System.Drawing.Size(620, 720) # Increased height for tabs
$form.MinimumSize = New-Object System.Drawing.Size(620, 720)
$form.StartPosition = "CenterScreen"

# --- Main Tab Control ---
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabControl)

# --- Tab 1: Batch Operations ---
$tabBatch = New-Object System.Windows.Forms.TabPage
$tabBatch.Text = "Batch Operations"
$tabControl.Controls.Add($tabBatch)

# --- Directory Selection Panel (Top of Tab) ---
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Dock = [System.Windows.Forms.DockStyle]::Top
$panelTop.Height = 50
$panelTop.Padding = New-Object System.Windows.Forms.Padding(10)
$tabBatch.Controls.Add($panelTop)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Dock = [System.Windows.Forms.DockStyle]::Right
$btnBrowse.Width = 80

$lblDirectory = New-Object System.Windows.Forms.Label
$lblDirectory.Text = "Root Directory:"
$lblDirectory.Dock = [System.Windows.Forms.DockStyle]::Left
$lblDirectory.AutoSize = $true
$lblDirectory.TextAlign = "MiddleLeft"

$txtDirectory = New-Object System.Windows.Forms.TextBox
$txtDirectory.Dock = [System.Windows.Forms.DockStyle]::Fill

$panelTop.Controls.AddRange(@($txtDirectory, $lblDirectory, $btnBrowse))

# --- Main Content Panel (Below Directory Selection) ---
$panelMain = New-Object System.Windows.Forms.Panel
$panelMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelMain.Padding = New-Object System.Windows.Forms.Padding(10)
$tabBatch.Controls.Add($panelMain)

$groupValues = New-Object System.Windows.Forms.GroupBox
$groupValues.Text = "Values to Update Across All XML Files"
$groupValues.Dock = [System.Windows.Forms.DockStyle]::Top
$groupValues.Height = 180
$panelMain.Controls.Add($groupValues)

$txtImo = Add-FormRow -ParentControl $groupValues -LabelText "IMO Number (IdeOfMeaOfTraCro):" -ControlName "txtImo" -Y 30
$txtVoyage = Add-FormRow -ParentControl $groupValues -LabelText "Voyage Number (ConveyanceRefNum):" -ControlName "txtVoyage" -Y 55
$txtDeclPlace = Add-FormRow -ParentControl $groupValues -LabelText "Declaration Place (DeclPlace):" -ControlName "txtDeclPlace" -Y 80
$txtCustOffice = Add-FormRow -ParentControl $groupValues -LabelText "Customs Office Ref Num:" -ControlName "txtCustOffice" -Y 105

$lblArrival = New-Object System.Windows.Forms.Label; $lblArrival.Text = "Arrival Date (ExpectedDateTimeOfArrival):"; $lblArrival.Location = New-Object System.Drawing.Point(15, 135); $lblArrival.Size = New-Object System.Drawing.Size(200, 20); $groupValues.Controls.Add($lblArrival)
$dtpArrival = New-Object System.Windows.Forms.DateTimePicker; $dtpArrival.Name = "dtpArrival"; $dtpArrival.Location = New-Object System.Drawing.Point(220, 132); $dtpArrival.Size = New-Object System.Drawing.Size(280, 20); $dtpArrival.Format = "Custom"; $dtpArrival.CustomFormat = "yyyy-MM-dd"; $groupValues.Controls.Add($dtpArrival)

$btnProcess = New-Object System.Windows.Forms.Button
$btnProcess.Text = "Start Processing"
$btnProcess.Dock = [System.Windows.Forms.DockStyle]::Top
$btnProcess.Height = 40
$btnProcess.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 5) # Add top and bottom margin
$btnProcess.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$panelMain.Controls.Add($btnProcess)

$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = "Processing Log:"
$lblOutput.Dock = [System.Windows.Forms.DockStyle]::Top
$lblOutput.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
$lblOutput.AutoSize = $true
$panelMain.Controls.Add($lblOutput)

$outputTextBox = New-Object System.Windows.Forms.TextBox
$outputTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$outputTextBox.Multiline = $true
$outputTextBox.ScrollBars = "Vertical"
$outputTextBox.ReadOnly = $true
$outputTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$panelMain.Controls.Add($outputTextBox)

# Bring controls to front to ensure correct docking order
$outputTextBox.BringToFront()
$lblOutput.BringToFront()
$btnProcess.BringToFront()
$groupValues.BringToFront()

# --- Tab 2: Tariff Validation ---
$tabTariff = New-Object System.Windows.Forms.TabPage
$tabTariff.Text = "Tariff Validation"
$tabTariff.Padding = New-Object System.Windows.Forms.Padding(10)
$tabControl.Controls.Add($tabTariff)

$btnScanTariffs = New-Object System.Windows.Forms.Button
$btnScanTariffs.Text = "Scan/Refresh Failed List"
$btnScanTariffs.Dock = [System.Windows.Forms.DockStyle]::Top
$btnScanTariffs.Height = 30
$tabTariff.Controls.Add($btnScanTariffs)

$lblTariffStatus = New-Object System.Windows.Forms.Label
$lblTariffStatus.Text = "Select a directory on the 'Batch Operations' tab first."
$lblTariffStatus.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblTariffStatus.Height = 20
$tabTariff.Controls.Add($lblTariffStatus)

$splitter = New-Object System.Windows.Forms.SplitContainer
$splitter.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitter.BorderStyle = "Fixed3D"
$tabTariff.Controls.Add($splitter)

# Left Panel of Splitter
$lblFailedFiles = New-Object System.Windows.Forms.Label
$lblFailedFiles.Text = "Files with Tariff Issues:"
$lblFailedFiles.Dock = [System.Windows.Forms.DockStyle]::Top
$lblFailedFiles.AutoSize = $true
$splitter.Panel1.Controls.Add($lblFailedFiles)

$lbFailedFiles = New-Object System.Windows.Forms.ListBox
$lbFailedFiles.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitter.Panel1.Controls.Add($lbFailedFiles)
$lbFailedFiles.BringToFront()

# Right Panel of Splitter
$groupCorrection = New-Object System.Windows.Forms.GroupBox
$groupCorrection.Text = "Correct Tariff Number"
$groupCorrection.Dock = [System.Windows.Forms.DockStyle]::Fill
$groupCorrection.Enabled = $false
$splitter.Panel2.Controls.Add($groupCorrection)

$lblFailedFileName = New-Object System.Windows.Forms.Label; $lblFailedFileName.Text = "File: (select from list)"; $lblFailedFileName.Location = New-Object System.Drawing.Point(10, 25); $lblFailedFileName.AutoSize = $true
$lblGoodsItemDescription = New-Object System.Windows.Forms.Label; $lblGoodsItemDescription.Text = "Description: (select item)"; $lblGoodsItemDescription.Location = New-Object System.Drawing.Point(10, 50); $lblGoodsItemDescription.AutoSize = $true; $lblGoodsItemDescription.MaximumSize = New-Object System.Drawing.Size(300, 40); $lblGoodsItemDescription.AutoEllipsis = $true
$btnCopyDescription = New-Object System.Windows.Forms.Button; $btnCopyDescription.Text = "Copy Desc."; $btnCopyDescription.Location = New-Object System.Drawing.Point(10, 95); $btnCopyDescription.Size = New-Object System.Drawing.Size(100, 25); $btnCopyDescription.Enabled = $false
$lblCurrentTariffProblem = New-Object System.Windows.Forms.Label; $lblCurrentTariffProblem.Text = "Current Problem: "; $lblCurrentTariffProblem.Location = New-Object System.Drawing.Point(10, 130); $lblCurrentTariffProblem.AutoSize = $true
$txtCorrectedTariffNumber = New-Object System.Windows.Forms.TextBox; $txtCorrectedTariffNumber.Location = New-Object System.Drawing.Point(10, 160); $txtCorrectedTariffNumber.Size = New-Object System.Drawing.Size(150, 20); $txtCorrectedTariffNumber.MaxLength = 6
$lblCorrectedTariffError = New-Object System.Windows.Forms.Label; $lblCorrectedTariffError.Location = New-Object System.Drawing.Point(170, 163); $lblCorrectedTariffError.AutoSize = $true; $lblCorrectedTariffError.ForeColor = [System.Drawing.Color]::Red; $lblCorrectedTariffError.Visible = $false
$btnSaveCorrectedTariff = New-Object System.Windows.Forms.Button; $btnSaveCorrectedTariff.Text = "Save Corrected Tariff"; $btnSaveCorrectedTariff.Location = New-Object System.Drawing.Point(10, 190); $btnSaveCorrectedTariff.Size = New-Object System.Drawing.Size(180, 30)

$groupCorrection.Controls.AddRange(@($lblFailedFileName, $lblGoodsItemDescription, $btnCopyDescription, $lblCurrentTariffProblem, $txtCorrectedTariffNumber, $lblCorrectedTariffError, $btnSaveCorrectedTariff))
$splitter.BringToFront()

# ---------------------------------------------------------------------------------
# --- Event Handlers ---
# ---------------------------------------------------------------------------------

$btnBrowse.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select the root directory containing your XML files"
    if ($folderBrowser.ShowDialog() -eq "OK") {
        $txtDirectory.Text = $folderBrowser.SelectedPath
        $script:SelectedFolderPath = $folderBrowser.SelectedPath
        $outputTextBox.Clear()
        $lbFailedFiles.Items.Clear()
        $groupCorrection.Enabled = $false
        Write-UIText "Folder selected. You can now start processing or scan for tariff issues."
        $lblTariffStatus.Text = "Click 'Scan/Refresh Failed List' to check for tariff issues."
    }
})

$btnProcess.Add_Click({
    # --- Disable UI ---
    $btnProcess.Enabled = $false
    $btnScanTariffs.Enabled = $false
    $btnProcess.Text = "Processing..."
    $outputTextBox.Clear()

    # --- Get and Validate Inputs ---
    $targetDirectory = $txtDirectory.Text
    if (-not (Test-Path -Path $targetDirectory -PathType Container)) {
        Write-UIText "ERROR: The path '$targetDirectory' does not exist or is not a directory. Please browse for a valid folder."
        $btnProcess.Enabled = $true
        $btnScanTariffs.Enabled = $true
        $btnProcess.Text = "Start Processing"
        return
    }

    $newValues = @{
        IdeOfMeaOfTraCro = $txtImo.Text
        ConveyanceRefNum = $txtVoyage.Text
        DeclPlace        = $txtDeclPlace.Text
        CustOfficeRefNum = $txtCustOffice.Text
        ExpectedArrival  = $dtpArrival.Value.ToString("yyyyMMdd") + "0000"
    }

    # --- Main Processing Logic ---
    Write-UIText "Starting XML processing in directory: $targetDirectory"
    $failureLogFile = Join-Path $targetDirectory "TariffNumber failures.txt"
    if (Test-Path $failureLogFile) { Remove-Item $failureLogFile -ErrorAction SilentlyContinue }

    $xmlFiles = Get-ChildItem -Path $targetDirectory -Filter "*.xml" -Recurse -File
    if (-not $xmlFiles) {
        Write-UIText "WARNING: No .xml files were found in the specified directory."
        $script:XmlFilePaths = @()
        $btnProcess.Enabled = $true
        $btnScanTariffs.Enabled = $true
        $btnProcess.Text = "Start Processing"
        return
    }

    $validTariffCount = 0
    $tariffFailures = [System.Collections.Generic.List[string]]::new()
    Write-UIText "Found $($xmlFiles.Count) XML files to process."
    $script:XmlFilePaths = $xmlFiles.FullName

    foreach ($file in $xmlFiles) {
        try {
            Write-UIText "Processing file: $($file.Name)"
            $xmlDoc = [xml](Get-Content -Path $file.FullName -Raw)

            $namespace = "http://www.ksdsoftware.com/Schema/ICS/EntrySummaryDeclaration"
            $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $nsManager.AddNamespace("ens", $namespace)
            $fileWasModified = $false

            # --- TARIFF NUMBER VALIDATION & CORRECTION ---
            $commercialRef = "CommercialRefNum-NotFound-in-File-$($file.Name)"
            $commercialRefNode = $xmlDoc.SelectSingleNode("//ens:CommercialRefNum", $nsManager)
            if ($null -ne $commercialRefNode -and -not [string]::IsNullOrWhiteSpace($commercialRefNode.InnerText)) {
                $commercialRef = $commercialRefNode.InnerText
            }

            $fileFailedValidation = $false
            $goodsItems = $xmlDoc.SelectNodes("//ens:GoodsItem", $nsManager)
            
            if ($goodsItems.Count -gt 0) {
                foreach ($item in $goodsItems) {
                    $tariffNode = $item.SelectSingleNode("ens:TariffNumber", $nsManager)
                    if ($null -eq $tariffNode) { $tariffNode = $item.SelectSingleNode("ens:tariffNumber", $nsManager) }
                    if ($null -eq $tariffNode) { $tariffNode = $item.SelectSingleNode("ens:harmonizedSystemSubHeadingCode", $nsManager) }

                    if ($null -eq $tariffNode) {
                        $fileFailedValidation = $true
                        Write-UIText "  - Adding missing <TariffNumber> tag to a GoodsItem."
                        $newNode = $xmlDoc.CreateElement("TariffNumber", $namespace)
                        $newNode.InnerText = "000000"
                        $descriptionNode = $item.SelectSingleNode("ens:Description", $nsManager)
                        if ($null -ne $descriptionNode) { [void]$item.InsertAfter($newNode, $descriptionNode) } 
                        else { [void]$item.AppendChild($newNode) }
                        $fileWasModified = $true
                    } 
                    else {
                        if (($tariffNode.InnerText -replace '\D','').Length -ne 6) {
                             $fileFailedValidation = $true
                        }
                    }
                }
            } else { $fileFailedValidation = $true }

            if ($fileFailedValidation) {
                 if ($tariffFailures -notcontains $commercialRef) {
                    Write-UIText "  - FAILURE: Invalid or missing Tariff Number found. Commercial Ref: $commercialRef"
                    $tariffFailures.Add($commercialRef) | Out-Null
                }
            } else { $validTariffCount++ }

            # --- UPDATE EXISTING TAGS ---
            Update-XmlNode $xmlDoc $nsManager "//ens:IdeOfMeaOfTraCro" $newValues.IdeOfMeaOfTraCro "IdeOfMeaOfTraCro" ([ref]$fileWasModified)
            Update-XmlNode $xmlDoc $nsManager "//ens:ConveyanceRefNum" $newValues.ConveyanceRefNum "ConveyanceRefNum" ([ref]$fileWasModified)
            Update-XmlNode $xmlDoc $nsManager "//ens:DeclPlace" $newValues.DeclPlace "DeclPlace" ([ref]$fileWasModified)
            Update-XmlNode $xmlDoc $nsManager "//ens:CustOfficeOfFirstEntry/ens:RefNum" $newValues.CustOfficeRefNum "CustOfficeOfFirstEntry/RefNum" ([ref]$fileWasModified)
            Update-XmlNode $xmlDoc $nsManager "//ens:CustOfficeOfFirstEntry/ens:ExpectedDateTimeOfArrival" $newValues.ExpectedArrival "CustOfficeOfFirstEntry/ExpectedDateTimeOfArrival" ([ref]$fileWasModified)

            # --- ADD MISSING TAGS ---
            Ensure-XmlNodeExists $xmlDoc $nsManager $namespace "//ens:Consignor" "Number" "N/A" "City" ([ref]$fileWasModified)
            Ensure-XmlNodeExists $xmlDoc $nsManager $namespace "//ens:Consignee" "Number" "N/A" "City" ([ref]$fileWasModified)

            # --- SAVE FILE ---
            if ($fileWasModified) {
                $xmlDoc.Save($file.FullName)
                Write-UIText "  - File saved with updates."
            } else {
                Write-UIText "  - No tag updates were required for this file."
            }
        }
        catch {
            Write-UIText "  - ERROR: Failed to process file $($file.FullName). Details: $_"
        }
    }

    # --- SUMMARY ---
    Write-UIText "------------------------------------------------------------"
    Write-UIText "Script Finished. Summary:"
    Write-UIText "- $($validTariffCount) of $($xmlFiles.Count) files had a valid six-digit Tariff Number."
    Write-UIText "- $($tariffFailures.Count) files failed validation (and may have been corrected)."

    if ($tariffFailures.Count -gt 0) {
        try {
            $tariffFailures | Out-File -FilePath $failureLogFile -Encoding utf8
            Write-UIText "A list of CommercialRefNum's for failed files has been saved to:"
            Write-UIText $failureLogFile
        }
        catch {
            Write-UIText "ERROR: Could not write to the failure log file at '$failureLogFile'. Details: $_"
        }
    }
    Write-UIText "------------------------------------------------------------"
    [System.Windows.Forms.MessageBox]::Show("Processing complete. Check the log for details.", "Finished", "OK", "Information")

    # --- Re-enable UI ---
    $btnProcess.Enabled = $true
    $btnScanTariffs.Enabled = $true
    $btnProcess.Text = "Start Processing"
})

# --- Tariff Validation Tab Event Handlers ---

$btnScanTariffs.Add_Click({
    if (-not $script:SelectedFolderPath) { $lblTariffStatus.Text = "Browse for a folder on the 'Batch Operations' tab first."; return }
    
    $lbFailedFiles.Items.Clear(); $groupCorrection.Enabled = $false; $lblFailedFileName.Text = "File: (select from list)"; $txtCorrectedTariffNumber.Text = ""; $lblCurrentTariffProblem.Text = "Problem:"; $lblGoodsItemDescription.Text = "Description: (select item)"; $btnCopyDescription.Enabled = $false
    $lblTariffStatus.Text = "Scanning files for tariff issues..."; $form.Refresh()
    
    $allXmlFilesInDir = Get-ChildItem -Path $script:SelectedFolderPath -Filter "*.xml" -Recurse -File
    $script:XmlFilePaths = $allXmlFilesInDir.FullName

    $failedFilePaths = @()
    foreach ($filePath in $script:XmlFilePaths) {
        try {
            $xmlDoc = New-Object System.Xml.XmlDocument; $xmlDoc.Load($filePath)
            $goodsItems = $xmlDoc.SelectNodes("//ens:GoodsItem", $script:NamespaceManager)
            $fileHasIssue = $false
            foreach ($gi in $goodsItems) {
                $tariffNode = $gi.SelectSingleNode("ens:TariffNumber | ens:tariffnumber | ens:harmonizedSystemSubHeadingCode", $script:NamespaceManager)
                if (-not $tariffNode -or [string]::IsNullOrWhiteSpace($tariffNode.InnerText) -or ($tariffNode.InnerText -replace '\D','').Length -ne 6) {
                    $fileHasIssue = $true; break 
                }
            }
            if ($fileHasIssue) { $failedFilePaths += $filePath }
        } catch { Write-UIText "ERROR scanning $filePath for tariff: $($_.Exception.Message)" }
    }

    if ($failedFilePaths.Count -gt 0) {
        $failedFilePaths | ForEach-Object { $relPath = $_.Substring($script:SelectedFolderPath.Length).TrimStart('\'); $lbFailedFiles.Items.Add($relPath) } | Out-Null
        $lblTariffStatus.Text = "Found $($failedFilePaths.Count) files with tariff issues. Select a file to correct."
    } else {
        $lblTariffStatus.Text = "No tariff issues found in scanned files."
    }
})

$lbFailedFiles.Add_SelectedIndexChanged({
    $txtCorrectedTariffNumber.Text = ""; $lblCorrectedTariffError.Visible = $false; $lblGoodsItemDescription.Text = "Description: (loading...)"; $btnCopyDescription.Enabled = $false
    if ($lbFailedFiles.SelectedItem) {
        $script:CurrentlySelectedFailedFile = Join-Path -Path $script:SelectedFolderPath -ChildPath $lbFailedFiles.SelectedItem.ToString()
        $lblFailedFileName.Text = "File: $($lbFailedFiles.SelectedItem.ToString())"
        $groupCorrection.Enabled = $true
        $script:CurrentlySelectedGoodsItemIndexForTariff = -1 

        try {
            $xmlDoc = New-Object System.Xml.XmlDocument; $xmlDoc.Load($script:CurrentlySelectedFailedFile)
            $goodsItems = $xmlDoc.SelectNodes("//ens:GoodsItem", $script:NamespaceManager)
            for ($i = 0; $i -lt $goodsItems.Count; $i++) {
                $gi = $goodsItems[$i]
                $tariffNode = $gi.SelectSingleNode("ens:TariffNumber | ens:tariffnumber | ens:harmonizedSystemSubHeadingCode", $script:NamespaceManager)
                $currentVal = if ($tariffNode) { $tariffNode.InnerText } else { "(Missing)" }
                if (-not $tariffNode -or [string]::IsNullOrWhiteSpace($currentVal) -or ($currentVal -replace '\D','').Length -ne 6) {
                    $script:CurrentlySelectedGoodsItemIndexForTariff = $i
                    $itemNumNode = $gi.SelectSingleNode("ens:ItemNumber", $script:NamespaceManager)
                    $itemNumText = if($itemNumNode){ "Item# $($itemNumNode.InnerText)"} else {"Item# ($($i+1))"}
                    $lblCurrentTariffProblem.Text = "Problem in ${itemNumText}: Current Tariff is '$currentVal'"
                    
                    $descriptionNode = $gi.SelectSingleNode("ens:Description", $script:NamespaceManager)
                    if ($descriptionNode -and -not [string]::IsNullOrWhiteSpace($descriptionNode.InnerText)) {
                        $lblGoodsItemDescription.Text = "Description: $($descriptionNode.InnerText)"
                        $btnCopyDescription.Enabled = $true
                    } else { $lblGoodsItemDescription.Text = "Description: (Not Found)"; $btnCopyDescription.Enabled = $false }
                    $txtCorrectedTariffNumber.Focus()
                    break
                }
            }
        } catch { $lblCurrentTariffProblem.Text = "Problem: Error loading file details."; $lblGoodsItemDescription.Text = "Description: (Error)"; $btnCopyDescription.Enabled = $false; $groupCorrection.Enabled = $false }
    } else { $groupCorrection.Enabled = $false; $lblFailedFileName.Text = "File: (select from list)"; $lblCurrentTariffProblem.Text = "Problem:"; $lblGoodsItemDescription.Text = "Description: (select item)"; $btnCopyDescription.Enabled = $false }
})

$btnCopyDescription.Add_Click({
    if ($lblGoodsItemDescription.Text -and $lblGoodsItemDescription.Text.StartsWith("Description: ")) {
        $descriptionToCopy = $lblGoodsItemDescription.Text.Substring("Description: ".Length)
        [System.Windows.Forms.Clipboard]::SetText($descriptionToCopy)
        $lblTariffStatus.Text = "Description copied to clipboard!"
    }
})

$btnSaveCorrectedTariff.Add_Click({
    if (-not $script:CurrentlySelectedFailedFile -or $script:CurrentlySelectedGoodsItemIndexForTariff -lt 0) { [System.Windows.Forms.MessageBox]::Show("No file or specific GoodsItem selected.", "Error", "OK", "Error"); return }
    $correctedTariff = $txtCorrectedTariffNumber.Text.Trim()
    if ($correctedTariff -notmatch '^\d{6}$') { $lblCorrectedTariffError.Text = "Must be 6 digits."; $lblCorrectedTariffError.Visible = $true; return }
    $lblCorrectedTariffError.Visible = $false

    try {
        $xmlDoc = New-Object System.Xml.XmlDocument; $xmlDoc.Load($script:CurrentlySelectedFailedFile)
        $goodsItems = $xmlDoc.SelectNodes("//ens:GoodsItem", $script:NamespaceManager)
        $targetGoodsItem = $goodsItems[$script:CurrentlySelectedGoodsItemIndexForTariff]
        $existingTariffs = $targetGoodsItem.SelectNodes("ens:TariffNumber | ens:tariffnumber | ens:harmonizedSystemSubHeadingCode", $script:NamespaceManager); foreach($et in $existingTariffs){ $et.ParentNode.RemoveChild($et) | Out-Null }
        $newTariffNode = $xmlDoc.CreateElement("TariffNumber", $script:TargetNamespaceURI); $newTariffNode.InnerText = $correctedTariff
        $descNode = $targetGoodsItem.SelectSingleNode("ens:Description", $script:NamespaceManager); if ($descNode) { $targetGoodsItem.InsertAfter($newTariffNode, $descNode) | Out-Null } else { $targetGoodsItem.AppendChild($newTariffNode) | Out-Null }
        $xmlDoc.Save($script:CurrentlySelectedFailedFile)
        $lblTariffStatus.Text = "Tariff saved for $($lbFailedFiles.SelectedItem). Refresh list to verify."
        $txtCorrectedTariffNumber.Text = ""; $groupCorrection.Enabled = $false; $btnCopyDescription.Enabled = $false
    } catch { [System.Windows.Forms.MessageBox]::Show("Error saving corrected tariff: $($_.Exception.Message)", "Save Error", "OK", "Error") }
})

# ---------------------------------------------------------------------------------
# --- Show the Form ---
# ---------------------------------------------------------------------------------
[System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
$form.Dispose()