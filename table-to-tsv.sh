#!/usr/bin/env bash

emacs --batch \
      --load org-table-anki.el \
      --eval "(gothic-anki-export-file \"$1\" \"$2\")"
