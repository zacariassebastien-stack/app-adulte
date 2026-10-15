param(
  [string]$PsqlPath = 'psql',
  [string]$Database = 'concept_usage_test',
  [int]$Port = 5432
)
$ErrorActionPreference = 'Stop'
if ($Database -notmatch '^concept_usage_test[a-zA-Z0-9_]*$') {
  throw 'Use a fresh disposable concept_usage_test* database.'
}
$repoDirectory = Split-Path -Parent $PSScriptRoot
$psqlCommand = Get-Command $PsqlPath -ErrorAction Stop
# Always loopback; this runner cannot be pointed at a remote Supabase instance.
$psqlArguments = @('-X', '--host=127.0.0.1', "--port=$Port", "--dbname=$Database", '-v', 'ON_ERROR_STOP=1')
& $psqlCommand.Source @psqlArguments --single-transaction --file="$repoDirectory/supabase/tests/local_bootstrap.sql"
if ($LASTEXITCODE -ne 0) { throw 'Local bootstrap failed.' }
foreach ($migrationFile in Get-ChildItem -LiteralPath "$repoDirectory/supabase/migrations" -Filter '*.sql' | Sort-Object Name) {
  & $psqlCommand.Source @psqlArguments --single-transaction ('--file=' + $migrationFile.FullName)
  if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($migrationFile.Name)" }
}
& $psqlCommand.Source @psqlArguments --file="$repoDirectory/supabase/tests/concept_usage_contract.sql"
if ($LASTEXITCODE -ne 0) { throw 'Local RPC integration checks failed.' }
