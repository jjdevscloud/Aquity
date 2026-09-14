$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "C:\git\Aquity" }
$port = 8139
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")

try {
  $listener.Start()
} catch {
  Write-Error "Could not start listener on 127.0.0.1:$port - $($_.Exception.Message)"
  Write-Error "Most likely something is already using that port. Check with:"
  Write-Error "  Get-NetTCPConnection -LocalPort $port | Select-Object OwningProcess"
  Write-Error "then stop that process (Stop-Process -Id <pid> -Force) and try again."
  exit 1
}

Write-Host "Serving $repoRoot at http://127.0.0.1:$port/aquity.html (Ctrl+C to stop)"

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
      $path = $req.Url.LocalPath.TrimStart('/')
      if ([string]::IsNullOrEmpty($path)) { $path = "aquity.html" }
      $file = Join-Path $repoRoot $path
      if (Test-Path $file -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        if ($file -like "*.html") { $res.ContentType = "text/html" }
        elseif ($file -like "*.js") { $res.ContentType = "application/javascript" }
        elseif ($file -like "*.json") { $res.ContentType = "application/json" }
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        $res.StatusCode = 404
      }
    } finally {
      $res.OutputStream.Close()
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
