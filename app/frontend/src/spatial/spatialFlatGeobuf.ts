export interface DecodedFlatGeobufPlot {
  plotNumber: string;
  lat: number;
  lon: number;
  utmDerivedLat: number | null;
  utmDerivedLon: number | null;
  divergenceMeters: number | null;
  elevation: number | null;
  slope: number | null;
  aspect: number | null;
  fieldBgc: string;
  gisBgc: string;
  bgcMismatch: boolean;
  siteUnit: string;
}

export const FLATGEOBUF_MAGIC_V3 = new Uint8Array([0x66, 0x67, 0x62, 0x03, 0x66, 0x67, 0x62, 0x01]);

const BASE64_LOOKUP = (() => {
  const table = new Int16Array(128).fill(-1);
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  for (let i = 0; i < alphabet.length; i++) {
    table[alphabet.charCodeAt(i)] = i;
  }
  table['-'.charCodeAt(0)] = 62;
  table['_'.charCodeAt(0)] = 63;
  return table;
})();

function decodeBase64Pure(raw: string): Uint8Array {
  const cleaned = raw.replace(/[\r\n\s=]+/g, '');
  const outLen = Math.floor((cleaned.length * 3) / 4);
  const out = new Uint8Array(outLen);
  let outIdx = 0;
  let acc = 0;
  let bits = 0;
  for (let i = 0; i < cleaned.length; i++) {
    const code = cleaned.charCodeAt(i);
    const val = code < 128 ? BASE64_LOOKUP[code] : -1;
    if (val < 0) continue;
    acc = (acc << 6) | val;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[outIdx++] = (acc >> bits) & 0xff;
    }
  }
  return outIdx === outLen ? out : out.subarray(0, outIdx);
}

function decodeUTF8Slice(bytes: Uint8Array): string {
  if (typeof TextDecoder !== 'undefined') {
    return new TextDecoder('utf-8').decode(bytes);
  }
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i++];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
    } else if ((b0 & 0xe0) === 0xc0 && i < bytes.length) {
      const b1 = bytes[i++] & 0x3f;
      out += String.fromCharCode(((b0 & 0x1f) << 6) | b1);
    } else if ((b0 & 0xf0) === 0xe0 && i + 1 < bytes.length) {
      const b1 = bytes[i++] & 0x3f;
      const b2 = bytes[i++] & 0x3f;
      out += String.fromCharCode(((b0 & 0x0f) << 12) | (b1 << 6) | b2);
    } else if ((b0 & 0xf8) === 0xf0 && i + 2 < bytes.length) {
      const b1 = bytes[i++] & 0x3f;
      const b2 = bytes[i++] & 0x3f;
      const b3 = bytes[i++] & 0x3f;
      const cp = ((b0 & 0x07) << 18) | (b1 << 12) | (b2 << 6) | b3;
      out += String.fromCodePoint(cp);
    }
  }
  return out;
}

function toUint8Array(input: Uint8Array | ArrayBuffer | string | null | undefined): Uint8Array {
  if (!input) return new Uint8Array(0);
  if (input instanceof Uint8Array) return input;
  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  }
  if (input instanceof ArrayBuffer || Object.prototype.toString.call(input) === '[object ArrayBuffer]') {
    return new Uint8Array(input as ArrayBuffer);
  }
  if (typeof input === 'string') {
    return decodeBase64Pure(input);
  }
  return new Uint8Array(0);
}

function fbFieldPos(dv: DataView, tablePos: number, fieldIdx: number): number | null {
  if (tablePos < 0 || tablePos + 4 > dv.byteLength) return null;
  const soffset = dv.getInt32(tablePos, true);
  const vtPos = tablePos - soffset;
  if (vtPos < 0 || vtPos + 4 > dv.byteLength) return null;
  const vtLen = dv.getUint16(vtPos, true);
  const slotOff = 4 + 2 * fieldIdx;
  if (slotOff + 2 > vtLen || vtPos + slotOff + 2 > dv.byteLength) return null;
  const rel = dv.getUint16(vtPos + slotOff, true);
  if (rel === 0 || tablePos + rel > dv.byteLength) return null;
  return tablePos + rel;
}

