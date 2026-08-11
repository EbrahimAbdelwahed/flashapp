"""Generate real .apkg fixtures with the Anki library itself.

Synthetic fixtures would only prove our parser agrees with our own assumptions.
These are written by Anki, so they carry whatever Anki actually emits.
"""
import os
import shutil
import struct
import sys
import zlib

from anki.collection import Collection
from anki.import_export_pb2 import ExportAnkiPackageOptions

OUT = sys.argv[1]
WORK = sys.argv[2]

shutil.rmtree(WORK, ignore_errors=True)
os.makedirs(WORK, exist_ok=True)
os.makedirs(OUT, exist_ok=True)


def tiny_png() -> bytes:
    """A 64x64 red PNG, hand-assembled so the fixture needs no image library.

    Deliberately not 1x1: a one-pixel image renders at one point and would hide a layout
    bug rather than expose it.
    """
    size = 64

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * size for _ in range(size))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def tiny_wav() -> bytes:
    """8 bytes of silence in a valid RIFF container."""
    data = b"\x80" * 8
    fmt = struct.pack("<4sIHHIIHH4sI", b"WAVE", 16, 1, 1, 8000, 8000, 1, 8, b"data", len(data))
    return b"RIFF" + struct.pack("<I", 4 + 24 + 8 + len(data)) + fmt[:4] + b"fmt " + fmt[4:] + data


col = Collection(os.path.join(WORK, "collection.anki2"))

deck_id = col.decks.id("Fixture Deck")

# --- 1. Basic -------------------------------------------------------------
basic = col.models.by_name("Basic")
n = col.new_note(basic)
n["Front"] = "Qual è la capitale d'Italia?"
n["Back"] = "Roma"
n.tags = ["geografia", "europa"]
col.add_note(n, deck_id)

# --- 2. Basic (and reversed card) -> two templates -> our "reversed" ------
rev = col.models.by_name("Basic (and reversed card)")
n = col.new_note(rev)
n["Front"] = "Bone"
n["Back"] = "Osso"
n.tags = ["english"]
col.add_note(n, deck_id)

# --- 3. Cloze with two deletions -----------------------------------------
cloze = col.models.by_name("Cloze")
n = col.new_note(cloze)
n["Text"] = "La {{c1::glicolisi}} avviene nel {{c2::citoplasma}}"
n["Back Extra"] = "Prima tappa della respirazione cellulare"
n.tags = ["biologia"]
col.add_note(n, deck_id)

# --- 4. Custom note type, 5 fields ---------------------------------------
custom = col.models.new("Cinque Campi")
for field in ["Termine", "Definizione", "Esempio", "Fonte", "Note"]:
    col.models.add_field(custom, col.models.new_field(field))
tmpl = col.models.new_template("Card 1")
tmpl["qfmt"] = "{{Termine}}"
tmpl["afmt"] = "{{FrontSide}}<hr id=answer>{{Definizione}}"
col.models.add_template(custom, tmpl)
col.models.add(custom)
custom = col.models.by_name("Cinque Campi")
n = col.new_note(custom)
n["Termine"] = "Entropia"
n["Definizione"] = "Misura del disordine di un sistema"
n["Esempio"] = "Il ghiaccio che si scioglie"
n["Fonte"] = "Termodinamica, cap. 2"
n["Note"] = "Da ripassare"
n.tags = ["fisica"]
col.add_note(n, deck_id)

# --- 5. HTML formatting, entities, embedded newlines ---------------------
n = col.new_note(basic)
n["Front"] = "Cos'è il <b>DNA</b>?<br>Definizione &amp; struttura"
n["Back"] = "<div>Acido desossiribonucleico</div><div>Doppia elica</div>&nbsp;&mdash; Watson &amp; Crick"
col.add_note(n, deck_id)

# --- 6. Image and audio ---------------------------------------------------
png_name = col.media.write_data("rossa.png", tiny_png())
wav_name = col.media.write_data("suono.wav", tiny_wav())
n = col.new_note(basic)
n["Front"] = f'Che colore è questo? <img src="{png_name}">'
n["Back"] = f"Rosso [sound:{wav_name}]"
n.tags = ["media"]
col.add_note(n, deck_id)

# --- 7. Rows our validation must refuse ----------------------------------
n = col.new_note(basic)
n["Front"] = "Domanda senza risposta"
n["Back"] = ""
col.add_note(n, deck_id)

n = col.new_note(cloze)
n["Text"] = "Questa frase non ha nessuna cancellazione"
col.add_note(n, deck_id)

col.save()

for legacy, name in ((True, "legacy.apkg"), (False, "modern.apkg")):
    path = os.path.join(OUT, name)
    if os.path.exists(path):
        os.remove(path)
    count = col.export_anki_package(
        out_path=path,
        options=ExportAnkiPackageOptions(
            with_scheduling=False, with_deck_configs=False, with_media=True, legacy=legacy
        ),
        limit=None,
    )
    print(f"{name}: {count} notes, {os.path.getsize(path)} bytes")

# An .apkg with no notes at all: the empty-input edge case.
empty = Collection(os.path.join(WORK, "empty.anki2"))
empty.decks.id("Mazzo Vuoto")
empty.save()
path = os.path.join(OUT, "empty.apkg")
if os.path.exists(path):
    os.remove(path)
empty.export_anki_package(
    out_path=path,
    options=ExportAnkiPackageOptions(
        with_scheduling=False, with_deck_configs=False, with_media=False, legacy=False
    ),
    limit=None,
)
print(f"empty.apkg: {os.path.getsize(path)} bytes")
empty.close()
col.close()
