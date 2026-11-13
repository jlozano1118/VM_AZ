<#
.SYNOPSIS
  Elige la región de Azure más barata (y, a igual precio, la más cercana)
  donde tu suscripción puede crear las VMs, y genera region.auto.tfvars.
  No crea ningún recurso: solo consulta información, así que no cuesta nada.
#>
[CmdletBinding()]
param(
    [string[]] $VmSizes        = @("Standard_B1s", "Standard_B2ats_v2"), # tamaños del cupo gratuito
    [int]      $VmCount        = 2,
    [double]   $OriginLat      = 4.7110,     # Bogotá
    [double]   $OriginLon      = -74.0721,
    [string[]] $ExcludeRegions = @(),
    [string]   $OutFile        = (Join-Path $PSScriptRoot "..\region.auto.tfvars")
)

function Invoke-AzJson([string[]] $AzArgs) {
    $raw = & az @AzArgs --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw "Falló: az $($AzArgs -join ' ')" }
    if (-not $raw) { return @() }
    return ($raw | Out-String | ConvertFrom-Json)
}

function Get-DistanceKm([double]$lat1, [double]$lon1, [double]$lat2, [double]$lon2) {
    $r = 6371; $toRad = [Math]::PI / 180
    $dLat = ($lat2 - $lat1) * $toRad; $dLon = ($lon2 - $lon1) * $toRad
    $a = [Math]::Sin($dLat/2) * [Math]::Sin($dLat/2) +
         [Math]::Cos($lat1*$toRad) * [Math]::Cos($lat2*$toRad) *
         [Math]::Sin($dLon/2) * [Math]::Sin($dLon/2)
    return [Math]::Round($r * 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a)))
}

function Get-LinuxHourlyPrice([string]$region, [string]$size) {
    $filter = "serviceName eq 'Virtual Machines' and priceType eq 'Consumption' " +
              "and armRegionName eq '$region' and armSkuName eq '$size'"
    $url = "https://prices.azure.com/api/retail/prices?`$filter=" + [uri]::EscapeDataString($filter)
    $items = (Invoke-RestMethod -Uri $url -Method Get).Items |
        Where-Object { $_.productName -notmatch 'Windows' -and
                       $_.skuName -notmatch 'Spot|Low Priority' -and
                       $_.meterName -notmatch 'Spot|Low Priority' }
    if (-not $items) { return $null }
    return ($items | Measure-Object -Property retailPrice -Minimum).Minimum
}

Write-Host "`n[1/4] Leyendo regiones permitidas por la política de la suscripción..." -ForegroundColor Cyan
$allowed = @()
$assignments = Invoke-AzJson @("policy","assignment","list","--query",
    "[?contains(displayName,'region') || contains(displayName,'location')]")
foreach ($a in $assignments) {
    if (-not $a.parameters) { continue }
    foreach ($p in $a.parameters.PSObject.Properties) {
        if ($p.Value.value -is [System.Array]) { $allowed += $p.Value.value }
    }
}
$allowed = $allowed | ForEach-Object { $_.ToLower() } | Sort-Object -Unique |
           Where-Object { $ExcludeRegions -notcontains $_ }
if (-not $allowed) { throw "No se encontraron regiones permitidas. Revisa la política en el portal." }
Write-Host ("      Permitidas: " + ($allowed -join ", "))

Write-Host "[2/4] Obteniendo coordenadas de las regiones..." -ForegroundColor Cyan
$locs = Invoke-AzJson @("account","list-locations","--query",
    "[?metadata.regionType=='Physical'].{name:name, lat:metadata.latitude, lon:metadata.longitude}")

Write-Host "[3/4] Evaluando disponibilidad, cuota y precio por región (tarda ~1 min)..." -ForegroundColor Cyan
$results = @()
foreach ($region in $allowed) {
    Write-Host "      -> $region"
    $loc  = $locs | Where-Object { $_.name -eq $region } | Select-Object -First 1
    $dist = if ($loc) { Get-DistanceKm $OriginLat $OriginLon ([double]$loc.lat) ([double]$loc.lon) } else { 99999 }

    $skus  = Invoke-AzJson @("vm","list-skus","--location",$region,"--resource-type","virtualMachines","--size","Standard_B")
    $usage = Invoke-AzJson @("vm","list-usage","--location",$region)
    $total = $usage | Where-Object { $_.name.value -eq "cores" } | Select-Object -First 1

    foreach ($size in $VmSizes) {
        $sku = $skus | Where-Object { $_.name -eq $size } | Select-Object -First 1
        $estado = "OK"; $precio = $null

        if (-not $sku) { $estado = "No ofrecido" }
        elseif ($sku.restrictions -and $sku.restrictions.Count -gt 0) {
            $estado = "Restringido: " + $sku.restrictions[0].reasonCode
        }
        else {
            $vcpu   = [int](($sku.capabilities | Where-Object { $_.name -eq "vCPUs" }).value)
            $need   = $vcpu * $VmCount
            $family = $usage | Where-Object { $_.name.value -eq $sku.family } | Select-Object -First 1
            $freeFam   = if ($family) { $family.limit - $family.currentValue } else { 0 }
            $freeTotal = if ($total)  { $total.limit  - $total.currentValue  } else { 0 }
            if ($freeFam -lt $need -or $freeTotal -lt $need) {
                $estado = "Sin cuota (necesita $need vCPU, familia libre $freeFam, total libre $freeTotal)"
            } else {
                $precio = Get-LinuxHourlyPrice $region $size
                if ($null -eq $precio) { $estado = "Sin precio publicado" }
            }
        }

        $results += [pscustomobject]@{
            Region      = $region
            Tamano      = $size
            DistanciaKm = $dist
            USD_hora_VM = $precio
            USD_hora_x2 = if ($precio) { [Math]::Round($precio * $VmCount, 4) } else { $null }
            Estado      = $estado
        }
    }
}

Write-Host "`n[4/4] Resultado:" -ForegroundColor Cyan
$results | Sort-Object @{e={ if ($_.Estado -eq "OK") {0} else {1} }}, USD_hora_VM, DistanciaKm |
    Format-Table -AutoSize | Out-Host

$best = $results | Where-Object { $_.Estado -eq "OK" } |
        Sort-Object USD_hora_VM, DistanciaKm | Select-Object -First 1
if (-not $best) { throw "Ninguna región/tamaño cumple los requisitos." }

$content = @"
# Generado automáticamente por scripts/select-region.ps1 el $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# Precio de referencia (fuera del cupo gratuito): $($best.USD_hora_VM) USD/hora por VM
location = "$($best.Region)"
vm_size  = "$($best.Tamano)"
"@

# UTF-8 sin BOM: Windows PowerShell 5.1 escribe UTF-16 con Out-File, y Terraform no lo lee.
$path = [System.IO.Path]::GetFullPath($OutFile)
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Elegida: $($best.Region) / $($best.Tamano)  ->  $path" -ForegroundColor Green