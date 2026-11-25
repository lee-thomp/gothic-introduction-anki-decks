(import csv hashlib)
(import pathlib [Path])

(require hyrule [->])

(setv deck-map
      {"lesson-1"
       {"declensions" {"*" declension}
        "exercises" {"*" exercise}
        "prepositions" preposition
        "vocabulary" vocabulary}})

(defn model-id [name]
  ;; Anki represents note IDs as Rust i64 where 0 has special meaning
  (let [i64-mask (- (<< 1 64) 1)]
    ;; This is a sort of poor-man's namespacing
    (-> f"lee-thomp:lambdin-gothic:model:{name}"
        .encode
        (hashlib.sha256)
        .digest
        (cut 0 8)
        (int.from_bytes "big")
        (& i64-mask)
        (or 1))))

(defclass TSV []
  (defn __init__ [self path]
    (setv self.path (Path path))
    (with [stream (.open self.path :encoding "utf-8-sig" :newline "")]
      (setv separator-line (next stream None)
            columns-line (next stream None))
      (when (or (is separator-line None)
                (not (.startswith separator-line "#separator:")))
        (raise (ValueError f"{self.path}: expected #separator: header")))
      (when (or (is columns-line None)
                (not (.startswith columns-line "#columns:")))
        (raise (ValueError f"{self.path}: expected #columns: header")))
      (setv separator-name (.strip (.removeprefix separator-line "#separator:"))
            self.separator (.get {"tab" "\t"
                                  "comma" ","
                                  "semicolon" ";"
                                  "pipe" "|"
                                  "space" " "
                                  "colon" ":"}
                                 separator-name separator-name))
      (when (!= (len self.separator) 1)
        (raise (ValueError f"{self.path}: invalid separator {separator-name!r}")))
      (setv self.columns (next (csv.reader
                                [(.removeprefix columns-line "#columns:")]
                                :delimiter self.separator))
            self.rows (list (csv.reader stream :delimiter self.separator))))))
