[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $PSScriptRoot "..\Week 4th-8th May 2026 Report Emerging Trends & Technologies.docx"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\NCA Weekly Report Power Automate Master Template.docx"
}

$source = [System.IO.Path]::GetFullPath($SourcePath)
$output = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source Word report not found: $source"
}

if ($source -eq $output) {
    throw "OutputPath must be different from SourcePath."
}

if (Test-Path -LiteralPath $output) {
    if (-not $Force) {
        throw "Output already exists. Use -Force to replace it: $output"
    }

    Set-ItemProperty -LiteralPath $output -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $output -Force
}

Copy-Item -LiteralPath $source -Destination $output

$verticalTab = [string][char]11
$fields = [System.Collections.Generic.List[object]]::new()

function Add-FullParagraphField {
    param([int]$Paragraph, [string]$Name, [string]$Anchor)
    $fields.Add([pscustomobject]@{
        Paragraph = $Paragraph
        Name = $Name
        Anchor = $Anchor
        StartMarker = $null
        EndMarker = $null
    })
}

function Add-ValueField {
    param(
        [int]$Paragraph,
        [string]$Name,
        [string]$Anchor,
        [string]$StartMarker,
        [string]$EndMarker = $null
    )
    $fields.Add([pscustomobject]@{
        Paragraph = $Paragraph
        Name = $Name
        Anchor = $Anchor
        StartMarker = $StartMarker
        EndMarker = $EndMarker
    })
}

Add-ValueField 7 "ReportingWeek" "Reporting Week:" "Reporting Week: " ("${verticalTab}Prepared by: ")
Add-ValueField 7 "PreparedBy" "Prepared by:" "Prepared by: "

Add-FullParagraphField 9 "ExecutiveSnapshotParagraph1" "This week"
Add-FullParagraphField 10 "ExecutiveSnapshotParagraph2" "The strongest strategic implication"
Add-FullParagraphField 11 "ExecutiveSnapshotParagraph3" "For NCA"

$trendStarts = @(14, 25, 36, 47)
for ($trend = 1; $trend -le 4; $trend++) {
    $start = $trendStarts[$trend - 1]
    Add-ValueField $start "Trend${trend}Title" "Trend ${trend}:" "Trend ${trend}: "
    Add-ValueField ($start + 1) "Trend${trend}WhatHappened" "What Happened:" ("What Happened:${verticalTab}")
    Add-ValueField ($start + 2) "Trend${trend}WhyItMatters" "Why It Matters (NCA Context):" ("Why It Matters (NCA Context):${verticalTab}")
    Add-FullParagraphField ($start + 4) "Trend${trend}StrategicSignal1" ""
    Add-FullParagraphField ($start + 5) "Trend${trend}StrategicSignal2" ""
    Add-ValueField ($start + 7) "Trend${trend}Risk" "Risk:" "Risk: "
    Add-ValueField ($start + 8) "Trend${trend}Opportunity" "Opportunity:" "Opportunity: "
    Add-ValueField ($start + 9) "Trend${trend}TimeHorizon" "Time Horizon:" "Time Horizon: "
}

$horizonTitles = @(59, 62, 65)
for ($item = 1; $item -le 3; $item++) {
    $titleParagraph = $horizonTitles[$item - 1]
    $bodyParagraph = $titleParagraph + 1
    Add-FullParagraphField $titleParagraph "Horizon${item}Title" ""
    Add-ValueField $bodyParagraph "Horizon${item}PotentialRelevance" "Potential Relevance:" ("Potential Relevance:${verticalTab}") ("${verticalTab}Uncertainty Level: ")
    Add-ValueField $bodyParagraph "Horizon${item}UncertaintyLevel" "Uncertainty Level:" "Uncertainty Level: "
}

