#!/usr/bin/env python3
"""
تنزيل أصول Poly Haven (CC0) المستخدمة في اللعبة.

الاستخدام:
    python tools/polyhaven_fetch.py                 # الدقة الافتراضية (المرفقة بالمشروع)
    python tools/polyhaven_fetch.py --tex 4k        # خامات 4K لإعداد Ultra
    python tools/polyhaven_fetch.py --tex 8k --models 4k

الملفات تُحفظ في assets/polyhaven/. لا يحتاج أي مكتبة خارجية.
كل الأصول من polyhaven.com برخصة CC0 (ملكية عامة).
"""
import argparse
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "polyhaven")

# الخامات: الاسم في Poly Haven
TEXTURES = [
    "asphalt_02",                  # الشوارع
    "rectangular_paving",          # الأرصفة
    "concrete_pavement",           # حواف الأرصفة والساحات
    "red_brick_03",                # واجهات طوب
    "painted_plaster_wall",        # واجهات جص
    "concrete_wall_008",           # واجهات خرسانة
    "concrete_tile_facade",        # واجهات حديثة
    "rectangular_facade_tiles",    # واجهات بلاط
    "corrugated_iron",             # المخبأ
    "metal_plate",                 # تفاصيل معدنية
]

# المجسمات (glTF)
MODELS = [
    "street_lamp_01", "street_lamp_02", "fire_hydrant", "metal_trash_can", "modular_street_seating",
    "concrete_road_barrier_02", "trashbag", "planter_box_01", "shrub_03", "shrub_04",
    "utility_box_01", "utility_box_02", "water_manhole_cover", "exterior_aircon_unit", "modular_fire_escape",
    "rollershutter_door", "rollershutter_window_01", "security_camera_01", "security_light",
    "modular_airduct_circular_01", "covered_car", "modular_metal_gutter",
    "modular_urban_apartments_facade", "modular_factory_facade",
]


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "damar-asset-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "damar-asset-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(path + ".part", path)
    return True


def fetch_texture(name, res):
    files = get_json(f"{API}/files/{name}")
    out = os.path.join(ROOT, "textures", name)
    # اللون + النظامي (OpenGL) + ARM (إطباق/خشونة/معدنية) + الإزاحة
    for key, fname in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm"), ("Displacement", "disp")):
        entry = files.get(key, {}).get(res) or files.get(key, {}).get("2k")
        if not entry:
            continue
        info = entry.get("jpg") or entry.get("png")
        ext = "jpg" if "jpg" in entry else "png"
        if download(info["url"], os.path.join(out, f"{fname}_{res}.{ext}")):
            print(f"  {name}/{fname}_{res}.{ext}  {info['size'] // 1024} KB")


def fetch_model(name, res):
    files = get_json(f"{API}/files/{name}")
    g = files.get("gltf", {})
    entry = g.get(res) or g.get("1k")
    if not entry:
        print(f"  ! {name}: no glTF")
        return
    info = entry["gltf"]
    out = os.path.join(ROOT, "models", name)
    download(info["url"], os.path.join(out, f"{name}.gltf"))
    for rel, inc in info.get("include", {}).items():
        download(inc["url"], os.path.join(out, rel))
    print(f"  {name} ({res})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", default="2k", help="1k | 2k | 4k | 8k")
    ap.add_argument("--models", default="1k", help="1k | 2k | 4k")
    ap.add_argument("--only", default="", help="comma separated asset names")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    print("Textures:")
    for t in TEXTURES:
        if not only or t in only:
            fetch_texture(t, a.tex)
    print("Models:")
    for m in MODELS:
        if not only or m in only:
            fetch_model(m, a.models)
    print("Done. All assets: CC0, polyhaven.com")


if __name__ == "__main__":
    sys.exit(main())
