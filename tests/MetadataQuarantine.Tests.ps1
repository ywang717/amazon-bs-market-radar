Import-Module (Join-Path $PSScriptRoot '../src/BestSellersPostgres.psm1') -Force
Describe 'Metadata quarantine partition' {
 It 'isolates trusted conflicts while retaining normal and unknown rows' {
  $rows=@([pscustomobject]@{asin='B000000001';brand_source='verified_metadata';normalized_brand_key='new';raw_brand='New'},[pscustomobject]@{asin='B000000002';brand_source='unknown';normalized_brand_key=$null},[pscustomobject]@{asin='B000000003';brand_source='manual_review';normalized_brand_key='same'})
  $stored=@([pscustomobject]@{asin='B000000001';brand_source='manual_review';normalized_brand_key='old';raw_brand='Old'},[pscustomobject]@{asin='B000000003';brand_source='verified_metadata';normalized_brand_key='same'})
  $r=Split-BestSellersMetadataConflicts -MetadataRows $rows -StoredBrands $stored -MarketDate '2026-10-23' -SourceSha ('a'*64)
  @($r.Accepted).Count | Should Be 2
  @($r.Conflicts).Count | Should Be 1
  $r.Conflicts[0].asin | Should Be 'B000000001'
  $r.Conflicts[0].old_brand | Should Be 'Old'
  $rows[0].brand_source | Should Be 'verified_metadata'
 }
}
Describe 'Quarantine edge cases and publication warning state' {
 It 'quarantines missing trusted keys and keeps untrusted incoming brands eligible' {
  $incoming=@([pscustomobject]@{asin='B000000001';brand_source='manual_review';normalized_brand_key='new';raw_brand='New'},[pscustomobject]@{asin='B000000002';brand_source='unknown';normalized_brand_key=$null;raw_brand=$null})
  $stored=@([pscustomobject]@{asin='B000000001';brand_source='verified_metadata';normalized_brand_key=$null;raw_brand='Old'},[pscustomobject]@{asin='B000000002';brand_source='manual_review';normalized_brand_key='old';raw_brand='Old'})
  $r=Split-BestSellersMetadataConflicts -MetadataRows $incoming -StoredBrands $stored -MarketDate '2026-10-23' -SourceSha ('a'*64)
  @($r.Conflicts).Count|Should Be 1
  @($r.Accepted).Count|Should Be 1
  $r.Accepted[0].brand_source|Should Be 'unknown'
 }
 It 'round trips published warning counts and quarantine paths without credentials' {
  Import-Module (Join-Path $PSScriptRoot '../src/DashboardPublishState.psm1') -Force
  Write-DashboardPublishState -Root $TestDrive -MarketDate '2026-10-23' -Status PUBLISHED_WITH_WARNINGS -ObservationCount 510 -ReportsUploaded 17 -MetadataQuarantined 2 -MetadataQuarantinePath 'metadata-quarantine.json' | Out-Null
  $s=Read-DashboardPublishState -Root $TestDrive -MarketDate '2026-10-23'
  $s.Status|Should Be 'PUBLISHED_WITH_WARNINGS'
  $s.MetadataQuarantined|Should Be 2
  $s.MetadataQuarantinePath|Should Be 'metadata-quarantine.json'
 }
}
Describe 'Quarantine receipt transaction state' {
 It 'only reports imported metadata after a committed transaction' {
  $partition=[pscustomobject]@{Accepted=@(1,2);Conflicts=@()}
  foreach($state in @('PENDING','FAILED')){(New-BestSellersQuarantineReceipt -Partition $partition -Status $state -MarketDate '2026-10-23' -SourceSha ('a'*64)).metadata_imported|Should Be 0}
  (New-BestSellersQuarantineReceipt -Partition $partition -Status IMPORTED -MarketDate '2026-10-23' -SourceSha ('a'*64)).metadata_imported|Should Be 2
 }
}
Describe 'Bounded import race recovery' {
 It 'repartitions once after a concurrent trusted brand write and persists only committed counts' {
  $state=@{Reads=0;Imports=0;Receipts=(New-Object System.Collections.ArrayList)}
  $row=[pscustomobject]@{asin='B000000001';brand_source='verified_metadata';raw_brand='New';normalized_brand_key='new'}
  $read={ $state.Reads++;if($state.Reads -gt 1){[pscustomobject]@{asin='B000000001';brand_source='manual_review';raw_brand='Old';normalized_brand_key='old'}}}.GetNewClosure()
  $import={param($Rows) $state.Imports++;if($state.Imports -eq 1){throw 'concurrent brand conflict'};@($Rows).Count|Should Be 0}.GetNewClosure()
  $write={param($Receipt) [void]$state.Receipts.Add($Receipt)}.GetNewClosure()
  $r=Invoke-BestSellersQuarantineImport -MetadataRows @($row) -ReadStored $read -ImportRows $import -WriteReceipt $write -MarketDate '2026-10-23' -SourceSha ('a'*64)
  $state.Imports|Should Be 2
  @($r.Conflicts).Count|Should Be 1
  ($state.Receipts.status -join ',')|Should Be 'PENDING,FAILED,PENDING,IMPORTED'
 }
 It 'preserves ordinary failures without repeating an unchanged import' {
  $state=@{Imports=0;Receipts=(New-Object System.Collections.ArrayList)}
  $import={param($Rows)$state.Imports++;throw 'disk failure'}.GetNewClosure();$write={param($Receipt)[void]$state.Receipts.Add($Receipt)}.GetNewClosure()
  {Invoke-BestSellersQuarantineImport -MetadataRows @() -ReadStored {@()} -ImportRows $import -WriteReceipt $write -MarketDate '2026-10-23' -SourceSha ('a'*64)} | Should Throw 'disk failure'
  $state.Imports|Should Be 1
  $state.Receipts[-1].status|Should Be 'FAILED'
  $state.Receipts[-1].metadata_imported|Should Be 0
 }
}
