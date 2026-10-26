function Invoke-ReportDrivers {
    param($Context)
    $drivers = @(Get-ReportWmi 'Win32_PnPSignedDriver' ([int]$Context.Config.Compatibilidade.Limites.wmiSegundos))
    Save-ReportEvidence $Context 'drivers.xml' ($drivers | Select-Object DeviceName,DriverProviderName,DriverVersion,DriverDate,DeviceID,HardWareID,InfName,IsSigned)
    foreach ($driver in $drivers) {
        Add-ReportRow $Context @{ tipo_registro='Driver'; categoria='Driver'; nome_item=$driver.DeviceName; fabricante_item=$driver.DriverProviderName; versao_instalada=$driver.DriverVersion; kb_ou_id=$driver.DeviceID; fonte='WMI/Win32_PnPSignedDriver'; status='Inventariado'; observacao=('Data={0}; INF={1}; assinado={2}. Inventario nao determina existencia de atualizacao.' -f $driver.DriverDate,$driver.InfName,$driver.IsSigned) }
    }
    Add-ReportStage $Context 'Drivers' 'Concluido' ('Dispositivos inventariados: ' + $drivers.Count) $drivers.Count
}

function Invoke-ReportFeatures {
    param($Context)
    $features = @(Get-ReportWmi 'Win32_ServerFeature' ([int]$Context.Config.Compatibilidade.Limites.wmiSegundos))
    Save-ReportEvidence $Context 'funcoes.xml' ($features | Select-Object ID,ParentID,Name)
    foreach ($feature in $features) {
        Add-ReportRow $Context @{ tipo_registro='FuncaoWindows'; categoria='FuncaoWindows'; nome_item=$feature.Name; fabricante_item='Microsoft'; kb_ou_id=$feature.ID; fonte='WMI/Win32_ServerFeature'; status='Inventariado'; observacao=('ParentID={0}; versao vinculada ao Windows.' -f $feature.ParentID) }
    }
    Add-ReportStage $Context 'FuncoesWindows' 'Concluido' ('Funcoes retornadas pelo provedor: ' + $features.Count) $features.Count
}
