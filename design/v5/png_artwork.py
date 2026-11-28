"""Bounded PNG container/scanline validation using the Python standard library.
ImageIO/XCTest and GPT review remain separate gates: this does not certify aesthetics.
"""
import hashlib
import struct
import zlib

class InvalidArtwork(ValueError):
    pass

def inspect_png(data):
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise InvalidArtwork('PNG signature missing')
    offset = 8
    chunks = []
    while offset < len(data):
        if offset + 12 > len(data):
            raise InvalidArtwork('Truncated chunk')
        size, kind = struct.unpack_from('>I4s', data, offset)
        if size > 64 * 1024 * 1024 or offset + size + 12 > len(data):
            raise InvalidArtwork('Chunk size exceeds file or budget')
        payload = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from('>I', data, offset + 8 + size)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise InvalidArtwork('CRC mismatch: ' + kind.decode('ascii', errors='replace'))
        chunks.append((kind, payload)); offset += size + 12
        if kind == b'IEND':
            if payload or offset != len(data):
                raise InvalidArtwork('Invalid IEND or trailing data')
            break
    kinds = [k for k, _ in chunks]
    if not kinds or kinds[0] != b'IHDR' or kinds[-1] != b'IEND' or kinds.count(b'IHDR') != 1:
        raise InvalidArtwork('Invalid PNG chunk sequence')
    if len(chunks[0][1]) != 13:
        raise InvalidArtwork('Invalid IHDR')
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', chunks[0][1])
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
    depths = {0: (1,2,4,8,16), 2: (8,16), 3: (1,2,4,8), 4: (8,16), 6: (8,16)}
    if not channels or depth not in depths[color] or compression or filtering or interlace not in (0,1):
        raise InvalidArtwork('Unsupported PNG header')
    if not width or not height or width * height > 40_000_000:
        raise InvalidArtwork('Invalid dimensions or decoded pixel budget exceeded')
    idat = [i for i, k in enumerate(kinds) if k == b'IDAT']
    if not idat or idat != list(range(idat[0], idat[-1] + 1)):
        raise InvalidArtwork('Missing or non-contiguous IDAT')
    if color == 3 and (b'PLTE' not in kinds or kinds.index(b'PLTE') > idat[0]):
        raise InvalidArtwork('Indexed PNG lacks preceding palette')
    # Include all Adam7 pass scanline headers in the exact decoded bound.
    passes = [(0,0,1,1)] if interlace == 0 else [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
    shapes = []
    for x, y, dx, dy in passes:
        w, h = max(0, (width-x+dx-1)//dx), max(0, (height-y+dy-1)//dy)
        if w and h:
            shapes.append(((w * channels * depth + 7)//8, h))
    expected = sum((row + 1) * h for row, h in shapes)
    if expected > 256 * 1024 * 1024:
        raise InvalidArtwork('Decoded byte budget exceeded')
    inflater = zlib.decompressobj()
    try:
        raw = inflater.decompress(b''.join(chunks[i][1] for i in idat), expected + 1)
    except zlib.error as error:
        raise InvalidArtwork('Invalid IDAT compression') from error
    if len(raw) != expected or not inflater.eof or inflater.unused_data or inflater.unconsumed_tail:
        raise InvalidArtwork('IDAT decoded length mismatch or incomplete stream')
    # Undo filters, allowing re-encoded copies to be detected despite different compression/filtering.
    digest = hashlib.sha256(struct.pack('>IIBBB', width, height, depth, color, interlace))
    for kind, payload in chunks:
        if kind in (b'PLTE', b'tRNS'):
            digest.update(kind + payload)
    cursor = 0; bpp = max(1, (channels * depth + 7)//8)
    for row_size, rows in shapes:
        previous = bytearray(row_size)
        for _ in range(rows):
            mode = raw[cursor]; row = bytearray(raw[cursor+1:cursor+1+row_size]); cursor += row_size + 1
            if mode > 4:
                raise InvalidArtwork('Invalid scanline filter')
            for i in range(row_size):
                left = row[i-bpp] if i >= bpp else 0
                up = previous[i]; corner = previous[i-bpp] if i >= bpp else 0
                if mode == 1: predictor = left
                elif mode == 2: predictor = up
                elif mode == 3: predictor = (left + up)//2
                elif mode == 4:
                    p = left + up - corner
                    distances = (abs(p-left), abs(p-up), abs(p-corner))
                    predictor = (left,up,corner)[distances.index(min(distances))]
                else: predictor = 0
                row[i] = (row[i] + predictor) & 255
            digest.update(row); previous = row
    profile = 'sRGB' if b'sRGB' in kinds else ('ICC_REQUIRES_REVIEW' if b'iCCP' in kinds else 'UNSPECIFIED_REQUIRES_REVIEW')
    return dict(pixels=[width,height], alphaChannel=color in (4,6) or b'tRNS' in kinds,
                colorProfile=profile, pixelSHA256=digest.hexdigest(), containerCRC=True, scanlines=True)
