$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\ReportArchive.psm1') -Force

Describe 'Desktop report archive' {
    BeforeEach {
        $script:archiveRoot = Join-Path $TestDrive 'desktop-archive'
        $script:sourcePdf = Join-Path $TestDrive 'report.pdf'
        [IO.File]::WriteAllText($script:sourcePdf, 'first version', (New-Object Text.UTF8Encoding($false)))
    }

    It 'routes daily pressure washer reports to the 高压清洗机 directory' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Daily -CategoryKey pressure_washers -ArchiveRoot $script:archiveRoot

        $destination | Should Be (Join-Path (Join-Path $script:archiveRoot '高压清洗机') 'report.pdf')
        [IO.File]::ReadAllText($destination) | Should Be 'first version'
    }

    It 'routes daily sump pump reports to the 污水泵 directory' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Daily -CategoryKey sump_pumps -ArchiveRoot $script:archiveRoot

        $destination | Should Be (Join-Path (Join-Path $script:archiveRoot '污水泵') 'report.pdf')
        [IO.File]::ReadAllText($destination) | Should Be 'first version'
    }

    It 'routes daily pressure washer accessory reports to the 高压清洗机配件 directory' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Daily -CategoryKey pressure_washer_accessories -ArchiveRoot $script:archiveRoot

        $destination | Should Be (Join-Path (Join-Path $script:archiveRoot '高压清洗机配件') 'report.pdf')
        [IO.File]::ReadAllText($destination) | Should Be 'first version'
    }

    It 'routes weekly reports to the shared 周报 directory without a category key' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $script:archiveRoot

        $destination | Should Be (Join-Path (Join-Path $script:archiveRoot '周报') 'report.pdf')
        [IO.File]::ReadAllText($destination) | Should Be 'first version'
    }

    It 'overwrites an existing archived report with the current source contents' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $script:archiveRoot
        [IO.File]::WriteAllText($script:sourcePdf, 'replacement version', (New-Object Text.UTF8Encoding($false)))

        $secondDestination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $script:archiveRoot

        $secondDestination | Should Be $destination
        [IO.File]::ReadAllText($destination) | Should Be 'replacement version'
    }

    It 'throws when the archive root is an existing file instead of a directory' {
        $invalidArchiveRoot = Join-Path $TestDrive 'archive-root-file'
        [IO.File]::WriteAllText($invalidArchiveRoot, 'not a directory', (New-Object Text.UTF8Encoding($false)))

        $failure = $null
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            try { Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $invalidArchiveRoot }
            catch { $failure = $_ }
        }
        finally { $ErrorActionPreference = $previousErrorActionPreference }

        $failure | Should Not Be $null
    }

    It 'throws when an existing archive destination cannot be overwritten' {
        $destination = Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $script:archiveRoot
        $destinationLock = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $failure = $null
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            try { Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Weekly -ArchiveRoot $script:archiveRoot }
            catch { $failure = $_ }
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
            $destinationLock.Dispose()
        }

        $failure | Should Not Be $null
    }

    It 'rejects a missing source PDF' {
        $failure = $null
        try { Copy-BestSellersReportToDesktop -PdfPath (Join-Path $TestDrive 'missing.pdf') -ReportKind Weekly -ArchiveRoot $script:archiveRoot }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match 'Source PDF not found'
    }

    It 'rejects a source that is not a PDF' {
        $textFile = Join-Path $TestDrive 'report.txt'
        [IO.File]::WriteAllText($textFile, 'not a PDF', (New-Object Text.UTF8Encoding($false)))

        $failure = $null
        try { Copy-BestSellersReportToDesktop -PdfPath $textFile -ReportKind Weekly -ArchiveRoot $script:archiveRoot }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match 'Report source must be a PDF'
    }

    It 'rejects an unknown daily category key' {
        $failure = $null
        try { Copy-BestSellersReportToDesktop -PdfPath $script:sourcePdf -ReportKind Daily -CategoryKey unknown_category -ArchiveRoot $script:archiveRoot }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match 'Unknown daily category key'
    }
}

Describe 'Daily report archive integration' {
    BeforeEach {
        $script:dailyReportScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\New-BestSellersDailyReport.ps1') -Raw
    }

    It 'imports the desktop archive module for daily report processing' {
        $dailyReportScript | Should Match 'ReportArchive\.psm1'
    }

    It 'archives each verified daily PDF with its category key' {
        $dailyReportScript | Should Match 'Copy-BestSellersReportToDesktop\s+-PdfPath\s+\$pdf\.PdfPath\s+-ReportKind\s+Daily\s+-CategoryKey\s+\$categoryKey'
    }

    It 'exposes the archived PDF path in each report result' {
        $dailyReportScript | Should Match 'ArchivedPdfPath'
    }

    It 'archives after PDF verification and before email delivery' {
        $verifiedIndex = $dailyReportScript.IndexOf("`$pdf.Status -ne 'VERIFIED'")
        $archiveIndex = $dailyReportScript.IndexOf('Copy-BestSellersReportToDesktop')
        $emailIndex = $dailyReportScript.IndexOf('Send-DailyReportEmail')

        ($verifiedIndex -ge 0) | Should Be $true
        ($archiveIndex -gt $verifiedIndex) | Should Be $true
        ($emailIndex -gt $archiveIndex) | Should Be $true
    }
}

Describe 'Weekly split-report archive integration' {
    BeforeEach {
        $script:weeklyReportScript = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\New-BestSellersWeeklyReport.ps1') -Raw
        $script:activePathEndIndex = $weeklyReportScript.IndexOf("`nreturn", $weeklyReportScript.IndexOf('$splitResults = @()'))
    }

    It 'imports the desktop archive module for the active weekly split-report path' {
        $weeklyReportScript | Should Match 'ReportArchive\.psm1'
    }

    It 'archives verified split weekly PDFs as weekly reports' {
        $weeklyReportScript | Should Match 'Copy-BestSellersReportToDesktop\s+-PdfPath\s+\$pdf\.PdfPath\s+-ReportKind\s+Weekly'
    }

    It 'exposes the archived PDF path in each split weekly report result' {
        $weeklyReportScript | Should Match 'ArchivedPdfPath\s*=\s*\$archivedPdfPath'
    }

    It 'archives each split weekly PDF after verification and before the active email loop' {
        $verifiedIndex = $weeklyReportScript.IndexOf("`$pdf.Status -ne 'VERIFIED'")
        $archiveIndex = $weeklyReportScript.IndexOf('Copy-BestSellersReportToDesktop')
        $emailLoopIndex = $weeklyReportScript.IndexOf('foreach ($result in $splitResults)')

        ($verifiedIndex -ge 0) | Should Be $true
        ($archiveIndex -gt $verifiedIndex) | Should Be $true
        ($emailLoopIndex -gt $archiveIndex) | Should Be $true
    }

    It 'archives before the active split-report return' {
        $archiveIndex = $weeklyReportScript.IndexOf('Copy-BestSellersReportToDesktop')

        ($activePathEndIndex -ge 0) | Should Be $true
        ($archiveIndex -ge 0) | Should Be $true
        ($archiveIndex -lt $activePathEndIndex) | Should Be $true
    }
}

