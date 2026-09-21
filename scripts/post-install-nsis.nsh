; OpenCluely installer hooks.
;
; Local Whisper speech-to-text needs Python 3.10+. If it is missing, ask the
; user for permission and install Python 3.12 for the current user only
; (no admin rights needed). The Whisper venv + pip packages themselves are
; created by the in-app onboarding wizard on first launch, with live progress.
; Skipping the prompt is fine: Azure Speech / typed chat work without Python.

!define PYTHON_VERSION "3.12.8"
!define PYTHON_URL "https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-amd64.exe"

!macro customInstall
  IfSilent oc_py_done

  ; Already have Python >= 3.10? (py launcher first, then plain python)
  nsExec::ExecToStack 'cmd /c py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)"'
  Pop $0
  Pop $1
  StrCmp $0 "0" oc_py_done
  nsExec::ExecToStack 'cmd /c python -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)"'
  Pop $0
  Pop $1
  StrCmp $0 "0" oc_py_done

  MessageBox MB_YESNO|MB_ICONQUESTION "OpenCluely uses Python 3.10+ for local speech recognition (Whisper).$\r$\n$\r$\nPython was not found on this PC. Download and install Python ${PYTHON_VERSION} now?$\r$\n$\r$\n- Installs for your user only (no admin needed)$\r$\n- Downloads about 25 MB from python.org$\r$\n- Adds Python to your PATH$\r$\n$\r$\nChoose No to skip. You can install Python later, or use Azure Speech instead." IDNO oc_py_done

  DetailPrint "Downloading Python ${PYTHON_VERSION}..."
  nsExec::ExecToLog 'powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $$ProgressPreference = $\'SilentlyContinue$\'; Invoke-WebRequest -UseBasicParsing -Uri ${PYTHON_URL} -OutFile $\'$TEMP\opencluely-python-setup.exe$\'"'
  Pop $0
  StrCmp $0 "0" +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "Could not download Python (exit code $0). Check your internet connection and install Python 3.10+ from python.org later."
  Goto oc_py_done

  DetailPrint "Installing Python ${PYTHON_VERSION}..."
  ExecWait '"$TEMP\opencluely-python-setup.exe" /passive InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0 Include_doc=0' $0
  Delete "$TEMP\opencluely-python-setup.exe"
  StrCmp $0 "0" +2
  MessageBox MB_OK|MB_ICONEXCLAMATION "Python setup did not finish (exit code $0). Install Python 3.10+ from python.org later to use local Whisper."

  oc_py_done:
!macroend

!macro customUnInstall
!macroend
