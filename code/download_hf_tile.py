#!/usr/bin/env python3
"""
Robust chunked downloader for HuggingFace GBA tiles.
Handles the 1-hour signed URL expiry by re-fetching the redirect URL every chunk.
Supports resume via Range requests.

Usage:
    python3 code/download_hf_tile.py europe e005_n55_e010_n50
    nohup python3 code/download_hf_tile.py europe e005_n55_e010_n50 &
"""

import sys
import os
import time
import urllib.request
import urllib.error

# ---- config ----------------------------------------------------------------
HF_BASE = "https://huggingface.co/datasets/zhu-xlab/GBA.ODbLPolygon/resolve/main"
CACHE_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "gba_tiles_cache")
CHUNK_BYTES = 200 * 1024 * 1024   # 200 MB per request (re-fetches URL each time)
TIMEOUT_S   = 600                  # 10 min per chunk
MAX_RETRIES = 20
# ----------------------------------------------------------------------------

def get_total_size(url):
    """HEAD request to get total file size."""
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None

def download_chunk(url, dest, start, end):
    """Download bytes [start, end] and append to dest."""
    headers = {"Range": f"bytes={start}-{end}"}
    req = urllib.request.Request(url, headers=headers)
    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
                if resp.status not in (200, 206):
                    raise IOError(f"HTTP {resp.status}")
                with open(dest, "ab") as f:
                    written = 0
                    while True:
                        buf = resp.read(4 * 1024 * 1024)  # 4 MB read buffer
                        if not buf:
                            break
                        f.write(buf)
                        written += len(buf)
                return written
        except Exception as e:
            wait = 2 ** attempt
            print(f"  [retry {attempt+1}/{MAX_RETRIES}] {e} — waiting {wait}s...")
            time.sleep(wait)
    raise RuntimeError(f"Failed to download bytes {start}-{end} after {MAX_RETRIES} retries")

def main():
    if len(sys.argv) < 3:
        print("Usage: download_hf_tile.py <continent> <tile>")
        sys.exit(1)

    continent = sys.argv[1]
    tile      = sys.argv[2]
    url       = f"{HF_BASE}/{continent}/{tile}.geojson"
    dest      = os.path.join(CACHE_DIR, f"{tile}.geojson")
    os.makedirs(CACHE_DIR, exist_ok=True)

    # How much do we already have?
    resume_from = os.path.getsize(dest) if os.path.exists(dest) else 0

    print(f"URL    : {url}")
    print(f"Dest   : {dest}")
    print(f"Already: {resume_from / 1e9:.2f} GB")

    total = get_total_size(url)
    if total:
        print(f"Total  : {total / 1e9:.2f} GB")
    else:
        print("Total  : unknown")

    if total and resume_from >= total:
        print("Already complete — nothing to do.")
        return

    pos = resume_from
    t0  = time.time()

    while True:
        end = min(pos + CHUNK_BYTES - 1, (total - 1) if total else pos + CHUNK_BYTES - 1)
        pct = f"{100 * pos / total:.1f}%" if total else "?"
        print(f"  [{pct}] Downloading bytes {pos:,}–{end:,} ...", flush=True)

        written = download_chunk(url, dest, pos, end)
        pos += written

        elapsed = time.time() - t0
        speed   = (pos - resume_from) / elapsed / 1e6  # MB/s
        print(f"    => +{written/1e6:.1f} MB | total {pos/1e9:.2f} GB | {speed:.1f} MB/s", flush=True)

        if total and pos >= total:
            print(f"\nDownload complete: {dest}")
            break

        if written == 0:
            print("Nothing downloaded — stopping.")
            break

if __name__ == "__main__":
    main()
