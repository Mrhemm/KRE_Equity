import pandas as pd
import geopandas as gpd
from pathlib import Path

BASE = Path(__file__).resolve().parent
PODES_DIR = BASE / "Data" / "PODES_ALL"
BPS_ADM4_PATH = BASE / "Data/idn_adm_bps_20200401_shp/idn_admbnda_adm4_bps_20200401.shp"


def id_desa_to_10_digit(value):
    """
    Convert PODES ID_DESA (8, 9, or 10 digits) to 10-digit numeric for BPS match.
    - 8 digits: prov(2)+kab(2)+kec(2)+desa(2) → pad desa to 4 → 10 digits.
    - 9 digits: prov(2)+kab(2)+kec(2)+desa(3) → pad desa to 4 → 10 digits.
    - 10 digits: return as-is.
    """
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    s = str(value).strip()
    if not s.isdigit():
        return None
    if len(s) == 10:
        return int(s)
    if len(s) == 8:
        return int(s[:6] + s[6:8].zfill(4))
    if len(s) == 9:
        return int(s[:6] + s[6:9].zfill(4))
    return None


def load_podes_with_2011_fix(podes_path):
    podes = pd.read_stata(podes_path)
    id_col = "IDDESA" if "IDDESA" in podes.columns else "ID_DESA"
    raw = podes[id_col].astype(str).str.strip()

    # Detect 8/9-digit codes (PODES 2011 style)
    lengths = raw.str.len()
    needs_convert = (lengths >= 8) & (lengths <= 9) & raw.str.isdigit()

    podes = podes.copy()
    if needs_convert.any():
        podes["id_desa_numeric"] = podes[id_col].apply(id_desa_to_10_digit)
    else:
        podes["id_desa_numeric"] = pd.to_numeric(podes[id_col], errors="coerce")

    podes_clean = podes.dropna(subset=["id_desa_numeric"]).copy()
    podes_clean["id_desa_numeric"] = podes_clean["id_desa_numeric"].astype("int64")
    return podes_clean


def diagnose_2011_vs_2024():
    p11_path = PODES_DIR / "podes_desa_2011.dta"
    p24_path = PODES_DIR / "podes_desa_2024.dta"
    if not p11_path.exists() or not p24_path.exists():
        print("PODES files not found")
        return

    p11 = pd.read_stata(p11_path)
    p24 = pd.read_stata(p24_path)
    id11 = "ID_DESA" if "ID_DESA" in p11.columns else "IDDESA"
    id24 = "IDDESA" if "IDDESA" in p24.columns else "ID_DESA"

    print("=== PODES 2011 vs 2024 ID format ===\n")
    print("2011 column:", id11, "  dtype:", p11[id11].dtype)
    print("2011 ID length counts:")
    print(p11[id11].astype(str).str.len().value_counts().sort_index())
    print("\n2024 column:", id24, "  dtype:", p24[id24].dtype)
    print("2024 ID length counts:")
    print(p24[id24].astype(str).str.len().value_counts().sort_index())

    # BPS 10-digit ids
    bps = gpd.read_file(BPS_ADM4_PATH)
    bps["_code"] = bps["ADM4_PCODE"].str.replace("ID", "").str.strip()
    bps = bps[bps["_code"].str.len() == 10]
    bps_ids = set(pd.to_numeric(bps["_code"], errors="coerce").dropna().astype("int64"))

    # Without fix: 2011 raw numeric
    p11_raw_num = pd.to_numeric(p11[id11], errors="coerce")
    p24_num = pd.to_numeric(p24[id24], errors="coerce")
    overlap_2011_raw = set(p11_raw_num.dropna().astype("int64")) & bps_ids
    overlap_2024 = set(p24_num.dropna().astype("int64")) & bps_ids
    print("\n=== BPS match (10-digit) ===\n")
    print("2011 (raw numeric) match BPS:", len(overlap_2011_raw))
    print("2024 match BPS:", len(overlap_2024))

    # With fix
    p11_fixed = load_podes_with_2011_fix(p11_path)
    overlap_2011_fixed = set(p11_fixed["id_desa_numeric"].unique()) & bps_ids
    print("\n2011 (after 8/9→10 digit fix) match BPS:", len(overlap_2011_fixed))
    print("\n=> Use load_podes_with_2011_fix() for PODES 2011 so R1 overlay matches many more villages.")


if __name__ == "__main__":
    diagnose_2011_vs_2024()
