# Windows Terminal configuration

Windows Terminal stable版の設定を管理します. `settings.json`が単一の正本です. cloneだけでは適用されません.

## Apply

全Windows Terminalを閉じ, Terminal外のPowerShell 7から実行します. processの強制終了はしません.

```powershell
pwsh -NoProfile -File .\setup.ps1
pwsh -NoProfile -File .\verify.ps1
```

`setup.ps1 -WaitForTerminalExit`は変更が必要な場合だけ終了を待ちます. 正しく接続済みなら, 起動中でも検証してno-opで終了します. `-WhatIf`は変更しません.

`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState`をrepositoryへのjunctionにします. 既存directoryは同じpackage内の`LocalState.backup-*`へ保存します. runtime状態は引き継ぎ, version管理しません. 他のjunctionやruntime fileの衝突は上書きせず停止します. 接続・検証失敗時は元の状態へ復元します.

## Responsibilities

- Windowsの既定ターミナルはOS設定です. このrepositoryからregistryを変更しません.
- 既定shellはPowerShell 7のdynamic profileです. 通常起動は非昇格です.
- AHKは新規windowと開始directoryを指定し, shellを指定しません. 管理者起動は既存の昇格workerから行います.
- `Ctrl+Shift+C/V`がコピー・貼り付けです. `Ctrl+C/V`のTerminal割り当ては解除します.
- `Ctrl+Shift+N`は`Terminal.OpenNewWindow`です. 現directoryの引き継ぎはAHKが扱います. tab tear-offは使いません.
- 過去のwindow layoutは復元せず, 既定profileで新規windowを開きます.

## Verification

```powershell
pwsh -NoProfile -File .\tests\test-settings.ps1
pwsh -NoProfile -File .\tests\test-setup.ps1
pwsh -NoProfile -File .\verify.ps1
```

前2つはsourceと一時directoryでの回帰テストです. `verify.ps1`だけが実環境のjunctionと設定を確認し, 未接続なら失敗します. 新規windowのPowerShell version, directory, 通常・管理者tokenとPiの通知音は別途実動作で確認します.
