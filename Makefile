# Front end for the Linux Vivado machine and for Mac-side checks.
# On Windows use:  scripts\run.bat <target>
.PHONY: m0 check clean

m0:            ## Milestone 0: DFX smoke test (one RP, inv/buf RMs)
	./scripts/run.sh m0

check:         ## Mac-side: Python compile + unit tests (no Vivado needed)
	python3 -m py_compile pynq/selfheal/*.py pynq/m0_smoke.py
	python3 -m unittest discover -s tests -v

clean:         ## remove the gitignored build tree (keeps bitstreams/ and reports/)
	rm -rf build
