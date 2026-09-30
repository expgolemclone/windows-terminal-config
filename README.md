# Windows Terminal configuration

Windows Terminal stable版の`settings.json`を管理するrepositoryです.

Windows Terminalが使用する`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState`から, このrepositoryへのdirectory junctionを作ります. repository内の`settings.json`がLive設定の単一の正本です.

Windows Terminalをすべて閉じ, 独立したPowerShellまたはConsole Hostで次を実行します. `-WaitForTerminalExit`を付けると, すべてのTerminalが終了するまで待ってから接続します.

```powershell
pwsh -NoProfile -File .\setup.ps1
```

既存の`LocalState`は同じpackage directoryの`LocalState.backup-*`に保存され, `state.json`などのruntime状態はrepositoryへコピーされます. 正しいjunctionが既にあれば何もしません.

`state.json`, `elevated-state.json`, `buffer_*.txt`はWindows Terminalが生成するruntime状態であり, version管理しません.

既定のshellはPowerShell 7 (`pwsh`)です. Windows PowerShell, Command Prompt, Visual Studioの旧shell profilesはmenuに表示しません.

`Ctrl+Shift+N`はWindows Terminal側では標準の`Terminal.OpenNewWindow`に固定します. 同じdirectoryを維持する挙動はAutoHotkey側でWindows Terminalがactiveな場合だけ処理し, Terminalのtab tear-off (`duplicateTab` + `moveTab`) は使用しません.

`Ctrl+Shift+C/V`をコピーと貼り付けに使い, `Ctrl+C/V`のTerminal側のコピペ割り当てを解除します. 通常起動と同じアカウントの管理者起動に適用されます. PowerShell 7のprofile側では`Ctrl+C`を入力行のキャンセルに割り当て, `Ctrl+V`を解除します.

`firstWindowPreference`は`defaultProfile`に固定し, 過去のwindow layoutを復元しません. 設定を検証するには次を実行します.

```powershell
pwsh -NoProfile -File .\tests\test-settings.ps1
```
