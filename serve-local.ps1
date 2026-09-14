$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:8137/")
$listener.Start()
Write-Host "Serving C:\git\Aquity at http://127.0.0.1:8137/aquity.html (Ctrl+C to stop)"
$root = "C:\git\Aquity"
while ($true) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  $path = $req.Url.LocalPath.TrimStart('/')
  if ([string]::IsNullOrEmpty($path)) { $path = "aquity.html" }
  $file = Join-Path $root $path
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
  $res.OutputStream.Close()
}
