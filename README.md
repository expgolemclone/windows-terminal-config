# Windows Terminal configuration

Windows Terminal stable版の`settings.json`を管理するrepositoryです.

`C:\dev\settings\windows-terminal-config`は, Windows Terminalが使用する`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState`へのdirectory junctionです. このため, repository内の`settings.json`がLive設定の単一の正本です.

`state.json`, `elevated-state.json`, `buffer_*.txt`はWindows Terminalが生成するruntime状態であり, version管理しません.

`firstWindowPreference`は`defaultProfile`に固定し, 過去のwindow layoutを復元しません. 設定を検証するには次を実行します.

```powershell
pwsh -NoProfile -File .\tests\test-settings.ps1
```