function fbDeref(dv: DataView, slotPos: number): number | null {
  if (slotPos < 0 || slotPos + 4 > dv.byteLength) return null;
  const target = slotPos + dv.getUint32(slotPos, true);
  return target >= 0 && target <= dv.byteLength ? target : null;
}

function fbReadString(dv: DataView, bytes: Uint8Array, slotPos: number): string {
  const strPos = fbDeref(dv, slotPos);
  if (strPos === null || strPos + 4 > dv.byteLength) return '';
  const len = dv.getUint32(strPos, true);
  if (strPos + 4 + len > dv.byteLength) return '';
  return decodeUTF8Slice(bytes.subarray(strPos + 4, strPos + 4 + len));
}

/**
 * Decodes an OGC FlatGeobuf v3 binary buffer (or Wails base64 string) into plot point records.
 */
export function decodeFlatGeobufPoints(
  input: Uint8Array | ArrayBuffer | string | null | undefined
): DecodedFlatGeobufPlot[] {
  const bytes = toUint8Array(input);
  if (bytes.byteLength === 0) return [];
  if (bytes.byteLength < 12) {
    throw new Error('FlatGeobuf buffer shorter than 12-byte magic + header prefix');
  }
  for (let i = 0; i < 8; i++) {
    if (bytes[i] !== FLATGEOBUF_MAGIC_V3[i]) {
      throw new Error('Invalid OGC FlatGeobuf v3 magic signature');
    }
  }

  const fullDV = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let pos = 8;
  const hdrLen = fullDV.getUint32(pos, true);
  pos += 4;
  if (hdrLen < 8 || pos + hdrLen > bytes.byteLength) {
    throw new Error('FlatGeobuf header size exceeds buffer bounds');
  }

  const hdrBytes = bytes.subarray(pos, pos + hdrLen);
  const hdrDV = new DataView(hdrBytes.buffer, hdrBytes.byteOffset, hdrBytes.byteLength);
  pos += hdrLen;

  const hdrRoot = fbDeref(hdrDV, 0);
  if (hdrRoot === null) {
    throw new Error('Invalid FlatGeobuf header root offset');
  }

  const colDefs: Array<{ name: string; colType: number }> = [];
  const colsSlot = fbFieldPos(hdrDV, hdrRoot, 7);
  if (colsSlot !== null) {
    const colsVec = fbDeref(hdrDV, colsSlot);
    if (colsVec !== null && colsVec + 4 <= hdrDV.byteLength) {
      const nCols = hdrDV.getUint32(colsVec, true);
      for (let i = 0; i < nCols; i++) {
        const elemSlot = colsVec + 4 + i * 4;
        const colTbl = fbDeref(hdrDV, elemSlot);
        if (colTbl === null) throw new Error('Invalid FlatGeobuf column table offset');
        const nameSlot = fbFieldPos(hdrDV, colTbl, 0);
        const typeSlot = fbFieldPos(hdrDV, colTbl, 1);
        colDefs.push({
          name: nameSlot !== null ? fbReadString(hdrDV, hdrBytes, nameSlot) : '',
          colType: typeSlot !== null ? hdrDV.getUint8(typeSlot) : 0,
        });
      }
    }
  }

  const out: DecodedFlatGeobufPlot[] = [];
  while (pos < bytes.byteLength) {
    if (pos + 4 > bytes.byteLength) {
      throw new Error('Truncated FlatGeobuf feature size prefix');
    }
    const fLen = fullDV.getUint32(pos, true);
    pos += 4;
    if (fLen < 4 || pos + fLen > bytes.byteLength) {
      throw new Error('FlatGeobuf feature size exceeds buffer bounds');
    }
    const fBytes = bytes.subarray(pos, pos + fLen);
    const fDV = new DataView(fBytes.buffer, fBytes.byteOffset, fBytes.byteLength);
    pos += fLen;

    const fRoot = fbDeref(fDV, 0);
    if (fRoot === null) throw new Error('Invalid FlatGeobuf feature root offset');

    const rec: DecodedFlatGeobufPlot = {
      plotNumber: '',
      lat: 0,
      lon: 0,
      utmDerivedLat: null,
      utmDerivedLon: null,
      divergenceMeters: null,
      elevation: null,
      slope: null,
      aspect: null,
      fieldBgc: '',
      gisBgc: '',
      bgcMismatch: false,
      siteUnit: '',
    };

    const geomSlot = fbFieldPos(fDV, fRoot, 0);
    if (geomSlot !== null) {
      const geomTbl = fbDeref(fDV, geomSlot);
      if (geomTbl !== null) {
        const xySlot = fbFieldPos(fDV, geomTbl, 1);
        if (xySlot !== null) {
          const xyVec = fbDeref(fDV, xySlot);
          if (xyVec !== null && xyVec + 20 <= fDV.byteLength) {
            const nCoords = fDV.getUint32(xyVec, true);
            if (nCoords >= 2) {
              rec.lon = fDV.getFloat64(xyVec + 4, true);
              rec.lat = fDV.getFloat64(xyVec + 12, true);
            }
          }
        }
      }
    }

    const propSlot = fbFieldPos(fDV, fRoot, 1);
    if (propSlot !== null) {
      const propVec = fbDeref(fDV, propSlot);
      if (propVec !== null && propVec + 4 <= fDV.byteLength) {
        const pLen = fDV.getUint32(propVec, true);
        if (propVec + 4 + pLen <= fDV.byteLength) {
          const pSub = fBytes.subarray(propVec + 4, propVec + 4 + pLen);
          const pDV = new DataView(pSub.buffer, pSub.byteOffset, pSub.byteLength);
          let pIdx = 0;
          while (pIdx + 2 <= pSub.byteLength) {
            const colIdx = pDV.getUint16(pIdx, true);
            pIdx += 2;
            const col = colDefs[colIdx];
            if (!col) break;
            if (col.colType === 11) {
              if (pIdx + 4 > pSub.byteLength) break;
              const sLen = pDV.getUint32(pIdx, true);
              pIdx += 4;
              if (pIdx + sLen > pSub.byteLength) break;
              const sv = decodeUTF8Slice(pSub.subarray(pIdx, pIdx + sLen));
              pIdx += sLen;
              if (col.name === 'PlotNumber') rec.plotNumber = sv;
              else if (col.name === 'FieldBGC') rec.fieldBgc = sv;
              else if (col.name === 'GIS_BGC') rec.gisBgc = sv;
              else if (col.name === 'SiteUnit') rec.siteUnit = sv;
            } else if (col.colType === 8) {
              if (pIdx + 8 > pSub.byteLength) break;
              const dv = pDV.getFloat64(pIdx, true);
              pIdx += 8;
              if (col.name === 'Lat') rec.lat = dv;
              else if (col.name === 'Lon') rec.lon = dv;
              else if (col.name === 'UTMDerivedLat') rec.utmDerivedLat = dv;
              else if (col.name === 'UTMDerivedLon') rec.utmDerivedLon = dv;
              else if (col.name === 'DivergenceMeters') rec.divergenceMeters = dv;
              else if (col.name === 'Elevation') rec.elevation = dv;
              else if (col.name === 'Slope') rec.slope = dv;
              else if (col.name === 'Aspect') rec.aspect = dv;
            } else if (col.colType === 5) {
              if (pIdx + 1 > pSub.byteLength) break;
              const bv = pDV.getUint8(pIdx) !== 0;
              pIdx += 1;
              if (col.name === 'BGCMismatch') rec.bgcMismatch = bv;
            } else {
              break;
            }
          }
        }
      }
    }

    out.push(rec);
  }

  return out;
}

/**
 * Even-odd Jordan curve ray-casting test for an EPSG:4326 [lon, lat] polygon ring.
 */
export function pointInPolygonRing(lon: number, lat: number, ring: ReadonlyArray<readonly [number, number]>): boolean {
  if (!Number.isFinite(lon) || !Number.isFinite(lat) || ring.length < 3) {
    return false;
  }
  const effectiveLen =
    ring.length >= 4 && ring[ring.length - 1][0] === ring[0][0] && ring[ring.length - 1][1] === ring[0][1]
      ? ring.length - 1
      : ring.length;
  if (effectiveLen < 3) return false;

  let inside = false;
  let j = effectiveLen - 1;
  for (let i = 0; i < effectiveLen; i++) {
    const xi = ring[i][0];
    const yi = ring[i][1];
    const xj = ring[j][0];
    const yj = ring[j][1];
    if (yi > lat !== yj > lat && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}
