import os
import sys
from pathlib import Path


def is_vasp_dir(folder: Path) -> bool:
    """Identifies a directory as a VASP job if key input/output files exist."""
    vasp_files = {"INCAR", "POSCAR", "OUTCAR"}
    return any((folder / fname).exists() for fname in vasp_files)


def check_vasp_status(folder: Path) -> tuple[str, str]:
    """
    Inspects the end of OUTCAR for the standard VASP completion string.
    Returns (Status, Reason).
    """
    outcar = folder / "OUTCAR"

    if not outcar.exists():
        return "FAILED", "Missing OUTCAR file"

    try:
        # Fast tail-read: Seek last 4KB to avoid loading giant OUTCAR files
        with open(outcar, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 4000))
            tail = f.read().decode("utf-8", errors="ignore")

            if "General timing and accounting informations for this job:" in tail:
                return "SUCCESS", "Completed normally"
            else:
                return "FAILED", "Incomplete (crashed or hit time limit)"
    except Exception as e:
        return "FAILED", f"Read error ({e})"


def scan_directory(root_path: str):
    root = Path(root_path).resolve()
    succeeded = []
    failed = []

    for path in root.rglob("*"):
        if path.is_dir() and is_vasp_dir(path):
            status, detail = check_vasp_status(path)
            rel_path = path.relative_to(root)
            if status == "SUCCESS":
                succeeded.append(rel_path)
            else:
                failed.append((rel_path, detail))

    return succeeded, failed


if __name__ == "__main__":
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    succeeded, failed = scan_directory(target_dir)

    print(f"\n=== VASP Audit Report: {Path(target_dir).resolve()} ===")

    print(f"\n[✓] SUCCESSFUL RUNS ({len(succeeded)}):")
    for path in succeeded:
        print(f"  - {path}")

    print(f"\n[✗] FAILED OR INCOMPLETE RUNS ({len(failed)}):")
    for path, reason in failed:
        print(f"  - {path}  ({reason})")