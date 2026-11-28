(import argparse csv hashlib os tempfile)
(import collections [Counter])
(import html [escape])
(import pathlib [Path])
(import genanki)

(require hyrule [-> unless])

(setv css (.read_text (Path "anki.css") :encoding "utf-8"))

(defn stable-id [kind name]
  "Return a stable, nonzero signed 64-bit ID for a model or deck."
  (let [mask (- (<< 1 63) 1)]
    (-> f"lee-thomp:lambdin-gothic:{kind}:{name}"
        .encode
        (hashlib.sha256)
        .digest
        (cut 0 8)
        (int.from_bytes "big")
        (& mask)
        (or 1))))

(defn model-id [name] (stable-id "model" name))
(defn deck-id [name] (stable-id "deck" name))

(defclass TSV []

  (defn __init__ [self path]
    (with [stream (.open (Path path) :encoding "utf-8-sig" :newline "")]
      (let [separator-line (next stream None)
            columns-line   (next stream None)
            separator-line-valid? (and separator-line
                                       (.startswith separator-line "#separator:"))
            columns-line-valid?   (and columns-line
                                       (.startswith columns-line "#columns:"))]
        (unless separator-line-valid?
          (raise (ValueError f"{path}: expected #separator: header")))
        (unless columns-line-valid?
          (raise (ValueError f"{path}: expected #columns: header")))
        (let [separator-name (-> separator-line
                                 (.removeprefix "#separator:")
                                 (.strip))
              separator-char (.get {"tab" "\t"
                                    "comma" ","
                                    "semicolon" ";"
                                    "pipe" "|"
                                    "space" " "
                                    "colon" ":"} separator-name None)]
          (unless separator-char
            (raise (ValueError f"{path}: invalid separator {separator-name!r}")))
          (let [columns (next (csv.reader
                                [(.removeprefix columns-line "#columns:")]
                                :delimiter separator-char))
                rows (list (csv.reader stream :delimiter separator-char))]
            (unless rows
              (raise (ValueError f"{path}: no data rows")))
            (for [[number row] (enumerate rows 3)]
              (when (!= (len row) (len columns))
                (raise
                  (ValueError f"{path}:{number}: expected {(len columns)} columns, got {(len row)}"))))
            (setv self.path path
                  self.columns columns
                  self.rows rows)))))
    ))

(setv vocabulary-model
      (genanki.Model
        (model-id "Gothic Vocabulary") "Gothic Vocabulary"
        :fields [{"name" "Gothic"} {"name" "English"} {"name" "Notes"}]
        :templates [{"name" "Gothic to English"
                     "qfmt" "{{Gothic}}"
                     "afmt" (+ "{{FrontSide}}<hr id=\"answer\">"
                               "{{#Notes}}<div class=\"notes\">{{Notes}}</div>{{/Notes}}"
                               "<div class=\"translation\">{{English}}</div>")}]
        :css css))

(setv basic-model
      (genanki.Model
        (model-id "Gothic Translation") "Gothic Translation"
        :fields [{"name" "Front"} {"name" "Back"}]
        :templates [{"name" "Front to back"
                     "qfmt" "{{Front}}"
                     "afmt" "{{FrontSide}}<hr id=\"answer\">{{Back}}"}]
        :css css))

(setv declension-model
      (genanki.Model
        (model-id "Gothic Declension Gap") "Gothic Declension Gap"
        :fields [{"name" "Label"}
                 {"name" "QuestionTable"}
                 {"name" "AnswerTable"}]
        :templates [{"name" "Fill the gap"
                     "qfmt" "{{QuestionTable}}"
                     "afmt" "{{AnswerTable}}"}]
        :css css))

(defn require-columns [table expected]
  (when (!= table.columns expected)
    (raise (ValueError f"{table.path}: expected {(', '.join expected)} columns"))))

(defn translation-notes [table name model]
  (let [occurrences (Counter)
        notes []]
    (for [row table.rows]
      (when (or (not (get row 0)) (not (get row 1)))
        (raise (ValueError f"{table.path}: first two fields must be nonempty")))
      (let [front (get row 0)
            count (+ (.get occurrences (get row 0) 0) 1)]
        (setv (get occurrences front) count)
        (.append notes
          (genanki.Note
            :model model
            :fields (lfor value row (escape value))
            :guid (genanki.guid_for
                    "gothic-anki" name front (str count))))))
    notes))

(defn vocabulary [table name]
  (require-columns table ["Gothic" "English" "Notes"])
  (translation-notes table name vocabulary-model))

(defn preposition [table name]
  (require-columns table ["Preposition + Noun Case" "Meaning"])
  (translation-notes table name basic-model))

