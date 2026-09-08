import struct
import zlib
import os

BG = (30, 41, 59)      # slate-800: dark, quiet, "lowkey"
FG = (248, 250, 252)    # near-white glasses glyph
SUPERSAMPLE = 8


def rounded_rect_mask(x, y, size, radius):
    half = size / 2.0
    inner = half - radius
    qx = abs(x - half) - inner
    qy = abs(y - half) - inner
    dx = max(qx, 0.0)
    dy = max(qy, 0.0)
    return (dx * dx + dy * dy) <= radius * radius


def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    hx = (x1 - x0) / 2.0
    hy = (y1 - y0) / 2.0
    qx = abs(x - cx) - (hx - r)
    qy = abs(y - cy) - (hy - r)
    dx = max(qx, 0.0)
    dy = max(qy, 0.0)
    return (dx * dx + dy * dy) <= r * r


def in_rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def seg_dist(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    apx, apy = px - ax, py - ay
    ab2 = abx * abx + aby * aby
    t = max(0.0, min(1.0, (apx * abx + apy * aby) / ab2))
    cx, cy = ax + abx * t, ay + aby * t
    dx, dy = px - cx, py - cy
    return (dx * dx + dy * dy) ** 0.5


def glasses_mask(x, y, S):
    # Flat sunglasses: two rounded-rect lenses joined by a bridge -
    # the "incognito/lowkey" glyph. No temple-tip strokes: they're
    # thin enough to disappear entirely once downsampled to a 16px
    # toolbar icon, so bold lenses + a clearly gapped bridge carry
    # the whole shape instead.
    lens_w = 0.27 * S
    lens_h = 0.22 * S
    lens_r = 0.05 * S
    gap = 0.16 * S
    cy = 0.50 * S
    cx = 0.50 * S

    l_x1 = cx - gap / 2
    l_x0 = l_x1 - lens_w
    r_x0 = cx + gap / 2
    r_x1 = r_x0 + lens_w
    y0 = cy - lens_h / 2
    y1 = cy + lens_h / 2

    if in_rounded_rect(x, y, l_x0, y0, l_x1, y1, lens_r):
        return True
    if in_rounded_rect(x, y, r_x0, y0, r_x1, y1, lens_r):
        return True

    # The bridge is a briefcase handle - a rounded arch over the two
    # lenses - instead of a straight bar or a generic checkmark. A
    # checkmark only means "done/submitted"; this arch reads as a
    # case/bag handle, which is specifically "job", so the whole glyph
    # becomes "glasses resting on a briefcase" - Lowkey from the
    # lenses, Apply (as in job application, not a generic checkmark)
    # from the handle. A real arc, not two straight segments meeting
    # at a point - a sharp V there read as eyebrows/a roof, not a
    # handle. A plain semicircle, centered at the attach height with
    # radius = half_gap, so its base exactly spans the two attach
    # points (l_x1, r_x0) with no bulge past them - an earlier attempt
    # that solved for a circle through an independently-chosen apex
    # put the attach points past the circle's equator, so the clipped
    # arc bulged wider than the lenses before narrowing back in,
    # looking like a floating ring instead of a dome resting on them.
    stroke = 0.045 * S
    half_gap = gap / 2
    attach_y = y0 + lens_h * 0.15
    arch_cy = attach_y
    arch_r = half_gap
    d = ((x - cx) ** 2 + (y - arch_cy) ** 2) ** 0.5
    if abs(d - arch_r) <= stroke / 2 and y <= attach_y:
        return True

    return False


def render(size):
    ss = size * SUPERSAMPLE
    radius = 0.22 * ss

    big = bytearray(ss * ss * 4)
    for j in range(ss):
        for i in range(ss):
            idx = (j * ss + i) * 4
            x, y = i + 0.5, j + 0.5
            if not rounded_rect_mask(x, y, ss, radius):
                continue
            if glasses_mask(x, y, ss):
                r, g, b = FG
            else:
                r, g, b = BG
            big[idx : idx + 4] = bytes((r, g, b, 255))

    out = bytearray(size * size * 4)
    for j in range(size):
        for i in range(size):
            rs = gs = bs = a_s = 0
            for jj in range(SUPERSAMPLE):
                for ii in range(SUPERSAMPLE):
                    sx = i * SUPERSAMPLE + ii
                    sy = j * SUPERSAMPLE + jj
                    sidx = (sy * ss + sx) * 4
                    rs += big[sidx]
                    gs += big[sidx + 1]
                    bs += big[sidx + 2]
                    a_s += big[sidx + 3]
            n = SUPERSAMPLE * SUPERSAMPLE
            oidx = (j * size + i) * 4
            out[oidx : oidx + 4] = bytes((rs // n, gs // n, bs // n, a_s // n))
    return out


def write_png(path, size, rgba):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = size * 4
    for j in range(size):
        raw.append(0)
        raw.extend(rgba[j * stride : (j + 1) * stride])

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


out_dir = os.path.dirname(os.path.abspath(__file__))
for size in (16, 32, 48, 96, 128):
    rgba = render(size)
    write_png(os.path.join(out_dir, f"icon-{size}.png"), size, rgba)
    print(f"wrote icon-{size}.png")
