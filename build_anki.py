"""Build nested Anki decks from TSV files exported by org-table-anki.el."""

import argparse
from collections import Counter
import csv
import hashlib
from html import escape
import os
from pathlib import Path
import tempfile

import genanki


CSS = """
.card { font-family: sans-serif; font-size: 22px; text-align: center; }
.notes { font-size: 0.7em; opacity: 0.75; margin: 0.5em 0; }
.translation { margin-top: 0.5em; }
.declension { border-collapse: collapse; margin: 0 auto; }
.declension th, .declension td { border: 1px solid #888; padding: 0.35em 0.7em; }
.declension .gap { font-weight: bold; }
.declension strong { text-decoration: underline; }
"""

VOCABULARY_MODEL = genanki.Model(
    1836274101,
    "Gothic Vocabulary",
    fields=[{"name": name} for name in ("Gothic", "English", "Notes")],
    templates=[{
        "name": "Gothic to English",
        "qfmt": "{{Gothic}}",
        "afmt": '{{FrontSide}}<hr id="answer">'
                '{{#Notes}}<div class="notes">{{Notes}}</div>{{/Notes}}'
                '<div class="translation">{{English}}</div>',
    }],
    css=CSS,
)

BASIC_MODEL = genanki.Model(
    1836274102,
    "Gothic Translation",
    fields=[{"name": "Front"}, {"name": "Back"}],
    templates=[{
        "name": "Front to back",
        "qfmt": "{{Front}}",
        "afmt": '{{FrontSide}}<hr id="answer">{{Back}}',
    }],
    css=CSS,
)

DECLENSION_MODEL = genanki.Model(
    1836274103,
    "Gothic Declension Gap",
    fields=[{"name": "Label"}, {"name": "QuestionTable"}, {"name": "AnswerTable"}],
    templates=[{
        "name": "Fill the gap",
        "qfmt": "{{QuestionTable}}",
        "afmt": "{{AnswerTable}}",
    }],
    css=CSS,
)


def read_tsv(path):
    """Read one Anki-style TSV and return its column names and rows."""
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)
        separator = next(reader, None)
        columns_line = next(reader, None)
        if separator != ["#separator:tab"] or not columns_line or not columns_line[0].startswith("#columns:"):
            raise ValueError(f"{path}: expected #separator:tab and #columns: header lines")
        columns = [columns_line[0][len("#columns:"):], *columns_line[1:]]
        rows = list(reader)
    if not rows:
        raise ValueError(f"{path}: no data rows")
    for number, row in enumerate(rows, start=3):
        if len(row) != len(columns):
            raise ValueError(f"{path}:{number}: expected {len(columns)} columns, got {len(row)}")
    return columns, rows


def deck_id(name):
    """Give a deck name a stable positive 31-bit Anki ID."""
    digest = hashlib.sha256(("gothic-anki:deck:" + name).encode("utf-8")).digest()
    return (int.from_bytes(digest[:4], "big") & 0x3fffffff) | 0x40000000


def deck_name(deck_root, relative_path):
    parts = relative_path.with_suffix("").parts
    return "::".join([deck_root, *(part.replace("-", " ").replace("_", " ").title() for part in parts)])


def table_html(columns, rows, gap=None, answer=False):
    """Render a declension table, hiding or highlighting one cell."""
    header = "".join(f"<th>{escape(column)}</th>" for column in columns)
    body = []
    for row_number, row in enumerate(rows):
        cells = [f"<th>{escape(row[0])}</th>"]
        for column_number in (1, 2):
            value = escape(row[column_number])
            if (row_number, column_number) == gap:
                if answer:
                    value = f"<strong>{value}</strong>"
                else:
                    value = '?'
                    cells.append('<td class="gap">?</td>')
                    continue
            cells.append(f"<td>{value}</td>")
        body.append("<tr>" + "".join(cells) + "</tr>")
    return '<table class="declension"><thead><tr>' + header + "</tr></thead><tbody>" + "".join(body) + "</tbody></table>"


def add_notes(deck, deck_root, relative_path, columns, rows):
    """Add the appropriate notes for one TSV file."""
    source_key = f"{deck_root}:{relative_path.as_posix()}"
    if relative_path.parts[0] == "declensions":
        if columns != ["Case", "Singular", "Plural"]:
            raise ValueError(f"{relative_path}: expected Case, Singular, Plural columns")
        cases = [row[0] for row in rows]
        if not all(cases) or len(set(cases)) != len(cases):
            raise ValueError(f"{relative_path}: case names must be nonempty and unique")
        for row_number, row in enumerate(rows):
            for column_number in (1, 2):
                form = row[column_number]
                if not form or form == "---":
                    continue
                label = f"{relative_path.stem} {row[0]} {columns[column_number]}"
                deck.add_note(genanki.Note(
                    model=DECLENSION_MODEL,
                    fields=[
                        escape(label),
                        table_html(columns, rows, (row_number, column_number)),
                        table_html(columns, rows, (row_number, column_number), answer=True),
                    ],
                    guid=genanki.guid_for("gothic-anki", source_key, row[0], columns[column_number]),
                ))
    else:
        vocabulary = relative_path.stem == "vocabulary"
        expected = ["Gothic", "English", "Notes"] if vocabulary else None
        if (vocabulary and columns != expected) or (not vocabulary and len(columns) != 2):
            requirement = "Gothic, English, Notes" if vocabulary else "exactly two columns"
            raise ValueError(f"{relative_path}: expected {requirement}")
        occurrences = Counter()
        for row in rows:
            if not row[0] or not row[1]:
                raise ValueError(f"{relative_path}: first two fields must be nonempty")
            occurrences[row[0]] += 1
            deck.add_note(genanki.Note(
                model=VOCABULARY_MODEL if vocabulary else BASIC_MODEL,
                fields=[escape(value) for value in row],
                guid=genanki.guid_for("gothic-anki", source_key, row[0], str(occurrences[row[0]])),
            ))


def build_package(input_dir, output, deck_root="Gothic::Lesson 1"):
    """Build one importable package from all TSV files under INPUT_DIR."""
    paths = sorted(input_dir.rglob("*.tsv"))
    if not paths:
        raise ValueError(f"{input_dir}: no TSV files found")
    decks = []
    for path in paths:
        relative_path = path.relative_to(input_dir)
        columns, rows = read_tsv(path)
        name = deck_name(deck_root, relative_path)
        deck = genanki.Deck(deck_id(name), name)
        add_notes(deck, deck_root, relative_path, columns, rows)
        if deck.notes:
            decks.append(deck)
    if not decks:
        raise ValueError(f"{input_dir}: no cards found")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".apkg", delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        genanki.Package(decks).write_to_file(str(temporary_path))
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)
    return sum(len(deck.notes) for deck in decks), len(decks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", nargs="?", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output", "-o", type=Path, help="output .apkg path")
    parser.add_argument("--deck-root", default="Gothic::Lesson 1", help="parent deck name")
    args = parser.parse_args()
    output = args.output or args.input_dir / "lesson-1.apkg"
    try:
        cards, decks = build_package(args.input_dir, output, args.deck_root)
    except (ValueError, OSError) as error:
        parser.exit(1, f"error: {error}\n")
    print(f"Wrote {output} ({cards} cards in {decks} decks)")


if __name__ == "__main__":
    main()
