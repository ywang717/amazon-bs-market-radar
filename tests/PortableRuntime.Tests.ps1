$projectRoot = Split-Path -Parent $PSScriptRoot

Describe 'Portable project runtime settings' {
    BeforeAll {
        Import-Module (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Force
    }

    It 'resolves Python and PostgreSQL paths beneath the supplied project root' {
        $sandboxRoot = Join-Path $TestDrive 'portable-project'
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        $settings = Get-ProjectRuntimeSettings -ProjectRoot $sandboxRoot

        $settings.ProjectRoot | Should Be $sandboxRoot
        $settings.BootstrapPythonPath | Should Be (Join-Path $sandboxRoot '.local\python\python.exe')
        $settings.VenvPythonPath | Should Be (Join-Path $sandboxRoot '.venv\Scripts\python.exe')
        $settings.PostgresSettingsPath | Should Be (Join-Path $sandboxRoot '.local\postgres-settings.json')
        $settings.PostgresInstallRoot | Should Be (Join-Path $sandboxRoot '.local\postgresql')
        $settings.PostgresDataRoot | Should Be (Join-Path $sandboxRoot '.local\postgres-data')
    }

    It 'rejects a project root that does not exist' {
        $failure = $null
        try { Get-ProjectRuntimeSettings -ProjectRoot (Join-Path $TestDrive 'missing-project') }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match '^Project root not found:'
    }
}

Describe 'Portable Python environment initialization' {
    It 'uses the project bootstrap Python to create and probe only the project virtual environment' {
        $sandboxRoot = Join-Path $TestDrive 'python-project'
        $scriptsRoot = Join-Path $sandboxRoot 'scripts'
        $srcRoot = Join-Path $sandboxRoot 'src'
        $bootstrapRoot = Join-Path $sandboxRoot '.local\python'
        New-Item -ItemType Directory -Path $scriptsRoot, $srcRoot, $bootstrapRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\Initialize-PythonEnvironment.ps1') -Destination (Join-Path $scriptsRoot 'Initialize-PythonEnvironment.ps1')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Destination (Join-Path $srcRoot 'ProjectRuntime.psm1')
        $bootstrapPython = Join-Path $bootstrapRoot 'python.exe'
        New-Item -ItemType File -Path $bootstrapPython -Force | Out-Null
        $venvPython = Join-Path $sandboxRoot '.venv\Scripts\python.exe'
        $calls = New-Object System.Collections.ArrayList
        $fakePython = {
            param(
                [string]$PythonPath,
                [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
            )
            [void]$calls.Add([pscustomobject]@{ PythonPath = $PythonPath; Arguments = @($Arguments) })
            if ($Arguments[0] -eq '-m' -and $Arguments[1] -eq 'venv') {
                New-Item -ItemType Directory -Path (Join-Path $Arguments[2] 'Scripts') -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $Arguments[2] 'Scripts\python.exe') -Force | Out-Null
                return
            }
            if ($Arguments[0] -eq '-c') {
                '{"python":"3.12.0","reportlab":"4.4.9","pdfplumber":"0.11.9","pypdf":"6.10.0","pypdfium2":"5.12.1","playwright":"1.62.0"}'
            }
        }.GetNewClosure()

        $result = & (Join-Path $scriptsRoot 'Initialize-PythonEnvironment.ps1') -SkipDependencyInstall -PythonInvoker $fakePython | ConvertFrom-Json

        $result.Status | Should Be 'READY'
        $result.PythonPath | Should Be $venvPython
        (Test-Path -LiteralPath $venvPython) | Should Be $true
        $calls.Count | Should Be 2
        $calls[0].PythonPath | Should Be $bootstrapPython
        ($calls[0].Arguments -join ' ') | Should Be "-m venv $($sandboxRoot)\.venv"
        $calls[1].PythonPath | Should Be $venvPython
        @($calls | Where-Object { $_.PythonPath -notin @($bootstrapPython, $venvPython) }).Count | Should Be 0
        @($calls | Where-Object { $_.Arguments -contains 'pip' }).Count | Should Be 0
    }

    It 'rejects a Playwright runtime too old for the supported system browser contract' {
        $sandboxRoot = Join-Path $TestDrive 'outdated-playwright-project'
        $scriptsRoot = Join-Path $sandboxRoot 'scripts'
        $srcRoot = Join-Path $sandboxRoot 'src'
        $bootstrapRoot = Join-Path $sandboxRoot '.local\python'
        $venvRoot = Join-Path $sandboxRoot '.venv\Scripts'
        New-Item -ItemType Directory -Path $scriptsRoot, $srcRoot, $bootstrapRoot, $venvRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\Initialize-PythonEnvironment.ps1') -Destination (Join-Path $scriptsRoot 'Initialize-PythonEnvironment.ps1')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Destination (Join-Path $srcRoot 'ProjectRuntime.psm1')
        New-Item -ItemType File -Path (Join-Path $bootstrapRoot 'python.exe'), (Join-Path $venvRoot 'python.exe') -Force | Out-Null
        $fakePython = {
            param(
                [string]$PythonPath,
                [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
            )
            if ($Arguments[0] -eq '-c') {
                '{"python":"3.12.10","reportlab":"4.4.9","pdfplumber":"0.11.9","pypdf":"6.10.0","pypdfium2":"5.12.1","playwright":"1.49.1"}'
            }
        }

        $failure = $null
        try { & (Join-Path $scriptsRoot 'Initialize-PythonEnvironment.ps1') -SkipDependencyInstall -PythonInvoker $fakePython | Out-Null }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Be 'Playwright 1.62.0 or newer is required for the supported system browser runtime.'
    }
}

Describe 'Project Python environment validation' {
    It 'returns a JSON-ready runtime summary when all pinned modules are installed' {
        $result = & (Join-Path $projectRoot 'scripts\Initialize-PythonEnvironment.ps1') -SkipDependencyInstall | ConvertFrom-Json

        $result.Status | Should Be 'READY'
        $result.PyPdfium2Version | Should Match '\S+'
        $result.PlaywrightVersion | Should Match '\S+'
    }
}

Describe 'PDF report verification contract' {
    It 'returns a verified PDF with every rendered page when retained' {
        $markdownPath = Join-Path $TestDrive 'verified-report.md'
        $pdfPath = Join-Path $TestDrive 'verified-report.pdf'
        [IO.File]::WriteAllText($markdownPath, "# 验证测试`n`n中文内容", (New-Object Text.UTF8Encoding($false)))
        $renderDirectory = $null
        try {
            $result = & (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -MarkdownPath $markdownPath -PdfPath $pdfPath -Title '验证测试' -GeneratedAtBeijing '2026-08-11 10:00' -KeepRenderedPages | ConvertFrom-Json
            $renderDirectory = Split-Path -Parent $result.RenderedPages

            $result.Status | Should Be 'VERIFIED'
            $result.PdfPath | Should Be (Resolve-Path -LiteralPath $pdfPath).Path
            $result.PageCount | Should Be 1
            @($result.RenderedPages).Count | Should Be 1
            Test-Path -LiteralPath $result.RenderedPages | Should Be $true
        }
        finally {
            if ($renderDirectory -and (Test-Path -LiteralPath $renderDirectory)) {
                Remove-Item -LiteralPath $renderDirectory -Recurse -Force
            }
        }
    }

    It 'rasterizes and retains every page of a real multi-page Chinese report' {
        $markdownPath = Join-Path $TestDrive 'multi-page-report.md'
        $pdfPath = Join-Path $TestDrive 'multi-page-report.pdf'
        $lines = @('# multi-page check') + @(1..180 | ForEach-Object { "Report line $_ validates rasterized PDF pages." })
        [IO.File]::WriteAllText($markdownPath, ($lines -join "`n`n"), (New-Object Text.UTF8Encoding($false)))
        $renderDirectory = $null
        try {
            $result = & (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -MarkdownPath $markdownPath -PdfPath $pdfPath -Title '多页验证测试' -GeneratedAtBeijing '2026-08-11 10:00' -KeepRenderedPages | ConvertFrom-Json
            $renderDirectory = Split-Path -Parent $result.RenderedPages[0]

            $result.Status | Should Be 'VERIFIED'
            $result.PageCount | Should BeGreaterThan 1
            @($result.RenderedPages).Count | Should Be $result.PageCount
            foreach ($renderedPage in @($result.RenderedPages)) {
                Test-Path -LiteralPath $renderedPage | Should Be $true
            }
        }
        finally {
            if ($renderDirectory -and (Test-Path -LiteralPath $renderDirectory)) {
                Remove-Item -LiteralPath $renderDirectory -Recurse -Force
            }
        }
    }
}

Describe 'Portable PDF runtime behavior' {
    It 'requires the project virtual environment instead of falling back to a machine runtime' {
        $sandboxRoot = Join-Path $TestDrive 'pdf-project'
        $scriptsRoot = Join-Path $sandboxRoot 'scripts'
        $pythonRoot = Join-Path $scriptsRoot 'python'
        $srcRoot = Join-Path $sandboxRoot 'src'
        New-Item -ItemType Directory -Path $pythonRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $srcRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\New-ReportPdf.ps1') -Destination (Join-Path $scriptsRoot 'New-ReportPdf.ps1')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\python\render_markdown_pdf.py') -Destination (Join-Path $pythonRoot 'render_markdown_pdf.py')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'src\ProjectRuntime.psm1') -Destination (Join-Path $srcRoot 'ProjectRuntime.psm1')
        $markdownPath = Join-Path $sandboxRoot 'report.md'
        $pdfPath = Join-Path $sandboxRoot 'report.pdf'
        [IO.File]::WriteAllText($markdownPath, "# 测试`n`n中文内容", (New-Object Text.UTF8Encoding($false)))

        $failure = $null
        try { & (Join-Path $scriptsRoot 'New-ReportPdf.ps1') -MarkdownPath $markdownPath -PdfPath $pdfPath -Title '测试报告' -GeneratedAtBeijing '2026-08-11 10:00' }
        catch { $failure = $_ }

        $failure | Should Not Be $null
        $failure.Exception.Message | Should Match '^Project Python virtual environment not found:'
    }
}