$implicationParagraphs = @(
    @{ Paragraph = 70; Name = "SpectrumManagementSignal1" },
    @{ Paragraph = 71; Name = "SpectrumManagementSignal2" },
    @{ Paragraph = 73; Name = "InfrastructureEvolutionSignal1" },
    @{ Paragraph = 74; Name = "InfrastructureEvolutionSignal2" },
    @{ Paragraph = 76; Name = "DigitalServicesGovernanceSignal1" },
    @{ Paragraph = 78; Name = "CybersecurityDataProtectionSignal1" },
    @{ Paragraph = 80; Name = "MarketCompetitionSignal1" }
)
foreach ($item in $implicationParagraphs) {
    Add-FullParagraphField $item.Paragraph $item.Name ""
}

$attentionParagraphs = @(
    @{ Paragraph = 84; Name = "MonitorSignal1" },
    @{ Paragraph = 85; Name = "MonitorSignal2" },
    @{ Paragraph = 87; Name = "EngageSignal1" },
    @{ Paragraph = 88; Name = "EngageSignal2" },
    @{ Paragraph = 90; Name = "PrepareSignal1" },
    @{ Paragraph = 91; Name = "PrepareSignal2" },
    @{ Paragraph = 93; Name = "PolicyReviewSignal1" },
    @{ Paragraph = 94; Name = "PolicyReviewSignal2" },
    @{ Paragraph = 95; Name = "PolicyReviewSignal3" }
)
foreach ($item in $attentionParagraphs) {
    Add-FullParagraphField $item.Paragraph $item.Name ""
}

for ($item = 1; $item -le 4; $item++) {
    Add-FullParagraphField (97 + $item) "Assumption${item}" ""
}

for ($item = 1; $item -le 10; $item++) {
    Add-FullParagraphField (104 + $item) "Reference${item}" ""
}

# Use Microsoft Word itself to insert and serialize the native controls. This
# produces the most reliable template for the Word Online (Business) connector
# while leaving the source document unchanged.
$word = $null
$document = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $word.ScreenUpdating = $false

    $document = $word.Documents.Open($output, $false, $false)
    $document.TrackRevisions = $false

    # The existing sample hyperlinks are inside fields that the flow replaces.
    # Remove the links from the copy while retaining their visible styled text.
    for ($linkIndex = $document.Hyperlinks.Count; $linkIndex -ge 1; $linkIndex--) {
        $document.Hyperlinks.Item($linkIndex).Delete()
    }

    for ($fieldIndex = $fields.Count - 1; $fieldIndex -ge 0; $fieldIndex--) {
        $field = $fields[$fieldIndex]
        if ($field.Paragraph -gt $document.Paragraphs.Count) {
            throw "Paragraph $($field.Paragraph) for '$($field.Name)' does not exist."
        }

        $paragraphRange = $document.Paragraphs.Item($field.Paragraph).Range.Duplicate
        $paragraphText = $paragraphRange.Text.TrimEnd([char]13, [char]7)
        if ($field.Anchor -and -not $paragraphText.Contains($field.Anchor)) {
            throw "Expected anchor '$($field.Anchor)' was not found in paragraph $($field.Paragraph) for '$($field.Name)'."
        }

        $startOffset = 0
        $endOffset = $paragraphText.Length
        if ($field.StartMarker) {
            $markerIndex = $paragraphText.IndexOf($field.StartMarker, [System.StringComparison]::Ordinal)
            if ($markerIndex -lt 0) {
                throw "Start marker '$($field.StartMarker)' was not found for '$($field.Name)'."
            }
            $startOffset = $markerIndex + $field.StartMarker.Length
        }
        if ($field.EndMarker) {
            $endOffset = $paragraphText.IndexOf($field.EndMarker, $startOffset, [System.StringComparison]::Ordinal)
            if ($endOffset -lt 0) {
                throw "End marker '$($field.EndMarker)' was not found for '$($field.Name)'."
            }
        }
        if ($endOffset -le $startOffset) {
            throw "The calculated range for '$($field.Name)' is empty."
        }

        $target = $document.Range(
            $paragraphRange.Start + $startOffset,
            $paragraphRange.Start + $endOffset)
        $control = $document.ContentControls.Add(1, $target)
        $control.Title = $field.Name
        $control.Tag = $field.Name
        $control.MultiLine = $true
        $control.LockContentControl = $true
        $control.LockContents = $false

        Write-Progress -Activity "Creating Power Automate Word template" -Status $field.Name -PercentComplete ([int](100 * ($fields.Count - $fieldIndex) / $fields.Count))
    }

    Write-Progress -Activity "Creating Power Automate Word template" -Completed
    $document.Save()
    $document.Close($false)
    $document = $null
}
finally {
    if ($document) {
        $document.Close($false)
    }
    if ($word) {
        $word.ScreenUpdating = $true
        $word.Quit()
    }
    if ($document) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($document)
    }
    if ($word) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

