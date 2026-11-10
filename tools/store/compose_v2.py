"""Четыре варианта оформления карточек (только RU) для выбора владельцем."""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = '/Users/Dom/Джадуаль'
RAW = f'{ROOT}/app/tmp/store/raw2'
OUT = f'{ROOT}/store/screenshots/variants'
INTER = f'{ROOT}/app/assets/fonts/Inter.ttf'
SERIF = f'{ROOT}/app/assets/fonts/Literata.ttf'
W, H = 1320, 2868


def font(path, size, var):
    f = ImageFont.truetype(path, int(size))
    try:
        f.set_variation_by_name(var)
    except Exception:
        pass
    return f


def shot(name):
    return Image.open(f'{RAW}/{name}.png').convert('RGB')


def rounded(img, r):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], r, fill=255)
    o = img.convert('RGBA')
    o.putalpha(m)
    return o


def phone(s, width, frame=(14, 18, 24)):
    sw = int(width * 0.964)
    sh = int(s.size[1] * sw / s.size[0])
    s = s.resize((sw, sh), Image.LANCZOS)
    b = int(width * 0.018)
    pw, ph = sw + 2 * b, sh + 2 * b
    body = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
    r = int(pw * 0.15)
    ImageDraw.Draw(body).rounded_rectangle([0, 0, pw - 1, ph - 1], r, fill=frame + (255,), outline=(90, 98, 110, 255), width=max(2, b // 4))
    body.alpha_composite(rounded(s, r - b), (b, b))
    return body


def drop(canvas, obj, x, y, blur=40, alpha=130, dy=36):
    sh = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    m = obj.split()[3].point(lambda a: alpha if a > 0 else 0)
    sh.paste((0, 0, 0, 255), (x, y + dy), m)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(obj, (x, y))


def text_center(d, y, lines, f, fill, spacing=1.18, w=W):
    for line in lines:
        tw = d.textlength(line, font=f)
        d.text(((w - tw) / 2, y), line, font=f, fill=fill)
        y += int(f.size * spacing)
    return y


def wrap(d, text, f, maxw=W * 0.84):
    words, lines, cur = text.split(), [], ''
    for wd in words:
        t = (cur + ' ' + wd).strip()
        if d.textlength(t, font=f) <= maxw:
            cur = t
        else:
            lines.append(cur)
            cur = wd
    lines.append(cur)
    return lines


def vgrad(w, h, top, bottom):
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))


def hgrad(w, h, stops):
    g = Image.new('RGB', (w, 1))
    for x in range(w):
        t = x / (w - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                g.putpixel((x, 0), tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)))
                break
    return g.resize((w, h))


def stars(img, n, seed, area=None, alpha=180):
    import random
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img, 'RGBA')
    x0, y0, x1, y1 = area or (0, 0, img.size[0], img.size[1])
    for _ in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        r = rnd.choice([1.5, 2, 2.5, 3.5])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rnd.randint(60, alpha)))


