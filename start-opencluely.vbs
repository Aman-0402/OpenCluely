Set objShell = CreateObject("WScript.Shell")
objShell.CurrentDirectory = "D:\code\GITHUB\OpenCluely"
objShell.Run "cmd /c npx electron . --no-sandbox --disable-gpu", 0, False