(defn exercise [table name]
  (require-columns table ["Gothic" "English"])
  (translation-notes table name basic-model))

(defn table-html [columns rows gap answer]
  (let [header (.join "" (lfor column columns f"<th>{(escape column)}</th>"))
        body []]
    (for [[row-number row] (enumerate rows)]
      (let [cells [f"<th>{(escape (get row 0))}</th>"]]
        (for [column-number [1 2]]
          (let [value (escape (get row column-number))]
            (when (= [row-number column-number] gap)
              (setv value (if answer f"<strong>{value}</strong>" "?")))
            (.append cells
              (if (and (not answer)
                       (= [row-number column-number] gap))
                "<td class=\"gap\">?</td>"
                f"<td>{value}</td>"))))
        (.append body (+ "<tr>" (.join "" cells) "</tr>"))))
    (+ "<table class=\"declension\"><thead><tr>"
       header
       "</tr></thead><tbody>"
       (.join "" body)
       "</tbody></table>")))

(defn declension [table name]
  (require-columns table ["Case" "Singular" "Plural"])
  (let [cases (lfor row table.rows (get row 0))
        notes []]
    (when (or (not (all cases)) (!= (len cases) (len (set cases))))
      (raise (ValueError f"{table.path}: case names must be nonempty and unique")))
    (for [[row-number row] (enumerate table.rows)]
      (for [column-number [1 2]]
        (let [form (get row column-number)]
          (when (and form (!= form "---"))
            (let [column (get table.columns column-number)
                  label f"{table.path.stem} {(get row 0)} {column}"
                  gap [row-number column-number]]
              (.append notes
                (genanki.Note
                  :model declension-model
                  :fields [(escape label)
                           (table-html table.columns table.rows gap False)
                           (table-html table.columns table.rows gap True)]
                  :guid (genanki.guid_for
                          "gothic-anki" name (get row 0) column))))))))
    notes))

;; Keys describe paths relative to the project root. A "*" matches one TSV stem.
(setv deck-map
      {"Gothic"
       {"Lesson 1"
        {"Declensions" {"*" declension}
         "Exercises" {"*" exercise}
         "Prepositions" preposition
         "Vocabulary" vocabulary}}})

(defn handler-for [path]
  (let [node deck-map]
    (for [part (getattr (.with_suffix path "") "parts")]
      (when (not (isinstance node dict))
        (raise (ValueError f"{path}: no deck mapping")))
      (setv node (.get node part (.get node "*" None)))
      (when (is node None)
        (raise (ValueError f"{path}: no deck mapping"))))
    (when (not (callable node))
      (raise (ValueError f"{path}: no deck mapping")))
    node))

(defn build-package [paths output]
  (let [root (.resolve (Path.cwd))
        seen (set)
        decks []]
    (for [path paths]
      (setv path (Path path))
      (when (or (.is_absolute path)
                (!= path.suffix ".tsv")
                (in ".." path.parts)
                (not (.is_relative_to (.resolve path) root)))
        (raise (ValueError f"{path}: expected a project-root-relative TSV path")))
      (when (in path seen)
        (raise (ValueError f"{path}: duplicate input")))
      (.add seen path)
      (let [name (.join "::" (getattr (.with_suffix path "") "parts"))
            handler (handler-for path)
            table (TSV path)
            current-deck (genanki.Deck (deck-id name) name)]
        (for [note (handler table name)]
          (.add_note current-deck note))
        (when current-deck.notes
          (.append decks current-deck))))
    (when (not decks)
      (raise (ValueError "no cards found")))
    (setv output (Path output))
    (.mkdir output.parent :parents True :exist_ok True)
    (with [temporary (tempfile.NamedTemporaryFile
                       :dir output.parent :suffix ".apkg" :delete False)]
      (setv temporary-path (Path temporary.name)))
    (try
      (.write_to_file (genanki.Package decks) (str temporary-path))
      (os.replace temporary-path output)
      (finally
        (.unlink temporary-path :missing_ok True)))
    [(sum (gfor current-deck decks (len current-deck.notes)))
     (len decks)]))

(defn main []
  (let [parser (argparse.ArgumentParser
                 :description "Build an Anki package from project-relative TSV files.")]
    (.add_argument parser "-o" "--output" :required True :type Path)
    (.add_argument parser "files" :nargs "+" :type Path)
    (setv args (.parse_args parser))
    (try
      (let [[cards decks] (build-package args.files args.output)]
        (print f"Wrote {args.output} ({cards} cards in {decks} decks)"))
      (except [error [ValueError OSError]]
        (.error parser (str error))))))

(when (= __name__ "__main__")
  (main))