def octagrams(img, step, color):
    d = ImageDraw.Draw(img, 'RGBA')
    w, h = img.size
    r = step * 0.42
    for row in range(-1, h // step + 2):
        for col in range(-1, w // step + 2):
            cx = col * step + (step / 2 if row % 2 else 0)
            cy = row * step
            for ang in (0, 45):
                a = math.radians(ang)
                pts = [(cx + r * math.cos(a + k * math.pi / 2 + math.pi / 4), cy + r * math.sin(a + k * math.pi / 2 + math.pi / 4)) for k in range(4)]
                d.polygon(pts, outline=color)


def save(var, i, img, name):
    os.makedirs(f'{OUT}/{var}', exist_ok=True)
    img.convert('RGB').save(f'{OUT}/{var}/{i:02d}-{name}.png', optimize=True)


# ---------------------------------------------------------------- тексты
T = {
    'beauty': ('Небо меняется\nвместе с намазом', 'Рассвет, день, закат и ночь — как за окном'),
    'beauty2': ('На закате —\nзакат', 'Вечерние зикры зовут, когда открывается их время'),
    'beauty3': ('Ночью — ночь', 'Отсчёт до следующей молитвы всегда перед глазами'),
    'deeds': ('Дела дня\nпривязаны к намазу', 'Зикры, аль-Кахф и ваши напоминания — вовремя'),
    'zikr': ('Зикры уже\nвнутри', 'Арабский текст, транскрипция и источник'),
    'calendar': ('Тетрадь\nпостоянства', 'Видно каждый день без пропусков'),
    'themes': ('Мекка, Медина\nили Астана', 'Выберите вид главного экрана'),
}

ORDER5 = [('beauty', 'home-mecca-sunset'), ('deeds', 'today-day'), ('zikr', 'reader-paper'),
          ('calendar', 'calendar-day'), ('themes', 'home-medina-night')]


# ------------------------------------------------ A: «Небо-триптих»
def variant_a():
    """Первые три карточки — одно небо: день → закат → ночь, фон перетекает."""
    n = 3
    sky = hgrad(W * n, H, [(0, (92, 150, 214)), (0.33, (150, 170, 200)), (0.5, (236, 150, 92)),
                            (0.66, (120, 70, 96)), (0.85, (34, 36, 70)), (1, (18, 20, 44))]).convert('RGBA')
    stars(sky, 260, 3, (W * 1.8, 0, W * n, H * 0.6))
    big = font(INTER, W * 0.088, 'Bold')
    small = font(INTER, W * 0.040, 'Medium')
    seq = [('beauty', 'home-mecca-day'), ('beauty2', 'home-mecca-sunset'), ('beauty3', 'home-mecca-night')]
    for i, (key, s) in enumerate(seq):
        card = sky.crop((i * W, 0, (i + 1) * W, H)).copy()
        dr = ImageDraw.Draw(card)
        title, sub = T[key]
        y = text_center(dr, int(H * 0.06), title.split('\n'), big, (255, 255, 255))
        text_center(dr, y + 20, wrap(dr, sub, small), small, (255, 245, 225))
        p = phone(shot(s), int(W * 0.80))
        drop(card, p, (W - p.size[0]) // 2, int(H * 0.27))
        save('A-nebo', i + 1, card, key)
    # дальше — ночная тема приложения
    rest = [('deeds', 'today-night'), ('zikr', 'reader-dark'), ('calendar', 'calendar-day'), ('themes', 'home-medina-night')]
    for j, (key, s) in enumerate(rest):
        card = vgrad(W, H, (22, 26, 52), (12, 14, 30)).convert('RGBA')
        stars(card, 90, 10 + j, (0, 0, W, H * 0.25))
        dr = ImageDraw.Draw(card)
        title, sub = T[key]
        y = text_center(dr, int(H * 0.06), title.split('\n'), big, (255, 255, 255))
        text_center(dr, y + 20, wrap(dr, sub, small), small, (232, 205, 140))
        p = phone(shot(s), int(W * 0.80))
        drop(card, p, (W - p.size[0]) // 2, int(H * 0.27))
        save('A-nebo', j + 4, card, key)


# ------------------------------------------------ B: «Во весь экран»
def variant_b():
    """Скриншот на всю карточку без рамки; заголовок поверх затемнения сверху."""
    big = font(INTER, W * 0.092, 'ExtraBold')
    small = font(INTER, W * 0.041, 'Medium')
    seq = [('beauty', 'home-mecca-night'), ('deeds', 'today-night'), ('zikr', 'reader-dark'),
           ('calendar', 'calendar-day'), ('themes', 'home-astana-night')]
    for i, (key, s) in enumerate(seq):
        img = shot(s).resize((W, int(2796 * W / 1290)), Image.LANCZOS)
        card = Image.new('RGBA', (W, H), (10, 12, 26, 255))
        # скриншот сдвинут вниз, чтобы освободить место под заголовок
        top = int(H * 0.035) if s.startswith('home') else int(H * 0.21)
        card.alpha_composite(img.convert('RGBA'), (0, top))
        fade = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        fd = ImageDraw.Draw(fade)
        solid = int(H * 0.06) if s.startswith('home') else top
        for y in range(int(H * 0.36)):
            a = 255 if y < solid else int(255 * max(0, 1 - (y - solid) / (H * 0.18)))
            fd.line([(0, y), (W, y)], fill=(12, 14, 30, a))
        card = Image.alpha_composite(card, fade)
        dr = ImageDraw.Draw(card)
        title, sub = T[key]
        # золотая полоска-акцент
        dr.rounded_rectangle([W / 2 - 60, H * 0.045, W / 2 + 60, H * 0.045 + 10], 5, fill=(214, 172, 86))
        y = text_center(dr, int(H * 0.065), title.split('\n'), big, (255, 255, 255))
        text_center(dr, y + 16, wrap(dr, sub, small), small, (230, 200, 135))
        save('B-ves-ekran', i + 1, card, key)


# ------------------------------------------------ C: «Бумага и золото»
def variant_c():
    """Светлый фон-бумага, орнамент, серифный заголовок, наклонённый телефон.
    Телефоны 1→2 и 2→3 заходят на соседнюю карточку — карточки сцеплены."""
    n = 5
    paper = vgrad(W * n, H, (250, 246, 236), (238, 230, 212)).convert('RGBA')
    octagrams(paper, int(H * 0.11), (150, 120, 60, 22))
    big = font(SERIF, W * 0.086, 'SemiBold')
    small = font(INTER, W * 0.039, 'Medium')
    seq = [('beauty', 'home-mecca-sunset', -6), ('deeds', 'today-day', 5), ('zikr', 'reader-paper', -4),
           ('calendar', 'calendar-day', 4), ('themes', 'home-medina-night', -5)]
    phones = []
    for i, (key, s, ang) in enumerate(seq):
        p = phone(shot(s), int(W * 0.78), frame=(30, 26, 22)).rotate(ang, resample=Image.BICUBIC, expand=True)
        cx = i * W + W // 2 + (int(W * 0.17) if i == 0 else (-int(W * 0.05) if i == 1 else 0))
        phones.append((p, cx - p.size[0] // 2, int(H * 0.29)))
    # большая «зацепка»: на первой карточке телефон уезжает вправо, на вторую
    for p, x, y in phones:
        drop(paper, p, x, y, blur=46, alpha=90, dy=40)
    dr = ImageDraw.Draw(paper)
    for i, (key, s, ang) in enumerate(seq):
        title, sub = T[key]
        lines = title.split('\n')
        x0 = i * W
        y = int(H * 0.065)
        for line in lines:
            tw = dr.textlength(line, font=big)
            dr.text((x0 + (W - tw) / 2, y), line, font=big, fill=(36, 30, 22))
            y += int(big.size * 1.16)
        y += 18
        for line in wrap(dr, sub, small):
            tw = dr.textlength(line, font=small)
            dr.text((x0 + (W - tw) / 2, y), line, font=small, fill=(140, 104, 40))
            y += int(small.size * 1.2)
    for i in range(n):
        save('C-bumaga', i + 1, paper.crop((i * W, 0, (i + 1) * W, H)), seq[i][0])


# ------------------------------------------------ D: «Веер времён суток»
def variant_d():
    """Тёмно-синий фон; на первой карточке веер из трёх телефонов (рассвет,
    день, ночь) — сразу видно, что экран живёт по времени суток."""
    big = font(INTER, W * 0.086, 'Bold')
    small = font(INTER, W * 0.040, 'Medium')
    gold = (226, 182, 92)

    def base(seed):
        c = vgrad(W, H, (16, 30, 54), (8, 14, 28)).convert('RGBA')
        glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([W * 0.1, H * 0.35, W * 0.9, H * 0.85], fill=(214, 160, 70, 60))
        c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(160)))
        stars(c, 70, seed, (0, 0, W, H * 0.3), 140)
        return c

    def head(card, key, accent_word):
        dr = ImageDraw.Draw(card)
        title, sub = T[key]
        y = int(H * 0.06)
        for line in title.split('\n'):
            tw = dr.textlength(line, font=big)
            x = (W - tw) / 2
            if accent_word and accent_word in line:
                pre, post = line.split(accent_word, 1)
                dr.text((x, y), pre, font=big, fill=(255, 255, 255))
                x += dr.textlength(pre, font=big)
                dr.text((x, y), accent_word, font=big, fill=gold)
                x += dr.textlength(accent_word, font=big)
                dr.text((x, y), post, font=big, fill=(255, 255, 255))
            else:
                dr.text((x, y), line, font=big, fill=(255, 255, 255))
            y += int(big.size * 1.18)
        text_center(dr, y + 18, wrap(dr, sub, small), small, (200, 210, 225))

    # 1 — веер
    card = base(1)
    head(card, 'beauty', 'намазом')
    for s, ang, dx in (('home-mecca-sunrise', 9, -0.26), ('home-mecca-night', -9, 0.26), ('home-mecca-day', 0, 0)):
        p = phone(shot(s), int(W * 0.60)).rotate(ang, resample=Image.BICUBIC, expand=True)
        drop(card, p, int(W / 2 + dx * W - p.size[0] / 2), int(H * 0.31), blur=40, alpha=150)
    save('D-veer', 1, card, 'beauty')
    rest = [('deeds', 'today-day', 'намазу'), ('zikr', 'reader-paper', 'внутри'),
            ('calendar', 'calendar-day', 'постоянства'), ('themes', 'home-astana-night', 'Астана')]
    for j, (key, s, acc) in enumerate(rest):
        card = base(j + 5)
        head(card, key, acc)
        p = phone(shot(s), int(W * 0.80))
        drop(card, p, (W - p.size[0]) // 2, int(H * 0.27), alpha=150)
        save('D-veer', j + 2, card, key)


def sheet(var):
    fs = sorted(os.listdir(f'{OUT}/{var}'))
    ims = [Image.open(f'{OUT}/{var}/{f}').convert('RGB').resize((330, 717)) for f in fs if f.endswith('.png')]
    s = Image.new('RGB', (330 * len(ims) + 8 * (len(ims) - 1), 717), (255, 255, 255))
    for i, im in enumerate(ims):
        s.paste(im, (i * 338, 0))
    os.makedirs(f'{OUT}/_preview', exist_ok=True)
    s.save(f'{OUT}/_preview/{var}.png')


if __name__ == '__main__':
    variant_a(); variant_b(); variant_c(); variant_d()
    for v in ('A-nebo', 'B-ves-ekran', 'C-bumaga', 'D-veer'):
        sheet(v)
    print('ok')
