const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// CRC32 table
const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
        if (c & 1) {
            c = 0xedb88320 ^ (c >>> 1);
        } else {
            c = c >>> 1;
        }
    }
    crcTable[n] = c;
}

function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) {
        c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
}

function createChunk(type, data) {
    const len = data.length;
    const buf = Buffer.alloc(12 + len);
    buf.writeUInt32BE(len, 0);
    buf.write(type, 4, 4, 'ascii');
    data.copy(buf, 8);
    const crc = crc32(buf.subarray(4, 8 + len));
    buf.writeUInt32BE(crc, 8 + len);
    return buf;
}

const WIDTH = 1024;
const HEIGHT = 1024;

// RGBA raw buffer: (1 filter byte + WIDTH * 4) * HEIGHT
const rawData = Buffer.alloc((1 + WIDTH * 4) * HEIGHT);

function setPixel(x, y, r, g, b, a = 255) {
    if (x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT) return;
    const rowOffset = y * (1 + WIDTH * 4);
    const pixelOffset = rowOffset + 1 + x * 4;

    // Alpha blending with existing pixel
    const bgA = rawData[pixelOffset + 3] / 255;
    const fgA = a / 255;
    const outA = fgA + bgA * (1 - fgA);
    if (outA <= 0) return;

    const outR = Math.round((r * fgA + rawData[pixelOffset] * bgA * (1 - fgA)) / outA);
    const outG = Math.round((g * fgA + rawData[pixelOffset + 1] * bgA * (1 - fgA)) / outA);
    const outB = Math.round((b * fgA + rawData[pixelOffset + 2] * bgA * (1 - fgA)) / outA);

    rawData[pixelOffset] = outR;
    rawData[pixelOffset + 1] = outG;
    rawData[pixelOffset + 2] = outB;
    rawData[pixelOffset + 3] = Math.round(outA * 255);
}

// 1. Draw smooth gradient background: Vibrant Tech Blue to Cyan (#0F52FF -> #00C6FF)
console.log('Rendering background gradient...');
for (let y = 0; y < HEIGHT; y++) {
    const rowOffset = y * (1 + WIDTH * 4);
    rawData[rowOffset] = 0; // Filter type 0 (None)

    const t = (y + (WIDTH - y) * 0.2) / HEIGHT; // diagonal subtle slant
    // Top-left: #0B41E6 (11, 65, 230)
    // Bottom-right: #00D2FF (0, 210, 255)
    const r = Math.round(11 * (1 - t) + 0 * t);
    const g = Math.round(65 * (1 - t) + 210 * t);
    const b = Math.round(230 * (1 - t) + 255 * t);

    for (let x = 0; x < WIDTH; x++) {
        // Radial subtle lighting in upper center
        const dx = (x - WIDTH * 0.45) / WIDTH;
        const dy = (y - HEIGHT * 0.35) / HEIGHT;
        const dist = Math.sqrt(dx * dx + dy * dy);
        const glow = Math.max(0, 1 - dist * 1.5) * 45;

        const pr = Math.min(255, Math.round(r + glow * 0.4));
        const pg = Math.min(255, Math.round(g + glow * 0.8));
        const pb = Math.min(255, Math.round(b + glow * 1.0));

        setPixel(x, y, pr, pg, pb, 255);
    }
}

// Helper: distance to rounded rectangle
function sdRoundRect(px, py, rx, ry, rw, rh, radius) {
    const cx = rx + rw / 2;
    const cy = ry + rh / 2;
    const qx = Math.abs(px - cx) - (rw / 2 - radius);
    const qy = Math.abs(py - cy) - (rh / 2 - radius);
    const ax = Math.max(qx, 0);
    const ay = Math.max(qy, 0);
    return Math.sqrt(ax * ax + ay * ay) + Math.min(Math.max(qx, qy), 0) - radius;
}

// 2. Draw Soft Glow Shadow behind main icon card
console.log('Rendering shadow and glow...');
const cardW = 540;
const cardH = 720;
const cardX = (WIDTH - cardW) / 2;
const cardY = (HEIGHT - cardH) / 2 + 10;
const cardRadius = 72;

for (let y = 0; y < HEIGHT; y++) {
    for (let x = 0; x < WIDTH; x++) {
        const d = sdRoundRect(x, y, cardX, cardY + 25, cardW, cardH, cardRadius);
        if (d > 0 && d < 60) {
            const shadowAlpha = (1 - d / 60) * 0.45;
            setPixel(x, y, 0, 15, 60, Math.round(shadowAlpha * 255));
        }
    }
}

