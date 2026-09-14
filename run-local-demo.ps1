<#
.SYNOPSIS
  One-shot local integration test: anvil + every Phase 1-3 contract + one
  launched demo agent + one seeded job payment and fee claim, wired into
  indexer/agents.config.json so the indexer (and then aquity.html) can show
  real on-chain data end to end.

.DESCRIPTION
  Runs contracts/script/DeployLocalDemo.s.sol against a local anvil chain.
  That script deploys mock USDG/stock tokens, a mock swap router, a mock
  launchpad factory, and a mock fee escrow, then launches one agent through
  Launcher exactly like a real builder would (real EIP-712 signatures,
  checked on-chain), wires its Vault/Splitter/FeeRouter/Distributor, and
  fires one WorkReceipt + one FeesClaimedAndSplit so there's something to
  see immediately.

  Known issue on some locked-down Windows setups: anvil.exe can be blocked
  by an Application Control / WDAC policy even though forge.exe runs fine.
  If anvil won't start, this script cannot proceed -- the contract logic
  itself was already verified with `forge script` (no anvil needed, see
  contracts/script/DeployLocalDemo.s.sol's own doc comment), just not a
  live, queryable chain the indexer can point at.

.EXAMPLE
  .\run-local-demo.ps1
#>

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$contracts = Join-Path $repoRoot "contracts"
$indexer = Join-Path $repoRoot "indexer"
$anvilExe = Join-Path $env:USERPROFILE ".foundry\bin\anvil.exe"

Write-Host "Starting anvil..."
$anvilOut = Join-Path $env:TEMP "aquity-anvil-out.log"
$anvilErr = Join-Path $env:TEMP "aquity-anvil-err.log"
Remove-Item -ErrorAction SilentlyContinue $anvilOut, $anvilErr

try {
    $anvil = Start-Process -FilePath $anvilExe -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $anvilOut -RedirectStandardError $anvilErr
} catch {
    Write-Error "Could not launch anvil.exe: $_"
    exit 1
}
Start-Sleep -Seconds 2

if ($anvil.HasExited) {
    Write-Error "anvil exited immediately (exit code $($anvil.ExitCode)). Check $anvilErr for details."
    Write-Error "On some locked-down machines this is a Windows Application Control policy blocking anvil.exe specifically (forge.exe can still work fine) -- try running 'anvil' directly in your own terminal to see the real error, and ask whoever manages the machine's policy to allow it if so."
    exit 1
}

try {
    Push-Location $contracts
    Remove-Item -ErrorAction SilentlyContinue local-demo-output.json, local-demo-env.json

    Write-Host "Deploying and launching the demo agent..."
    & forge script script/DeployLocalDemo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
    if ($LASTEXITCODE -ne 0) { throw "forge script exited with code $LASTEXITCODE" }

    $agent = Get-Content local-demo-output.json -Raw | ConvertFrom-Json
    $envInfo = Get-Content local-demo-env.json -Raw | ConvertFrom-Json
    Pop-Location

    $agentsConfigPath = Join-Path $indexer "agents.config.json"
    $json = @($agent) | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($agentsConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ""
    Write-Host "Wrote $agentsConfigPath"

    Write-Host ""
    Write-Host "Paste these into indexer/.env (copy indexer/.env.example first if you haven't):"
    Write-Host "  ROBINHOOD_RPC_URL=$($envInfo.rpcUrl)"
    Write-Host "  ROBINHOOD_CHAIN_ID=$($envInfo.chainId)"
    Write-Host "  AGENT_REGISTRY_ADDRESS=$($envInfo.registryAddress)"
    Write-Host "  LAUNCHER_ADDRESS=$($envInfo.launcherAddress)"
    Write-Host "  AGENT_REGISTRY_START_BLOCK=0"
    Write-Host "  LAUNCHER_START_BLOCK=0"
    Write-Host ""
    Write-Host "Then:"
    Write-Host "  cd indexer; npm install; npm run codegen; npm run dev"
    Write-Host "  (needs Node.js >=22 and a Postgres DATABASE_URL in .env too)"
    Write-Host ""
    Write-Host "Once the indexer is running, open aquity.html with:"
    Write-Host "  <script>window.AQUITY_API_BASE='http://localhost:42069'</script>"
    Write-Host "  added before its main <script> tag, to see this real data on the board."
    Write-Host ""
    Write-Host "anvil is running in the background (PID $($anvil.Id)) -- stop it with:"
    Write-Host "  Stop-Process -Id $($anvil.Id)"
} catch {
    Write-Error $_
    Stop-Process -Id $anvil.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
