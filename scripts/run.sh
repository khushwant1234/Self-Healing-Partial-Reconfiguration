#!/usr/bin/env bash
# One-command unattended build on the Linux Vivado machine.
#   ./scripts/run.sh m0
# Builds, collects the log into reports/<target>/, prints the summary and the
# exact git commands to push results back. Safe to walk away from.
set -u
TARGET="${1:-m0}"
cd "$(dirname "$0")/.."
REPO="$(pwd)"

TCL="vivado/${TARGET}/build_${TARGET}.tcl"
[ -f "$TCL" ] || { echo "No build script $TCL"; exit 2; }

if ! command -v vivado >/dev/null 2>&1; then
  for s in /tools/Xilinx/Vivado/2020.2/settings64.sh \
           /opt/Xilinx/Vivado/2020.2/settings64.sh \
           "$HOME/Xilinx/Vivado/2020.2/settings64.sh"; do
    if [ -f "$s" ]; then . "$s"; break; fi
  done
fi
command -v vivado >/dev/null 2>&1 || {
  echo "ERROR: vivado not on PATH and settings64.sh not found in the usual places."
  echo "       source <Xilinx>/Vivado/2020.2/settings64.sh and re-run."
  exit 2
}

mkdir -p build/logs "reports/${TARGET}"
START=$(date +%s)
vivado -mode batch -notrace -source "$TCL" \
       -log "build/logs/${TARGET}_vivado.log" -journal "build/logs/${TARGET}_vivado.jou"
RC=$?
cp -f "build/logs/${TARGET}_vivado.log" "reports/${TARGET}/vivado.log" 2>/dev/null
echo
echo "================ ${TARGET}: vivado exit code ${RC}, $(( $(date +%s) - START )) s wall ================"
cat "reports/${TARGET}/SUMMARY.txt" 2>/dev/null || echo "(no SUMMARY.txt -- Vivado died before writing it; see reports/${TARGET}/vivado.log)"
echo
echo "Now push the results:"
echo "  git add bitstreams/${TARGET} reports/${TARGET}"
echo "  git commit -m \"${TARGET} build results ($(hostname), rc=${RC})\""
echo "  git push"
exit $RC