Set-ItemProperty -LiteralPath $output -Name IsReadOnly -Value $true

[pscustomobject]@{
    Source = $source
    Template = $output
    ContentControlCount = $fields.Count
    LocalReadOnly = (Get-Item -LiteralPath $output).IsReadOnly
}

return

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

function Get-LogicalNodeText {
    param([System.Xml.XmlNode]$Node)

    if ($Node.NamespaceURI -eq $wordNamespace -and $Node.LocalName -eq "t") {
        return $Node.InnerText
    }
    if ($Node.NamespaceURI -eq $wordNamespace -and $Node.LocalName -eq "br") {
        return $verticalTab
    }

    $text = [System.Text.StringBuilder]::new()
    foreach ($child in $Node.ChildNodes) {
        [void]$text.Append((Get-LogicalNodeText $child))
    }
    return $text.ToString()
}

function New-WordElement {
    param(
        [System.Xml.XmlDocument]$Document,
        [string]$LocalName
    )
    return $Document.CreateElement("w", $LocalName, $wordNamespace)
}

function Set-WordAttribute {
    param(
        [System.Xml.XmlElement]$Element,
        [string]$Name,
        [string]$Value
    )
    $attribute = $Element.OwnerDocument.CreateAttribute("w", $Name, $wordNamespace)
    $attribute.Value = $Value
    [void]$Element.Attributes.Append($attribute)
}

function Set-WordTextNodeValue {
    param(
        [System.Xml.XmlElement]$TextNode,
        [string]$Value
    )

    $TextNode.InnerText = $Value
    $xmlNamespace = "http://www.w3.org/XML/1998/namespace"
    if ($Value.StartsWith(" ") -or $Value.EndsWith(" ")) {
        [void]$TextNode.SetAttribute("space", $xmlNamespace, "preserve")
    }
    else {
        $TextNode.RemoveAttribute("space", $xmlNamespace)
    }
}

