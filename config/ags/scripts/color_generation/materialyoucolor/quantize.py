"""Pure-Python Material Color Utilities quantizer module.

Converted from the uploaded C++ quantize/lab/utils snippets into one Python
module named ``quantize``.  Public API mirrors the original names:

    QuantizeWu(pixels, max_colors) -> list[int]
    QuantizeWsmeans(input_pixels, starting_clusters, max_colors) -> QuantizerResult
    QuantizeCelebi(pixels, max_colors) -> dict[int, int]
    ImageQuantizeCelebi(image_or_path, max_colors) -> dict[int, int]

Pixels are 32-bit ARGB integers: 0xAARRGGBB.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from enum import IntEnum
from math import pow, sqrt
from random import Random
from typing import Iterable, Mapping, Sequence, Any

Argb = int
K_PI = 3.141592653589793
K_WHITE_POINT_D65 = (95.047, 100.0, 108.883)


def RedFromInt(argb: Argb) -> int:
    return (argb & 0x00FF0000) >> 16


def GreenFromInt(argb: Argb) -> int:
    return (argb & 0x0000FF00) >> 8


def BlueFromInt(argb: Argb) -> int:
    return argb & 0x000000FF


def AlphaFromInt(argb: Argb) -> int:
    return (argb >> 24) & 0xFF


def ArgbFromRgb(red: int, green: int, blue: int) -> Argb:
    return 0xFF000000 | ((red & 0xFF) << 16) | ((green & 0xFF) << 8) | (blue & 0xFF)


def IsOpaque(argb: Argb) -> bool:
    return AlphaFromInt(argb) >= 255


def Linearized(rgb_component: int) -> float:
    normalized = rgb_component / 255.0
    if normalized <= 0.040449936:
        return normalized / 12.92 * 100.0
    return pow((normalized + 0.055) / 1.055, 2.4) * 100.0


def Delinearized(rgb_component: float) -> int:
    normalized = rgb_component / 100.0
    if normalized <= 0.0031308:
        delinearized = normalized * 12.92
    else:
        delinearized = 1.055 * pow(normalized, 1.0 / 2.4) - 0.055
    return max(0, min(255, int(round(delinearized * 255.0))))


def YFromLstar(lstar: float) -> float:
    ke = 8.0
    if lstar > ke:
        return pow((lstar + 16.0) / 116.0, 3.0) * 100.0
    return lstar / (24389.0 / 27.0) * 100.0


def LstarFromY(y: float) -> float:
    y = y / 100.0
    e = 216.0 / 24389.0
    if y <= e:
        return (24389.0 / 27.0) * y
    return 116.0 * pow(y, 1.0 / 3.0) - 16.0


def LstarFromArgb(argb: Argb) -> float:
    y = (0.2126 * Linearized(RedFromInt(argb)) +
         0.7152 * Linearized(GreenFromInt(argb)) +
         0.0722 * Linearized(BlueFromInt(argb)))
    return LstarFromY(y)


def IntFromLstar(lstar: float) -> Argb:
    y = YFromLstar(lstar)
    component = Delinearized(y)
    return ArgbFromRgb(component, component, component)


def HexFromArgb(argb: Argb) -> str:
    return f"#{RedFromInt(argb):02x}{GreenFromInt(argb):02x}{BlueFromInt(argb):02x}"


def SanitizeDegreesInt(degrees: int) -> int:
    degrees %= 360
    return degrees + 360 if degrees < 0 else degrees


def SanitizeDegreesDouble(degrees: float) -> float:
    degrees %= 360.0
    return degrees + 360.0 if degrees < 0.0 else degrees


def DiffDegrees(a: float, b: float) -> float:
    return 180.0 - abs(abs(a - b) - 180.0)


def RotationDirection(frm: float, to: float) -> float:
    increasing_difference = SanitizeDegreesDouble(to - frm)
    return 1.0 if increasing_difference <= 180.0 else -1.0


def Signum(num: float) -> int:
    return 1 if num > 0 else (-1 if num < 0 else 0)


def Lerp(start: float, stop: float, amount: float) -> float:
    return (1.0 - amount) * start + amount * stop


@dataclass(frozen=True)
class Vec3:
    a: float = 0.0
    b: float = 0.0
    c: float = 0.0

    def __getitem__(self, index: int) -> float:
        return (self.a, self.b, self.c)[index]


def MatrixMultiply(input: Vec3, matrix: Sequence[Sequence[float]]) -> Vec3:
    return Vec3(
        input.a * matrix[0][0] + input.b * matrix[0][1] + input.c * matrix[0][2],
        input.a * matrix[1][0] + input.b * matrix[1][1] + input.c * matrix[1][2],
        input.a * matrix[2][0] + input.b * matrix[2][1] + input.c * matrix[2][2],
    )


def ArgbFromLinrgb(linrgb: Vec3) -> Argb:
    return ArgbFromRgb(Delinearized(linrgb.a), Delinearized(linrgb.b), Delinearized(linrgb.c))


@dataclass(frozen=True)
class Lab:
    l: float = 0.0
    a: float = 0.0
    b: float = 0.0

    def DeltaE(self, other: "Lab") -> float:
        dl = self.l - other.l
        da = self.a - other.a
        db = self.b - other.b
        return dl * dl + da * da + db * db


def LabFromInt(argb: Argb) -> Lab:
    red_l = Linearized(RedFromInt(argb))
    green_l = Linearized(GreenFromInt(argb))
    blue_l = Linearized(BlueFromInt(argb))

    x = 0.41233895 * red_l + 0.35762064 * green_l + 0.18051042 * blue_l
    y = 0.2126 * red_l + 0.7152 * green_l + 0.0722 * blue_l
    z = 0.01932141 * red_l + 0.11916382 * green_l + 0.95034478 * blue_l

    e = 216.0 / 24389.0
    kappa = 24389.0 / 27.0

    def f(v: float) -> float:
        return pow(v, 1.0 / 3.0) if v > e else (kappa * v + 16.0) / 116.0

    fy = f(y / K_WHITE_POINT_D65[1])
    fx = f(x / K_WHITE_POINT_D65[0])
    fz = f(z / K_WHITE_POINT_D65[2])

    return Lab(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def IntFromLab(lab: Lab) -> Argb:
    e = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    ke = 8.0

    fy = (lab.l + 16.0) / 116.0
    fx = lab.a / 500.0 + fy
    fz = fy - lab.b / 200.0

    fx3 = fx * fx * fx
    fz3 = fz * fz * fz
    x_normalized = fx3 if fx3 > e else (116.0 * fx - 16.0) / kappa
    y_normalized = fy * fy * fy if lab.l > ke else lab.l / kappa
    z_normalized = fz3 if fz3 > e else (116.0 * fz - 16.0) / kappa

    x = x_normalized * K_WHITE_POINT_D65[0]
    y = y_normalized * K_WHITE_POINT_D65[1]
    z = z_normalized * K_WHITE_POINT_D65[2]

    r_l = 3.2406 * x - 1.5372 * y - 0.4986 * z
    g_l = -0.9689 * x + 1.8758 * y + 0.0415 * z
    b_l = 0.0557 * x - 0.2040 * y + 1.0570 * z
    return ArgbFromRgb(Delinearized(r_l), Delinearized(g_l), Delinearized(b_l))


@dataclass
class QuantizerResult:
    color_to_count: dict[Argb, int]
    input_pixel_to_cluster_pixel: dict[Argb, Argb]


# ---------------- Wu quantizer ----------------

@dataclass
class _Box:
    r0: int = 0
    r1: int = 0
    g0: int = 0
    g1: int = 0
    b0: int = 0
    b1: int = 0
    vol: int = 0


class _Direction(IntEnum):
    RED = 0
    GREEN = 1
    BLUE = 2


_K_INDEX_BITS = 5
_K_INDEX_COUNT = (1 << _K_INDEX_BITS) + 1
_K_TOTAL_SIZE = _K_INDEX_COUNT * _K_INDEX_COUNT * _K_INDEX_COUNT
_K_MAX_COLORS = 256


def _get_index(r: int, g: int, b: int) -> int:
    return (r << (_K_INDEX_BITS * 2)) + (r << (_K_INDEX_BITS + 1)) + (g << _K_INDEX_BITS) + r + g + b


def _construct_histogram(pixels: Sequence[Argb], weights: list[int], mr: list[int], mg: list[int], mb: list[int], moments: list[float]) -> None:
    bits_to_remove = 8 - _K_INDEX_BITS
    for pixel in pixels:
        red = RedFromInt(pixel)
        green = GreenFromInt(pixel)
        blue = BlueFromInt(pixel)
        index = _get_index((red >> bits_to_remove) + 1, (green >> bits_to_remove) + 1, (blue >> bits_to_remove) + 1)
        weights[index] += 1
        mr[index] += red
        mg[index] += green
        mb[index] += blue
        moments[index] += red * red + green * green + blue * blue


def _compute_moments(weights: list[int], mr: list[int], mg: list[int], mb: list[int], moments: list[float]) -> None:
    for r in range(1, _K_INDEX_COUNT):
        area = [0] * _K_INDEX_COUNT
        area_r = [0] * _K_INDEX_COUNT
        area_g = [0] * _K_INDEX_COUNT
        area_b = [0] * _K_INDEX_COUNT
        area_2 = [0.0] * _K_INDEX_COUNT
        for g in range(1, _K_INDEX_COUNT):
            line = line_r = line_g = line_b = 0
            line_2 = 0.0
            for b in range(1, _K_INDEX_COUNT):
                index = _get_index(r, g, b)
                line += weights[index]
                line_r += mr[index]
                line_g += mg[index]
                line_b += mb[index]
                line_2 += moments[index]
                area[b] += line
                area_r[b] += line_r
                area_g[b] += line_g
                area_b[b] += line_b
                area_2[b] += line_2
                previous_index = _get_index(r - 1, g, b)
                weights[index] = weights[previous_index] + area[b]
                mr[index] = mr[previous_index] + area_r[b]
                mg[index] = mg[previous_index] + area_g[b]
                mb[index] = mb[previous_index] + area_b[b]
                moments[index] = moments[previous_index] + area_2[b]


def _top(cube: _Box, direction: _Direction, position: int, moment: Sequence[float | int]) -> float:
    if direction == _Direction.RED:
        return moment[_get_index(position, cube.g1, cube.b1)] - moment[_get_index(position, cube.g1, cube.b0)] - moment[_get_index(position, cube.g0, cube.b1)] + moment[_get_index(position, cube.g0, cube.b0)]
    if direction == _Direction.GREEN:
        return moment[_get_index(cube.r1, position, cube.b1)] - moment[_get_index(cube.r1, position, cube.b0)] - moment[_get_index(cube.r0, position, cube.b1)] + moment[_get_index(cube.r0, position, cube.b0)]
    return moment[_get_index(cube.r1, cube.g1, position)] - moment[_get_index(cube.r1, cube.g0, position)] - moment[_get_index(cube.r0, cube.g1, position)] + moment[_get_index(cube.r0, cube.g0, position)]


def _bottom(cube: _Box, direction: _Direction, moment: Sequence[float | int]) -> float:
    if direction == _Direction.RED:
        return -moment[_get_index(cube.r0, cube.g1, cube.b1)] + moment[_get_index(cube.r0, cube.g1, cube.b0)] + moment[_get_index(cube.r0, cube.g0, cube.b1)] - moment[_get_index(cube.r0, cube.g0, cube.b0)]
    if direction == _Direction.GREEN:
        return -moment[_get_index(cube.r1, cube.g0, cube.b1)] + moment[_get_index(cube.r1, cube.g0, cube.b0)] + moment[_get_index(cube.r0, cube.g0, cube.b1)] - moment[_get_index(cube.r0, cube.g0, cube.b0)]
    return -moment[_get_index(cube.r1, cube.g1, cube.b0)] + moment[_get_index(cube.r1, cube.g0, cube.b0)] + moment[_get_index(cube.r0, cube.g1, cube.b0)] - moment[_get_index(cube.r0, cube.g0, cube.b0)]


def _vol(cube: _Box, moment: Sequence[float | int]) -> float:
    return (
        moment[_get_index(cube.r1, cube.g1, cube.b1)]
        - moment[_get_index(cube.r1, cube.g1, cube.b0)]
        - moment[_get_index(cube.r1, cube.g0, cube.b1)]
        + moment[_get_index(cube.r1, cube.g0, cube.b0)]
        - moment[_get_index(cube.r0, cube.g1, cube.b1)]
        + moment[_get_index(cube.r0, cube.g1, cube.b0)]
        + moment[_get_index(cube.r0, cube.g0, cube.b1)]
        - moment[_get_index(cube.r0, cube.g0, cube.b0)]
    )


def _variance(cube: _Box, weights: list[int], mr: list[int], mg: list[int], mb: list[int], moments: list[float]) -> float:
    dr = _vol(cube, mr)
    dg = _vol(cube, mg)
    db = _vol(cube, mb)
    xx = _vol(cube, moments)
    volume = _vol(cube, weights)
    if volume == 0:
        return 0.0
    return xx - (dr * dr + dg * dg + db * db) / volume


def _maximize(cube: _Box, direction: _Direction, first: int, last: int, whole_w: float, whole_r: float, whole_g: float, whole_b: float, weights: list[int], mr: list[int], mg: list[int], mb: list[int]) -> tuple[float, int]:
    bottom_r = _bottom(cube, direction, mr)
    bottom_g = _bottom(cube, direction, mg)
    bottom_b = _bottom(cube, direction, mb)
    bottom_w = _bottom(cube, direction, weights)
    max_score = 0.0
    cut = -1
    for i in range(first, last):
        half_r = bottom_r + _top(cube, direction, i, mr)
        half_g = bottom_g + _top(cube, direction, i, mg)
        half_b = bottom_b + _top(cube, direction, i, mb)
        half_w = bottom_w + _top(cube, direction, i, weights)
        if half_w == 0:
            continue
        temp = (half_r * half_r + half_g * half_g + half_b * half_b) / half_w
        half_r = whole_r - half_r
        half_g = whole_g - half_g
        half_b = whole_b - half_b
        half_w = whole_w - half_w
        if half_w == 0:
            continue
        temp += (half_r * half_r + half_g * half_g + half_b * half_b) / half_w
        if temp > max_score:
            max_score = temp
            cut = i
    return max_score, cut


def _cut(box1: _Box, box2: _Box, weights: list[int], mr: list[int], mg: list[int], mb: list[int]) -> bool:
    whole_r = _vol(box1, mr)
    whole_g = _vol(box1, mg)
    whole_b = _vol(box1, mb)
    whole_w = _vol(box1, weights)
    max_r, cut_r = _maximize(box1, _Direction.RED, box1.r0 + 1, box1.r1, whole_w, whole_r, whole_g, whole_b, weights, mr, mg, mb)
    max_g, cut_g = _maximize(box1, _Direction.GREEN, box1.g0 + 1, box1.g1, whole_w, whole_r, whole_g, whole_b, weights, mr, mg, mb)
    max_b, cut_b = _maximize(box1, _Direction.BLUE, box1.b0 + 1, box1.b1, whole_w, whole_r, whole_g, whole_b, weights, mr, mg, mb)

    if max_r >= max_g and max_r >= max_b:
        direction = _Direction.RED
        if cut_r < 0:
            return False
    elif max_g >= max_r and max_g >= max_b:
        direction = _Direction.GREEN
    else:
        direction = _Direction.BLUE

    box2.r1, box2.g1, box2.b1 = box1.r1, box1.g1, box1.b1
    if direction == _Direction.RED:
        box2.r0 = box1.r1 = cut_r
        box2.g0, box2.b0 = box1.g0, box1.b0
    elif direction == _Direction.GREEN:
        box2.r0 = box1.r0
        box2.g0 = box1.g1 = cut_g
        box2.b0 = box1.b0
    else:
        box2.r0, box2.g0 = box1.r0, box1.g0
        box2.b0 = box1.b1 = cut_b

    box1.vol = (box1.r1 - box1.r0) * (box1.g1 - box1.g0) * (box1.b1 - box1.b0)
    box2.vol = (box2.r1 - box2.r0) * (box2.g1 - box2.g0) * (box2.b1 - box2.b0)
    return True


def QuantizeWu(pixels: Sequence[Argb], max_colors: int) -> list[Argb]:
    if max_colors <= 0 or max_colors > 256 or not pixels:
        return []
    weights = [0] * _K_TOTAL_SIZE
    mr = [0] * _K_TOTAL_SIZE
    mg = [0] * _K_TOTAL_SIZE
    mb = [0] * _K_TOTAL_SIZE
    moments = [0.0] * _K_TOTAL_SIZE
    _construct_histogram(pixels, weights, mr, mg, mb, moments)
    _compute_moments(weights, mr, mg, mb, moments)

    cubes = [_Box() for _ in range(_K_MAX_COLORS)]
    cubes[0].r1 = cubes[0].g1 = cubes[0].b1 = _K_INDEX_COUNT - 1
    volume_variance = [0.0] * _K_MAX_COLORS
    next_index = 0
    actual_max = int(max_colors)
    for i in range(1, actual_max):
        if _cut(cubes[next_index], cubes[i], weights, mr, mg, mb):
            volume_variance[next_index] = _variance(cubes[next_index], weights, mr, mg, mb, moments) if cubes[next_index].vol > 1 else 0.0
            volume_variance[i] = _variance(cubes[i], weights, mr, mg, mb, moments) if cubes[i].vol > 1 else 0.0
        else:
            volume_variance[next_index] = 0.0
            continue
        next_index = max(range(i + 1), key=lambda j: volume_variance[j])
        if volume_variance[next_index] <= 0.0:
            actual_max = i + 1
            break

    out: list[Argb] = []
    for cube in cubes[:actual_max]:
        weight = _vol(cube, weights)
        if weight > 0:
            out.append(ArgbFromRgb(int(_vol(cube, mr) / weight), int(_vol(cube, mg) / weight), int(_vol(cube, mb) / weight)))
    return out


# ---------------- WSMeans quantizer ----------------

_K_MAX_ITERATIONS = 100
_K_MIN_DELTA_E = 3.0


def QuantizeWsmeans(input_pixels: Sequence[Argb], starting_clusters: Sequence[Argb] | None = None, max_colors: int = 128) -> dict[int, int]:
    if max_colors == 0 or not input_pixels:
        return {}
    max_colors = min(int(max_colors), 256)
    starting_clusters = list(starting_clusters or [])

    pixel_to_count: dict[Argb, int] = {}
    pixels: list[Argb] = []
    points: list[Lab] = []
    for pixel in input_pixels:
        if pixel in pixel_to_count:
            pixel_to_count[pixel] += 1
        else:
            pixels.append(pixel)
            points.append(LabFromInt(pixel))
            pixel_to_count[pixel] = 1

    cluster_count = min(max_colors, len(points))
    if starting_clusters:
        cluster_count = min(cluster_count, len(starting_clusters))
    if cluster_count <= 0:
        return {}

    clusters = [LabFromInt(argb) for argb in starting_clusters[:cluster_count]]
    rng = Random(42688)
    if not starting_clusters and cluster_count - len(clusters) > 0:
        for _ in range(cluster_count - len(clusters)):
            clusters.append(Lab(rng.random() * 100.0, rng.random() * 200.0 - 100.0, rng.random() * 200.0 - 100.0))

    rng = Random(42688)
    cluster_indices = [rng.randrange(cluster_count) for _ in points]
    pixel_count_sums = [0] * 256
    all_cluster_argbs = [0] * cluster_count

    for iteration in range(_K_MAX_ITERATIONS):
        distance_to_index_matrix: list[list[tuple[float, int]]] = [[(0.0, j) for j in range(cluster_count)] for _ in range(cluster_count)]
        index_matrix = [[0] * cluster_count for _ in range(cluster_count)]
        for i in range(cluster_count):
            distance_to_index_matrix[i][i] = (0.0, i)
            for j in range(i + 1, cluster_count):
                distance = clusters[i].DeltaE(clusters[j])
                distance_to_index_matrix[j][i] = (distance, i)
                distance_to_index_matrix[i][j] = (distance, j)
            row = sorted(distance_to_index_matrix[i])
            for j in range(cluster_count):
                index_matrix[i][j] = row[j][1]

        color_moved = False
        for i, point in enumerate(points):
            previous_cluster_index = cluster_indices[i]
            previous_distance = point.DeltaE(clusters[previous_cluster_index])
            minimum_distance = previous_distance
            new_cluster_index = -1
            for j in range(cluster_count):
                if distance_to_index_matrix[previous_cluster_index][j][0] >= 4.0 * previous_distance:
                    continue
                distance = point.DeltaE(clusters[j])
                if distance < minimum_distance:
                    minimum_distance = distance
                    new_cluster_index = j
            if new_cluster_index != -1:
                distance_change = abs(sqrt(minimum_distance) - sqrt(previous_distance))
                if distance_change > _K_MIN_DELTA_E:
                    color_moved = True
                    cluster_indices[i] = new_cluster_index

        if not color_moved and iteration != 0:
            break

        component_l_sums = [0.0] * 256
        component_a_sums = [0.0] * 256
        component_b_sums = [0.0] * 256
        for i in range(cluster_count):
            pixel_count_sums[i] = 0

        for i, point in enumerate(points):
            cluster_index = cluster_indices[i]
            count = pixel_to_count[pixels[i]]
            pixel_count_sums[cluster_index] += count
            component_l_sums[cluster_index] += point.l * count
            component_a_sums[cluster_index] += point.a * count
            component_b_sums[cluster_index] += point.b * count

        for i in range(cluster_count):
            count = pixel_count_sums[i]
            if count == 0:
                clusters[i] = Lab(0.0, 0.0, 0.0)
            else:
                clusters[i] = Lab(component_l_sums[i] / count, component_a_sums[i] / count, component_b_sums[i] / count)

    swatch_counts: dict[Argb, int] = {}
    for i in range(cluster_count):
        possible = IntFromLab(clusters[i])
        all_cluster_argbs[i] = possible
        count = pixel_count_sums[i]
        if count == 0:
            continue
        swatch_counts[possible] = swatch_counts.get(possible, 0) + count

    color_to_count = dict(sorted(swatch_counts.items(), key=lambda item: item[1], reverse=True))
    # input_pixel_to_cluster_pixel = {pixels[i]: all_cluster_argbs[cluster_indices[i]] for i in range(len(points))}
    return color_to_count

def _pixel_to_argb(pixel):
    if isinstance(pixel, int):
        return pixel

    if isinstance(pixel, tuple) or isinstance(pixel, list):
        r, g, b, *rest = pixel
        a = rest[0] if rest else 255

        return (
            (int(a) & 0xFF) << 24
            | (int(r) & 0xFF) << 16
            | (int(g) & 0xFF) << 8
            | (int(b) & 0xFF)
        )

    raise TypeError(f"Unsupported pixel type: {type(pixel)!r}")
def QuantizeCelebi(pixels, max_colors):
    pixels = [_pixel_to_argb(pixel) for pixel in pixels]
    wu_clusters = QuantizeWu(pixels, max_colors)
    return QuantizeWsmeans(pixels, wu_clusters, max_colors)


def _pixels_from_pillow_image(image: Any) -> list[Argb]:
    rgba = image.convert("RGBA")
    out: list[Argb] = []
    for red, green, blue, alpha in rgba.getdata():
        if alpha < 255:
            continue
        out.append(ArgbFromRgb(red, green, blue))
    return out


def ImageQuantizeCelebi(image_or_path: Any, max_colors: int = 128) -> dict[int, int]:
    """Quantize a Pillow Image or image file path with Celebi."""
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("ImageQuantizeCelebi requires Pillow: pip install pillow") from exc

    if isinstance(image_or_path, (str, bytes)):
        with Image.open(image_or_path) as img:
            pixels = _pixels_from_pillow_image(img)
    else:
        pixels = _pixels_from_pillow_image(image_or_path)

    return QuantizeCelebi(pixels, max_colors)


# snake_case aliases, useful for normal Python style.
red_from_int = RedFromInt
green_from_int = GreenFromInt
blue_from_int = BlueFromInt
alpha_from_int = AlphaFromInt
argb_from_rgb = ArgbFromRgb
hex_from_argb = HexFromArgb
lab_from_int = LabFromInt
int_from_lab = IntFromLab
quantize_wu = QuantizeWu
quantize_wsmeans = QuantizeWsmeans
quantize_celebi = QuantizeCelebi
image_quantize_celebi = ImageQuantizeCelebi

__all__ = [
    "Argb", "Vec3", "Lab", "QuantizerResult",
    "RedFromInt", "GreenFromInt", "BlueFromInt", "AlphaFromInt", "ArgbFromRgb",
    "ArgbFromLinrgb", "IsOpaque", "SanitizeDegreesInt", "SanitizeDegreesDouble",
    "DiffDegrees", "RotationDirection", "LstarFromArgb", "HexFromArgb",
    "Linearized", "Delinearized", "YFromLstar", "LstarFromY", "IntFromLstar",
    "Signum", "Lerp", "MatrixMultiply", "LabFromInt", "IntFromLab",
    "QuantizeWu", "QuantizeWsmeans", "QuantizeCelebi", "ImageQuantizeCelebi",
    "red_from_int", "green_from_int", "blue_from_int", "alpha_from_int",
    "argb_from_rgb", "hex_from_argb", "lab_from_int", "int_from_lab",
    "quantize_wu", "quantize_wsmeans", "quantize_celebi", "image_quantize_celebi",
]