// 3. Draw Main Device / Long Screenshot Card (Frosted Glass / Pure White with border)
console.log('Rendering long screenshot card...');
for (let y = 0; y < HEIGHT; y++) {
    for (let x = 0; x < WIDTH; x++) {
        const d = sdRoundRect(x, y, cardX, cardY, cardW, cardH, cardRadius);
        if (d <= 0) {
            // Inside card
            // Subtle vertical gradient inside card: white to slight blue tint
            const cyT = (y - cardY) / cardH;
            const cardR = Math.round(255 * (1 - cyT * 0.05));
            const cardG = Math.round(255 * (1 - cyT * 0.03));
            const cardB = 255;
            setPixel(x, y, cardR, cardG, cardB, 255);
        } else if (d < 2.0) {
            // Anti-aliased outer edge
            const alpha = (1 - d / 2.0);
            setPixel(x, y, 255, 255, 255, Math.round(alpha * 255));
        }
    }
}

// 4. Draw Content inside the Long Screenshot Card:
// Top Status Bar Area
console.log('Rendering card elements...');
// Notch / Pill at top
const pillW = 120;
const pillH = 22;
const pillX = (WIDTH - pillW) / 2;
const pillY = cardY + 28;
for (let y = pillY; y < pillY + pillH; y++) {
    for (let x = pillX; x < pillX + pillW; x++) {
        const d = sdRoundRect(x, y, pillX, pillY, pillW, pillH, 11);
        if (d <= 0) setPixel(x, y, 215, 225, 240, 255);
    }
}

// Screen Section 1 (Upper snippet): Chat / List mock items
function drawLine(x1, y1, w, h, r, g, b, a = 255, rad = h / 2) {
    for (let y = Math.floor(y1); y < y1 + h; y++) {
        for (let x = Math.floor(x1); x < x1 + w; x++) {
            const d = sdRoundRect(x, y, x1, y1, w, h, rad);
            if (d <= 0) setPixel(x, y, r, g, b, a);
        }
    }
}

// Draw Mock UI rows
const startX = cardX + 54;
const innerW = cardW - 108;

// Header mock bar
drawLine(startX, cardY + 80, innerW * 0.45, 26, 30, 115, 255, 255, 12);
drawLine(startX + innerW * 0.55, cardY + 84, innerW * 0.45, 18, 220, 230, 245, 255, 9);

// Upper card content
drawLine(startX, cardY + 140, innerW, 64, 242, 246, 255, 255, 16);
drawLine(startX + 20, cardY + 158, 28, 28, 16, 120, 255, 255, 14);
drawLine(startX + 65, cardY + 156, innerW * 0.4, 14, 60, 80, 120, 255, 7);
drawLine(startX + 65, cardY + 178, innerW * 0.65, 12, 180, 195, 220, 255, 6);

drawLine(startX, cardY + 225, innerW, 64, 242, 246, 255, 255, 16);
drawLine(startX + 20, cardY + 243, 28, 28, 0, 195, 255, 255, 14);
drawLine(startX + 65, cardY + 241, innerW * 0.5, 14, 60, 80, 120, 255, 7);
drawLine(startX + 65, cardY + 263, innerW * 0.55, 12, 180, 195, 220, 255, 6);

// 5. THE STITCH SEAM: Dynamic Glowing Stitching Seam in the Middle!
console.log('Rendering stitching seam and effect...');
const seamY = cardY + 360;

// Glowing energetic seam band
for (let y = seamY - 45; y <= seamY + 45; y++) {
    const distY = Math.abs(y - seamY);
    const intensity = Math.max(0, 1 - distY / 45);
    for (let x = cardX + 16; x < cardX + cardW - 16; x++) {
        // Cyan-Blue laser glow
        const glowA = Math.round(intensity * intensity * 70);
        setPixel(x, y, 0, 180, 255, glowA);
    }
}

// Dotted / Dashed Stitch Line
for (let x = cardX + 32; x < cardX + cardW - 32; x++) {
    if ((Math.floor(x / 18)) % 2 === 0) {
        for (let dy = -3; dy <= 3; dy++) {
            setPixel(x, seamY + dy, 0, 122, 255, 255);
        }
    }
}

// Scissors / Stitch connector badges on the seam sides
function drawSparkle(cx, cy, size, r, g, b) {
    for (let dy = -size; dy <= size; dy++) {
        for (let dx = -size; dx <= size; dx++) {
            const d = Math.abs(dx) + Math.abs(dy);
            if (d <= size) {
                const a = Math.round((1 - d / size) * 255);
                setPixel(cx + dx, cy + dy, r, g, b, a);
            }
        }
    }
}

