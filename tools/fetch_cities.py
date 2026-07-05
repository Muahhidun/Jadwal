# -*- coding: utf-8 -*-
"""Скачивает полный справочник населённых пунктов ДУМК (api.muftyat.kz/cities)
и сохраняет в app/assets/data/cities.json для офлайн-поиска и авто-определения.

Запуск: python3 tools/fetch_cities.py
"""
import json, time, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets" / "data" / "cities.json"
BASE = "https://api.muftyat.kz/cities/?page={}"


def fetch(page):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(BASE.format(page), timeout=25) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(1.5)


def main():
    cities, page = [], 1
    while True:
        data = fetch(page)
        for c in data["results"]:
            try:
                lat, lng = float(c["lat"]), float(c["lng"])
            except (TypeError, ValueError):
                continue
            title = (c.get("title") or "").strip()
            if not title:
                continue
            cities.append({
                "t": title,
                "lat": round(lat, 5),
                "lng": round(lng, 5),
                "r": (c.get("region") or "").strip(),
                "tz": int(c.get("timezone") or 5),
            })
        if not data.get("next"):
            break
        page += 1
        if page % 10 == 0:
            print(f"…страница {page}")
    # Стабильный порядок: по названию.
    cities.sort(key=lambda c: c["t"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(cities, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    kb = OUT.stat().st_size / 1024
    print(f"OK: {len(cities)} пунктов → {OUT.relative_to(ROOT)} ({kb:.0f} КБ)")


if __name__ == "__main__":
    main()
