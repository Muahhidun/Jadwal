"""Итоговые карточки сторов — вариант A «Небо» (RU/KZ, App Store и Google Play).

Первые три карточки — одно небо (день → закат → ночь), фон перетекает между ними.
Снимки экранов: app/tmp/store/raw2 (ru) и raw2kz (kz) из capture_v2_test.dart.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import compose_v2 as c
from PIL import Image, ImageDraw

ROOT = '/Users/Dom/Джадуаль'
OUT = f'{ROOT}/store/screenshots'

TEXT = {
    'ru': {
        'day': ('Небо меняется\nвместе с намазом', 'Рассвет, день, закат и ночь — как за окном'),
        'sunset': ('Магриб —\nна закате', 'Вечерние зикры зовут, когда приходит их время'),
        'night': ('Иша —\nпод звёздами', 'Время до следующей молитвы всегда перед глазами'),
        'deeds': ('Дела дня\nпривязаны к намазу', 'Зикры, аль-Кахф и ваши напоминания — вовремя'),
        'zikr': ('Зикры уже\nвнутри', 'Арабский текст, транскрипция и источник'),
        'calendar': ('Тетрадь\nпостоянства', 'Видно каждый день без пропусков'),
        'themes': ('Выберите\nсвой вид', 'Мекка, Медина и другие мечети'),
    },
    'kz': {
        'day': ('Аспан намазбен\nбірге өзгереді', 'Таң, күндіз, кеш және түн — терезедегідей'),
        'sunset': ('Ақшам —\nкүн батқанда', 'Кешкі зікір уақыты келгенде шақырады'),
        'night': ('Құптан —\nжұлдыздар астында', 'Келесі намазға дейінгі уақыт әрдайым көз алдыңызда'),
        'deeds': ('Күн істері\nнамазға байланған', 'Зікір, Кәһф сүресі және өз еске салғыштарыңыз — уақытылы'),
        'zikr': ('Зікірлер\nқосымшаның ішінде', 'Араб мәтіні, транскрипция және дереккөзі'),
        'calendar': ('Тұрақтылық\nдәптері', 'Әр күніңіз үзіліссіз көрінеді'),
        'themes': ('Өз көрінісіңізді\nтаңдаңыз', 'Мекке, Мәдина және басқа мешіттер'),
    },
}

SKY = [('day', 'home-mecca-day'), ('sunset', 'home-mecca-sunset'), ('night', 'home-mecca-night')]
REST = [('deeds', 'today-night'), ('zikr', 'reader-dark'), ('calendar', 'calendar-day'),
        ('themes', 'home-medina-night')]


def build(lang, w, h, folder):
    c.W, c.H = w, h
    raw = f'{ROOT}/app/tmp/store/raw2' + ('' if lang == 'ru' else lang)
    shot = lambda n: Image.open(f'{raw}/{n}.png').convert('RGB')
    out = f'{OUT}/{folder}/{lang}'
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith('.png'):
            os.remove(os.path.join(out, f))
    big = c.font(c.INTER, w * 0.088, 'Bold')
    small = c.font(c.INTER, w * 0.040, 'Medium')
    # телефон: по ширине, но не выше, чем остаётся под текстом
    pw = min(int(w * 0.80), int((h * 0.70) / (2796 / 1290) / 1.0))
    top = int(h * 0.27)

    def card_text(card, key, sub_color):
        dr = ImageDraw.Draw(card)
        title, sub = TEXT[lang][key]
        y = c.text_center(dr, int(h * 0.06), title.split('\n'), big, (255, 255, 255), w=w)
        lines = c.wrap(dr, sub, small, maxw=w * 0.86)
        c.text_center(dr, y + 20, lines, small, sub_color, w=w)

    n = len(SKY)
    sky = c.hgrad(w * n, h, [(0, (92, 150, 214)), (0.33, (150, 170, 200)), (0.5, (236, 150, 92)),
                              (0.66, (120, 70, 96)), (0.85, (34, 36, 70)), (1, (18, 20, 44))]).convert('RGBA')
    c.stars(sky, 260, 3, (w * 1.8, 0, w * n, h * 0.6))
    k = 1
    for i, (key, s) in enumerate(SKY):
        card = sky.crop((i * w, 0, (i + 1) * w, h)).copy()
        card_text(card, key, (255, 245, 225))
        p = c.phone(shot(s), pw)
        c.drop(card, p, (w - p.size[0]) // 2, top)
        card.convert('RGB').save(f'{out}/{k:02d}-{key}.png', optimize=True)
        k += 1
    for j, (key, s) in enumerate(REST):
        card = c.vgrad(w, h, (22, 26, 52), (12, 14, 30)).convert('RGBA')
        c.stars(card, 90, 10 + j, (0, 0, w, h * 0.25))
        card_text(card, key, (232, 205, 140))
        p = c.phone(shot(s), pw)
        c.drop(card, p, (w - p.size[0]) // 2, top)
        card.convert('RGB').save(f'{out}/{k:02d}-{key}.png', optimize=True)
        k += 1


def sheet(folder, lang):
    d = f'{OUT}/{folder}/{lang}'
    fs = sorted(f for f in os.listdir(d) if f.endswith('.png'))
    ims = [Image.open(f'{d}/{f}').convert('RGB') for f in fs]
    th = 717
    ims = [im.resize((int(im.size[0] * th / im.size[1]), th)) for im in ims]
    s = Image.new('RGB', (sum(i.size[0] + 8 for i in ims), th), 'white')
    x = 0
    for im in ims:
        s.paste(im, (x, 0))
        x += im.size[0] + 8
    os.makedirs(f'{OUT}/_preview', exist_ok=True)
    s.save(f'{OUT}/_preview/{folder}-{lang}.png')


if __name__ == '__main__':
    for lang in ('ru', 'kz'):
        build(lang, 1320, 2868, 'ios-6.9')
        build(lang, 1080, 2160, 'google-play')
        sheet('ios-6.9', lang)
        sheet('google-play', lang)
    print('ok')
