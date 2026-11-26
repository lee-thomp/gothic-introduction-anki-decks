.DEFAULT_GOAL := all

venv := $(if $(wildcard .venv/bin/python),.venv,.)
python := $(venv)/bin/python
hy2py := $(venv)/bin/hy2py

sources := $(sort $(wildcard lesson-1/*.txt lesson-1/*/*.txt))
tsvs := $(sources:.txt=.tsv)
# Directory mtimes also catch removals from the wildcard source list.
source_dirs := $(wildcard lesson-1/ lesson-1/*/)

.PHONY: all
all: lesson-1.apkg

%.tsv: %.txt org-table-anki.el table-to-tsv.sh
	./table-to-tsv.sh "$<" "$@"

# Currently Hy 1.3.1 has issues running against Python 3.12.6 —this step gets
# around that for now.
build/build_anki.py: build_anki.hy
	mkdir -p $(@D)
	$(hy2py) --output "$@" "$<"

lesson-1.apkg: $(tsvs) $(source_dirs) build/build_anki.py
	$(python) build/build_anki.py -o "$@" $(tsvs)