drawSparkle(cardX + 40, seamY, 20, 0, 220, 255);
drawSparkle(cardX + cardW - 40, seamY, 20, 0, 220, 255);

// 6. Lower Content (stitched section extending seamlessly downwards)
drawLine(startX, cardY + 420, innerW, 64, 242, 246, 255, 255, 16);
drawLine(startX + 20, cardY + 438, 28, 28, 16, 120, 255, 255, 14);
drawLine(startX + 65, cardY + 436, innerW * 0.45, 14, 60, 80, 120, 255, 7);
drawLine(startX + 65, cardY + 458, innerW * 0.6, 12, 180, 195, 220, 255, 6);

drawLine(startX, cardY + 505, innerW, 64, 242, 246, 255, 255, 16);
drawLine(startX + 20, cardY + 523, 28, 28, 0, 195, 255, 255, 14);
drawLine(startX + 65, cardY + 521, innerW * 0.55, 14, 60, 80, 120, 255, 7);
drawLine(startX + 65, cardY + 543, innerW * 0.4, 12, 180, 195, 220, 255, 6);

// 7. Dynamic Scroll Indicator Pill on the Right Side
const indW = 72;
const indH = 140;
const indX = cardX + cardW - 60;
const indY = cardY + cardH / 2 - 70;

// Floating indicator shadow
for (let y = indY - 10; y < indY + indH + 20; y++) {
    for (let x = indX - 10; x < indX + indW + 20; x++) {
        const d = sdRoundRect(x, y, indX, indY + 8, indW, indH, indW / 2);
        if (d > 0 && d < 25) {
            setPixel(x, y, 0, 30, 90, Math.round((1 - d / 25) * 110));
        }
    }
}
// Floating indicator body
for (let y = indY; y < indY + indH; y++) {
    for (let x = indX; x < indX + indW; x++) {
        const d = sdRoundRect(x, y, indX, indY, indW, indH, indW / 2);
        if (d <= 0) {
            const yt = (y - indY) / indH;
            setPixel(x, y, Math.round(16 * (1 - yt) + 0 * yt), Math.round(110 * (1 - yt) + 210 * yt), 255, 255);
        } else if (d < 2) {
            setPixel(x, y, 255, 255, 255, Math.round((1 - d / 2) * 255));
        }
    }
}

// Downward scrolling arrow inside floating indicator
const arrowCenterX = indX + indW / 2;
const arrowCenterY = indY + indH / 2;
for (let dy = -28; dy <= 28; dy++) {
    for (let dx = -18; dx <= 18; dx++) {
        const px = arrowCenterX + dx;
        const py = arrowCenterY + dy;
        // Arrow shaft
        if (Math.abs(dx) <= 4 && dy >= -22 && dy <= 10) {
            setPixel(px, py, 255, 255, 255, 255);
        }
        // Arrow head
        const headY = dy - 10;
        if (headY >= 0 && headY <= 16 && Math.abs(dx) <= (16 - headY)) {
            setPixel(px, py, 255, 255, 255, 255);
        }
    }
}

// 8. Bottom Home Indicator Bar
const homeW = 160;
const homeH = 8;
const homeX = (WIDTH - homeW) / 2;
const homeY = cardY + cardH - 24;
for (let y = homeY; y < homeY + homeH; y++) {
    for (let x = homeX; x < homeX + homeW; x++) {
        const d = sdRoundRect(x, y, homeX, homeY, homeW, homeH, 4);
        if (d <= 0) setPixel(x, y, 210, 220, 235, 255);
    }
}

console.log('Compressing PNG image...');
const compressed = zlib.deflateSync(rawData, { level: 9 });

const header = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const ihdrData = Buffer.alloc(13);
ihdrData.writeUInt32BE(WIDTH, 0);
ihdrData.writeUInt32BE(HEIGHT, 4);
ihdrData[8] = 8; // bit depth
ihdrData[9] = 6; // RGBA
ihdrData[10] = 0; // compression
ihdrData[11] = 0; // filter
ihdrData[12] = 0; // interlace
const ihdrChunk = createChunk('IHDR', ihdrData);

const idatChunk = createChunk('IDAT', compressed);
const iendChunk = createChunk('IEND', Buffer.alloc(0));

const finalPng = Buffer.concat([header, ihdrChunk, idatChunk, iendChunk]);

const outPath = path.join(__dirname, 'diypic', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png');
fs.writeFileSync(outPath, finalPng);
console.log('App Icon successfully created at: ' + outPath + ' (' + finalPng.length + ' bytes)');