function Split-WordRunAtOffset {
    param(
        [System.Xml.XmlElement]$Paragraph,
        [System.Xml.XmlElement]$Node,
        [int]$Offset,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    if ($Node.NamespaceURI -ne $wordNamespace -or $Node.LocalName -ne "r") {
        throw "A content-control boundary falls inside a non-run element and cannot be split safely."
    }

    $logicalText = Get-LogicalNodeText $Node
    if ($Offset -le 0 -or $Offset -ge $logicalText.Length) {
        throw "The requested Word run split is outside the valid text range."
    }

    $leftRun = [System.Xml.XmlElement]$Node.CloneNode($true)
    $rightRun = [System.Xml.XmlElement]$Node.CloneNode($true)

    foreach ($child in @($leftRun.ChildNodes)) {
        if (-not ($child.NamespaceURI -eq $wordNamespace -and $child.LocalName -eq "rPr")) {
            [void]$leftRun.RemoveChild($child)
        }
    }
    foreach ($child in @($rightRun.ChildNodes)) {
        if (-not ($child.NamespaceURI -eq $wordNamespace -and $child.LocalName -eq "rPr")) {
            [void]$rightRun.RemoveChild($child)
        }
    }

    $cursor = 0
    foreach ($child in @($Node.ChildNodes)) {
        if ($child.NamespaceURI -eq $wordNamespace -and $child.LocalName -eq "rPr") {
            continue
        }

        $childText = Get-LogicalNodeText $child
        $childStart = $cursor
        $childEnd = $cursor + $childText.Length

        if ($childEnd -le $Offset) {
            [void]$leftRun.AppendChild($child.CloneNode($true))
        }
        elseif ($childStart -ge $Offset) {
            [void]$rightRun.AppendChild($child.CloneNode($true))
        }
        elseif ($child.NamespaceURI -eq $wordNamespace -and $child.LocalName -eq "t") {
            $localOffset = $Offset - $childStart
            $leftText = [System.Xml.XmlElement]$child.CloneNode($true)
            $rightText = [System.Xml.XmlElement]$child.CloneNode($true)
            Set-WordTextNodeValue $leftText $child.InnerText.Substring(0, $localOffset)
            Set-WordTextNodeValue $rightText $child.InnerText.Substring($localOffset)
            [void]$leftRun.AppendChild($leftText)
            [void]$rightRun.AppendChild($rightText)
        }
        else {
            throw "A content-control boundary falls inside a complex Word child element and cannot be split safely."
        }

        $cursor = $childEnd
    }

    if ((Get-LogicalNodeText $leftRun).Length -eq 0 -or (Get-LogicalNodeText $rightRun).Length -eq 0) {
        throw "Splitting the Word run would create an empty formatting run."
    }

    [void]$Paragraph.InsertBefore($leftRun, $Node)
    [void]$Paragraph.InsertBefore($rightRun, $Node)
    [void]$Paragraph.RemoveChild($Node)
}

$fileStream = $null
$archive = $null

try {
    $fileStream = [System.IO.File]::Open(
        $output,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Update,
        $false)

    $documentEntry = $archive.GetEntry("word/document.xml")
    if (-not $documentEntry) {
        throw "The Word package does not contain word/document.xml."
    }

    $reader = [System.IO.StreamReader]::new($documentEntry.Open())
    try {
        $documentXml = [System.Xml.XmlDocument]::new()
        $documentXml.PreserveWhitespace = $true
        $documentXml.LoadXml($reader.ReadToEnd())
    }
    finally {
        $reader.Dispose()
    }

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($documentXml.NameTable)
    $namespaceManager.AddNamespace("w", $wordNamespace)

    # Proofing markers are non-visual and can straddle a content-control
    # boundary. Remove them so Word does not need to repair the template.
    foreach ($proofingMarker in @($documentXml.SelectNodes("//w:proofErr", $namespaceManager))) {
        [void]$proofingMarker.ParentNode.RemoveChild($proofingMarker)
    }

    # Existing source hyperlinks occur inside text that Power Automate will
    # replace. Retain their styled runs and visible text, but unwrap the link
    # container so each plain-text control has schema-safe run-only content.
    foreach ($hyperlink in @($documentXml.SelectNodes("//w:hyperlink", $namespaceManager))) {
        $parent = $hyperlink.ParentNode
        foreach ($child in @($hyperlink.ChildNodes)) {
            [void]$parent.InsertBefore($child, $hyperlink)
        }
        [void]$parent.RemoveChild($hyperlink)
    }

    $paragraphs = $documentXml.SelectNodes("//w:body/w:p", $namespaceManager)

    # Work backwards so later controls cannot disturb the node boundaries used
    # for earlier fields in the same paragraph.
    for ($fieldIndex = $fields.Count - 1; $fieldIndex -ge 0; $fieldIndex--) {
        $field = $fields[$fieldIndex]
        if ($field.Paragraph -gt $paragraphs.Count) {
            throw "Paragraph $($field.Paragraph) for '$($field.Name)' does not exist."
        }

        $paragraph = [System.Xml.XmlElement]$paragraphs[$field.Paragraph - 1]
        $boundariesAligned = $false
        while (-not $boundariesAligned) {
            $contentNodes = @($paragraph.ChildNodes | Where-Object {
                -not ($_.NamespaceURI -eq $wordNamespace -and $_.LocalName -eq "pPr")
            })

            $nodeTexts = @()
            $paragraphTextBuilder = [System.Text.StringBuilder]::new()
            foreach ($node in $contentNodes) {
                $nodeText = Get-LogicalNodeText $node
                $nodeTexts += $nodeText
                [void]$paragraphTextBuilder.Append($nodeText)
            }
            $paragraphText = $paragraphTextBuilder.ToString()

            if ($field.Anchor -and -not $paragraphText.Contains($field.Anchor)) {
                throw "Expected anchor '$($field.Anchor)' was not found in paragraph $($field.Paragraph) for '$($field.Name)'."
            }

            $startOffset = 0
            $endOffset = $paragraphText.Length
            if ($field.StartMarker) {
                $markerIndex = $paragraphText.IndexOf($field.StartMarker, [System.StringComparison]::Ordinal)
                if ($markerIndex -lt 0) {
                    throw "Start marker '$($field.StartMarker)' was not found for '$($field.Name)'."
                }
                $startOffset = $markerIndex + $field.StartMarker.Length
            }
            if ($field.EndMarker) {
                $endOffset = $paragraphText.IndexOf($field.EndMarker, $startOffset, [System.StringComparison]::Ordinal)
                if ($endOffset -lt 0) {
                    throw "End marker '$($field.EndMarker)' was not found for '$($field.Name)'."
                }
            }
            if ($endOffset -le $startOffset) {
                throw "The calculated range for '$($field.Name)' is empty."
            }

            $cursor = 0
            $firstNodeIndex = -1
            $lastNodeIndex = -1
            $splitPerformed = $false
            for ($nodeIndex = 0; $nodeIndex -lt $contentNodes.Count; $nodeIndex++) {
                $nodeStart = $cursor
                $nodeEnd = $cursor + $nodeTexts[$nodeIndex].Length

                if ($startOffset -gt $nodeStart -and $startOffset -lt $nodeEnd) {
                    try {
                        Split-WordRunAtOffset $paragraph $contentNodes[$nodeIndex] ($startOffset - $nodeStart) $namespaceManager
                    }
                    catch {
                        throw "Unable to split the start boundary for '$($field.Name)' in paragraph $($field.Paragraph): $($_.Exception.Message)"
                    }
                    $splitPerformed = $true
                    break
                }
                if ($endOffset -gt $nodeStart -and $endOffset -lt $nodeEnd) {
                    try {
                        Split-WordRunAtOffset $paragraph $contentNodes[$nodeIndex] ($endOffset - $nodeStart) $namespaceManager
                    }
                    catch {
                        throw "Unable to split the end boundary for '$($field.Name)' in paragraph $($field.Paragraph): $($_.Exception.Message)"
                    }
                    $splitPerformed = $true
                    break
                }

                if ($firstNodeIndex -lt 0 -and $startOffset -eq $nodeStart) {
                    $firstNodeIndex = $nodeIndex
                }
                if ($endOffset -eq $nodeEnd) {
                    $lastNodeIndex = $nodeIndex
                }
                $cursor = $nodeEnd
            }

            if (-not $splitPerformed) {
                if ($firstNodeIndex -lt 0 -or $lastNodeIndex -lt $firstNodeIndex) {
                    throw "'$($field.Name)' does not align with a safely splittable Word run. The template was not changed."
                }
                $boundariesAligned = $true
            }
        }

        $sdt = New-WordElement $documentXml "sdt"
        $sdtProperties = New-WordElement $documentXml "sdtPr"

        $alias = New-WordElement $documentXml "alias"
        Set-WordAttribute $alias "val" $field.Name
        [void]$sdtProperties.AppendChild($alias)

        $tag = New-WordElement $documentXml "tag"
        Set-WordAttribute $tag "val" $field.Name
        [void]$sdtProperties.AppendChild($tag)

        $id = New-WordElement $documentXml "id"
        Set-WordAttribute $id "val" ([string](Get-Random -Minimum 1000000 -Maximum 2147483646))
        [void]$sdtProperties.AppendChild($id)

        # Lock the control container against deletion while leaving its text
        # replaceable by Power Automate.
        $lock = New-WordElement $documentXml "lock"
        Set-WordAttribute $lock "val" "sdtLocked"
        [void]$sdtProperties.AppendChild($lock)

        $textControl = New-WordElement $documentXml "text"
        Set-WordAttribute $textControl "multiLine" "1"
        [void]$sdtProperties.AppendChild($textControl)

        $sdtContent = New-WordElement $documentXml "sdtContent"
        [void]$sdt.AppendChild($sdtProperties)
        [void]$sdt.AppendChild($sdtContent)

        $firstNode = $contentNodes[$firstNodeIndex]
        [void]$paragraph.InsertBefore($sdt, $firstNode)
        for ($nodeIndex = $firstNodeIndex; $nodeIndex -le $lastNodeIndex; $nodeIndex++) {
            [void]$sdtContent.AppendChild($contentNodes[$nodeIndex])
        }
    }

    $documentEntry.Delete()
    $newDocumentEntry = $archive.CreateEntry(
        "word/document.xml",
        [System.IO.Compression.CompressionLevel]::Optimal)
    $writerSettings = [System.Xml.XmlWriterSettings]::new()
    $writerSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $writerSettings.Indent = $false
    $writer = [System.Xml.XmlWriter]::Create($newDocumentEntry.Open(), $writerSettings)
    try {
        $documentXml.Save($writer)
    }
    finally {
        $writer.Dispose()
    }

    $settingsEntry = $archive.GetEntry("word/settings.xml")
    if ($settingsEntry) {
        $settingsReader = [System.IO.StreamReader]::new($settingsEntry.Open())
        try {
            $settingsXml = [System.Xml.XmlDocument]::new()
            $settingsXml.PreserveWhitespace = $true
            $settingsXml.LoadXml($settingsReader.ReadToEnd())
        }
        finally {
            $settingsReader.Dispose()
        }

        $settingsNs = [System.Xml.XmlNamespaceManager]::new($settingsXml.NameTable)
        $settingsNs.AddNamespace("w", $wordNamespace)
        if (-not $settingsXml.SelectSingleNode("/w:settings/w:writeProtection", $settingsNs)) {
            $writeProtection = New-WordElement $settingsXml "writeProtection"
            Set-WordAttribute $writeProtection "recommended" "1"
            [void]$settingsXml.DocumentElement.PrependChild($writeProtection)
        }

        $settingsEntry.Delete()
        $newSettingsEntry = $archive.CreateEntry(
            "word/settings.xml",
            [System.IO.Compression.CompressionLevel]::Optimal)
        $settingsWriter = [System.Xml.XmlWriter]::Create($newSettingsEntry.Open(), $writerSettings)
        try {
            $settingsXml.Save($settingsWriter)
        }
        finally {
            $settingsWriter.Dispose()
        }
    }
}
finally {
    if ($archive) {
        $archive.Dispose()
    }
    if ($fileStream) {
        $fileStream.Dispose()
    }
}

# Mark the local master as read-only. SharePoint library permissions should be
# used as the durable protection after the template is uploaded.
Set-ItemProperty -LiteralPath $output -Name IsReadOnly -Value $true

[pscustomobject]@{
    Source = $source
    Template = $output
    ContentControlCount = $fields.Count
    LocalReadOnly = (Get-Item -LiteralPath $output).IsReadOnly
}
