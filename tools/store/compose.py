"""Сборка карточек для сторов: общий фон-панорама + телефон со скриншотом + подписи."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = '/Users/Dom/Джадуаль'
RAW = f'{ROOT}/app/tmp/store/raw'
OUT = f'{ROOT}/store/screenshots'
FONT = f'{ROOT}/app/assets/fonts/Inter.ttf'
SHOTS = ['1-home', '2-today', '3-calendar', '4-reminders', '5-reader']

TEXT = {
    'ru': [
        ('Время намаза\nпо вашему городу', 'Живой отсчёт до следующей молитвы'),
        ('Молитвы и дела дня\nна одном экране', 'Утренние и вечерние зикры, свои дела'),
        ('Тетрадь\nпостоянства', 'Календарь покажет ваши дни без пропусков'),
        ('Напоминания\nв нужное время', 'Зикры, аль-Кахф, час дуа и ваши дела'),
        ('Зикры с источником\nи транскрипцией', 'Арабский текст и удобные темы чтения'),
    ],
    'kz': [
        ('Қалаңыз бойынша\nнамаз уақыты', 'Келесі намазға дейінгі тірі санақ'),
        ('Намаз уақыты мен күн\nістері бір экранда', 'Таңертеңгі, кешкі зікір және өз істеріңіз'),
        ('Тұрақтылық\nдәптері', 'Күнтізбеде орындалған күндеріңіз көрінеді'),
        ('Уақытылы\nеске салғыштар', 'Зікір, Кәһф сүресі, жұма дұғасы, өз істеріңіз'),
        ('Дереккөзі бар зікір\nжәне транскрипция', 'Араб мәтіні және ыңғайлы оқу тақырыптары'),
    ],
}

# Панорама: тёмно-синий → бирюзовый → тёплое золото (цвета приложения).
STOPS = [
    (0.00, (22, 42, 66)),
    (0.30, (28, 74, 98)),
    (0.60, (38, 104, 116)),
    (0.82, (122, 112, 78)),
    (1.00, (176, 138, 62)),
]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def color_at(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def panorama(w, h, n):
    """Один непрерывный фон на все n карточек."""
    total = w * n
    strip = Image.new('RGB', (total, 1))
    px = strip.load()
    for x in range(total):
        px[x, 0] = color_at(x / (total - 1))
    img = strip.resize((total, h), Image.BILINEAR)
    # лёгкая вертикальная тень внизу
    shade = Image.new('L', (1, h))
    sp = shade.load()
    for y in range(h):
        sp[0, y] = int(70 * (y / h) ** 2)
    shade = shade.resize((total, h))
    img = Image.composite(Image.new('RGB', (total, h), (8, 16, 28)), img, shade)
    d = ImageDraw.Draw(img, 'RGBA')
    # восьмиконечные звёзды (два квадрата) — фирменный узор, едва заметный
    step = int(h * 0.20)
    r = step * 0.42
    for row in range(-1, h // step + 2):
        for col in range(-1, total // step + 2):
            cx = col * step + (step / 2 if row % 2 else 0)
            cy = row * step
            for ang in (0, 45):
                a = math.radians(ang)
                pts = [(cx + r * math.cos(a + k * math.pi / 2 + math.pi / 4),
                        cy + r * math.sin(a + k * math.pi / 2 + math.pi / 4)) for k in range(4)]
                d.polygon(pts, outline=(255, 255, 255, 14))
    # сквозная золотая дуга через все карточки
    glow = Image.new('RGBA', (total, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    R = total * 0.62
    cx, cy = total / 2, h * 1.55
    gd.ellipse([cx - R, cy - R * 0.55, cx + R, cy + R * 0.55 + h * 0.9], outline=(240, 205, 120, 120), width=max(3, h // 600))
    img = Image.alpha_composite(img.convert('RGBA'), glow).convert('RGB')
    return img


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius, fill=255)
    out = img.convert('RGBA')
    out.putalpha(mask)
    return out


def phone(shot, width):
    """Скриншот в тёмной рамке телефона со скруглениями."""
    sw = int(width * 0.965)
    sh = int(shot.size[1] * sw / shot.size[0])
    s = shot.resize((sw, sh), Image.LANCZOS)
    bezel = int(width * 0.018)
    ph, pw = sh + 2 * bezel, sw + 2 * bezel
    body = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    outer = int(pw * 0.15)
    bd.rounded_rectangle([0, 0, pw - 1, ph - 1], outer, fill=(14, 18, 24, 255), outline=(70, 80, 92, 255), width=max(2, bezel // 4))
    body.alpha_composite(rounded(s, outer - bezel), (bezel, bezel))
    return body


def wrap_lines(text):
    return text.split('\n')


def compose(lang, w, h, folder):
    os.makedirs(f'{OUT}/{folder}/{lang}', exist_ok=True)
    pano = panorama(w, h, len(SHOTS))
    big = ImageFont.truetype(FONT, int(w * 0.074))
    big.set_variation_by_name('Bold')
    small = ImageFont.truetype(FONT, int(w * 0.040))
    small.set_variation_by_name('Medium')
    for i, name in enumerate(SHOTS):
        card = pano.crop((i * w, 0, (i + 1) * w, h)).convert('RGBA')
        title, sub = TEXT[lang][i]
        d = ImageDraw.Draw(card)
        y = int(h * 0.055)
        for line in wrap_lines(title):
            tw = d.textlength(line, font=big)
            d.text(((w - tw) / 2, y), line, font=big, fill=(255, 255, 255, 255))
            y += int(big.size * 1.2)
        y += int(w * 0.018)
        tw = d.textlength(sub, font=small)
        d.text(((w - tw) / 2, y), sub, font=small, fill=(255, 238, 205, 235))
        shot = Image.open(f'{RAW}/{lang}-{name}.png').convert('RGB')
        pw = int(w * 0.80)
        ph_img = phone(shot, pw)
        # телефон смещается чуть по ширине — «ползёт» вслед за фоном
        shift = int((i - 2) * w * 0.012)
        x = (w - ph_img.size[0]) // 2 + shift
        top = y + int(h * 0.055)
        # тень
        sh_layer = Image.new('RGBA', card.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh_layer)
        sd.rounded_rectangle([x, top + 30, x + ph_img.size[0], top + ph_img.size[1] + 30], int(pw * 0.15), fill=(0, 0, 0, 120))
        sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(int(w * 0.02)))
        card = Image.alpha_composite(card, sh_layer)
        card.alpha_composite(ph_img, (x, top))
        card.convert('RGB').save(f'{OUT}/{folder}/{lang}/{i + 1:02d}-{name.split("-", 1)[1]}.png', optimize=True)


if __name__ == '__main__':
    for lang in ('ru', 'kz'):
        compose(lang, 1320, 2868, 'ios-6.9')
        compose(lang, 1080, 2160, 'google-play')
    print('ok')
