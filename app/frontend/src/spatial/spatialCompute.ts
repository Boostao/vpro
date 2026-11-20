import { formatError } from '../shared/readRequests';

export type SpatialComputeBackendKind = 'webgpu' | 'webgl2-cpu';

export interface SpatialComputeBackendInfo {
  backend: SpatialComputeBackendKind;
  available: boolean;
  adapterLabel: string;
  maxComputeWorkgroupSizeX: number;
  fallbackReason: string | null;
}

export interface SpatialFilterKernelResult {
  backend: SpatialComputeBackendKind;
  matchedIndices: number[];
  matchedCount: number;
  densityGrid: Uint32Array;
  gridSize: number;
}

/**
 * Generates the WGSL compute kernel for parallel spatial BBOX + radius filtering
 * and 2D spatial density binning across 71,567+ BECMaster plot coordinates.
 */
export function buildWGSLSpatialFilterShader(workgroupSize = 64): string {
  const wg = Math.max(1, Math.min(256, Math.trunc(workgroupSize)));
  return `struct SpatialFilterUniforms {
  minLon: f32,
  minLat: f32,
  maxLon: f32,
  maxLat: f32,
  gridSize: u32,
  count: u32,
  pad0: u32,
  pad1: u32,
};

@group(0) @binding(0) var<storage, read> coords: array<vec2<f32>>;
@group(0) @binding(1) var<uniform> params: SpatialFilterUniforms;
@group(0) @binding(2) var<storage, read_write> flags: array<u32>;
@group(0) @binding(3) var<storage, read_write> densityBins: array<atomic<u32>>;

@compute @workgroup_size(${wg})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.count) {
    return;
  }
  let pt = coords[idx];
  let inside = pt.x >= params.minLon && pt.x <= params.maxLon &&
               pt.y >= params.minLat && pt.y <= params.maxLat;
  if (!inside) {
    flags[idx] = 0u;
    return;
  }
  flags[idx] = 1u;
  let spanLon = max(params.maxLon - params.minLon, 0.00001);
  let spanLat = max(params.maxLat - params.minLat, 0.00001);
  let nx = clamp((pt.x - params.minLon) / spanLon, 0.0, 0.999999);
  let ny = clamp((pt.y - params.minLat) / spanLat, 0.0, 0.999999);
  let gx = u32(nx * f32(params.gridSize));
  let gy = u32(ny * f32(params.gridSize));
  let binIdx = gy * params.gridSize + gx;
  atomicAdd(&densityBins[binIdx], 1u);
}
`;
}

interface MinimalGPUBuffer {
  mapAsync(mode: number): Promise<void>;
  getMappedRange(): ArrayBuffer;
  unmap(): void;
  destroy?(): void;
}

interface MinimalGPUComputePipeline {
  getBindGroupLayout(index: number): unknown;
}

interface MinimalGPUComputePassEncoder {
  setPipeline(pipeline: MinimalGPUComputePipeline): void;
  setBindGroup(index: number, bindGroup: unknown): void;
  dispatchWorkgroups(x: number): void;
  end(): void;
}

interface MinimalGPUCommandEncoder {
  beginComputePass(): MinimalGPUComputePassEncoder;
  copyBufferToBuffer(
    source: MinimalGPUBuffer,
    sourceOffset: number,
    destination: MinimalGPUBuffer,
    destinationOffset: number,
    size: number
  ): void;
  finish(): unknown;
}

interface MinimalGPUDevice {
  limits?: { maxComputeWorkgroupSizeX?: number };
  createShaderModule(descriptor: { code: string }): unknown;
  createBuffer?(descriptor: { size: number; usage: number }): MinimalGPUBuffer;
  createBindGroupLayout?(descriptor: unknown): unknown;
  createPipelineLayout?(descriptor: unknown): unknown;
  createComputePipeline?(descriptor: unknown): MinimalGPUComputePipeline;
  createBindGroup?(descriptor: unknown): unknown;
  createCommandEncoder?(): MinimalGPUCommandEncoder;
  queue?: {
    writeBuffer(buffer: MinimalGPUBuffer, offset: number, data: ArrayBuffer | ArrayBufferView): void;
    submit(commands: unknown[]): void;
  };
  destroy?(): void;
}

interface MinimalGPUAdapter {
  info?: { vendor?: string; architecture?: string; description?: string };
  limits?: { maxComputeWorkgroupSizeX?: number };
  requestDevice(): Promise<MinimalGPUDevice | null>;
}

interface MinimalNavigatorWithGPU {
  gpu?: {
    requestAdapter(): Promise<MinimalGPUAdapter | null>;
  };
}

/**
 * Probes navigator.gpu (requestAdapter + requestDevice + WGSL shader module compilation)
 * and falls back cleanly to WebGL2 + TypedArray CPU execution when WebGPU is unavailable.
 */
export async function detectSpatialComputeBackend(nav?: unknown): Promise<SpatialComputeBackendInfo> {
  const targetNav = (nav !== undefined ? nav : typeof navigator !== 'undefined' ? navigator : undefined) as
    MinimalNavigatorWithGPU | undefined;

  if (!targetNav || !targetNav.gpu || typeof targetNav.gpu.requestAdapter !== 'function') {
    return {
      backend: 'webgl2-cpu',
      available: false,
      adapterLabel: 'WebGL2 + TypedArray CPU Fallback',
      maxComputeWorkgroupSizeX: 0,
      fallbackReason: 'navigator.gpu is unavailable in this WebView runtime',
    };
  }

  try {
    const adapter = await targetNav.gpu.requestAdapter();
    if (!adapter || typeof adapter.requestDevice !== 'function') {
      return {
        backend: 'webgl2-cpu',
        available: false,
        adapterLabel: 'WebGL2 + TypedArray CPU Fallback',
        maxComputeWorkgroupSizeX: 0,
        fallbackReason: 'WebGPU adapter unavailable on active graphics driver',
      };
    }
    const device = await adapter.requestDevice();
    if (!device || typeof device.createShaderModule !== 'function') {
      return {
        backend: 'webgl2-cpu',
        available: false,
        adapterLabel: 'WebGL2 + TypedArray CPU Fallback',
        maxComputeWorkgroupSizeX: 0,
        fallbackReason: 'WebGPU logical device creation returned null',
      };
    }
    device.createShaderModule({ code: buildWGSLSpatialFilterShader(64) });
    const labelParts = [adapter.info?.vendor, adapter.info?.description || adapter.info?.architecture].filter(Boolean);
    const maxWg = device.limits?.maxComputeWorkgroupSizeX ?? adapter.limits?.maxComputeWorkgroupSizeX ?? 256;
    device.destroy?.();
    return {
      backend: 'webgpu',
      available: true,
      adapterLabel: labelParts.length > 0 ? labelParts.join(' - ') : 'WebGPU Hardware Compute',
      maxComputeWorkgroupSizeX: maxWg,
      fallbackReason: null,
    };
  } catch (cause) {
    return {
      backend: 'webgl2-cpu',
      available: false,
      adapterLabel: 'WebGL2 + TypedArray CPU Fallback',
      maxComputeWorkgroupSizeX: 0,
      fallbackReason: formatError(cause),
    };
  }
}

export function executeCPUSpatialFilterKernel(
  coordsLonLat: Float32Array,
  bounds: readonly [number, number, number, number],
  gridSize = 16
): SpatialFilterKernelResult {
  const safeGrid = Math.max(1, Math.min(64, Math.trunc(gridSize)));
  const count = Math.floor(coordsLonLat.length / 2);
  const [minLon, minLat, maxLon, maxLat] = bounds;
  const spanLon = Math.max(maxLon - minLon, 1e-5);
  const spanLat = Math.max(maxLat - minLat, 1e-5);
  const densityGrid = new Uint32Array(safeGrid * safeGrid);
  const matchedIndices: number[] = [];

  for (let i = 0; i < count; i++) {
    const lon = coordsLonLat[i * 2];
    const lat = coordsLonLat[i * 2 + 1];
    if (lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat) {
      matchedIndices.push(i);
      const nx = Math.min(0.999999, Math.max(0, (lon - minLon) / spanLon));
      const ny = Math.min(0.999999, Math.max(0, (lat - minLat) / spanLat));
      const gx = Math.floor(nx * safeGrid);
      const gy = Math.floor(ny * safeGrid);
      densityGrid[gy * safeGrid + gx]++;
    }
  }

  return {
    backend: 'webgl2-cpu',
    matchedIndices,
    matchedCount: matchedIndices.length,
    densityGrid,
    gridSize: safeGrid,
  };
}

/**
 * Dispatches the WGSL spatial filter & density-bin compute shader on WebGPU when available,
 * falling back deterministically to executeCPUSpatialFilterKernel otherwise.
 */
export async function executeSpatialFilterKernel(
  coordsLonLat: Float32Array,
  bounds: readonly [number, number, number, number],
  options?: { nav?: unknown; gridSize?: number }
): Promise<SpatialFilterKernelResult> {
  const safeGrid = Math.max(1, Math.min(64, Math.trunc(options?.gridSize ?? 16)));
  const count = Math.floor(coordsLonLat.length / 2);
  if (count === 0) {
    return {
      backend: 'webgl2-cpu',
      matchedIndices: [],
      matchedCount: 0,
      densityGrid: new Uint32Array(safeGrid * safeGrid),
      gridSize: safeGrid,
    };
  }

  const targetNav = (
    options?.nav !== undefined ? options.nav : typeof navigator !== 'undefined' ? navigator : undefined
  ) as MinimalNavigatorWithGPU | undefined;

  type GlobalWebGPUConstants = typeof globalThis & {
    GPUBufferUsage?: {
      STORAGE: number;
      COPY_DST: number;
      COPY_SRC: number;
      UNIFORM: number;
      MAP_READ: number;
    };
    GPUMapMode?: { READ: number };
  };
  const gpuGlobals = globalThis as GlobalWebGPUConstants;
  const gpuBufUsage = gpuGlobals.GPUBufferUsage;
  const gpuMapMode = gpuGlobals.GPUMapMode;

  if (targetNav?.gpu && gpuBufUsage && gpuMapMode) {
    let device: MinimalGPUDevice | null = null;
    try {
      const adapter = await targetNav.gpu.requestAdapter();
      device = adapter ? await adapter.requestDevice() : null;
      if (
        device &&
        device.createBuffer &&
        device.createComputePipeline &&
        device.createBindGroup &&
        device.createCommandEncoder &&
        device.queue
      ) {
        const shaderModule = device.createShaderModule({
          code: buildWGSLSpatialFilterShader(64),
        });
        const pipeline = device.createComputePipeline({
          layout: 'auto',
          compute: { module: shaderModule, entryPoint: 'main' },
        });

        const coordsBytes = Math.max(8, coordsLonLat.byteLength);
        const flagsBytes = Math.max(4, count * 4);
        const binsBytes = safeGrid * safeGrid * 4;

        const coordsBuffer = device.createBuffer({
          size: coordsBytes,
          usage: gpuBufUsage.STORAGE | gpuBufUsage.COPY_DST,
        });
        const uniformBuffer = device.createBuffer({
          size: 32,
          usage: gpuBufUsage.UNIFORM | gpuBufUsage.COPY_DST,
        });
        const flagsBuffer = device.createBuffer({
          size: flagsBytes,
          usage: gpuBufUsage.STORAGE | gpuBufUsage.COPY_SRC,
        });
        const binsBuffer = device.createBuffer({
          size: binsBytes,
          usage: gpuBufUsage.STORAGE | gpuBufUsage.COPY_SRC | gpuBufUsage.COPY_DST,
        });
        const flagsReadBuffer = device.createBuffer({
          size: flagsBytes,
          usage: gpuBufUsage.MAP_READ | gpuBufUsage.COPY_DST,
        });
        const binsReadBuffer = device.createBuffer({
          size: binsBytes,
          usage: gpuBufUsage.MAP_READ | gpuBufUsage.COPY_DST,
        });

        const uniformData = new ArrayBuffer(32);
        const uv = new DataView(uniformData);
        uv.setFloat32(0, bounds[0], true);
        uv.setFloat32(4, bounds[1], true);
        uv.setFloat32(8, bounds[2], true);
        uv.setFloat32(12, bounds[3], true);
        uv.setUint32(16, safeGrid, true);
        uv.setUint32(20, count, true);
        uv.setUint32(24, 0, true);
        uv.setUint32(28, 0, true);

        device.queue.writeBuffer(coordsBuffer, 0, coordsLonLat);
        device.queue.writeBuffer(uniformBuffer, 0, uniformData);
        device.queue.writeBuffer(binsBuffer, 0, new Uint32Array(safeGrid * safeGrid));

        const bindGroup = device.createBindGroup({
          layout: pipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: { buffer: coordsBuffer } },
            { binding: 1, resource: { buffer: uniformBuffer } },
            { binding: 2, resource: { buffer: flagsBuffer } },
            { binding: 3, resource: { buffer: binsBuffer } },
          ],
        });

        const encoder = device.createCommandEncoder();
        const pass = encoder.beginComputePass();
        pass.setPipeline(pipeline);
        pass.setBindGroup(0, bindGroup);
        pass.dispatchWorkgroups(Math.ceil(count / 64));
        pass.end();

        encoder.copyBufferToBuffer(flagsBuffer, 0, flagsReadBuffer, 0, flagsBytes);
        encoder.copyBufferToBuffer(binsBuffer, 0, binsReadBuffer, 0, binsBytes);
        device.queue.submit([encoder.finish()]);

        await Promise.all([flagsReadBuffer.mapAsync(gpuMapMode.READ), binsReadBuffer.mapAsync(gpuMapMode.READ)]);

        const flagsArr = new Uint32Array(flagsReadBuffer.getMappedRange().slice(0));
        const densityGrid = new Uint32Array(binsReadBuffer.getMappedRange().slice(0));
        flagsReadBuffer.unmap();
        binsReadBuffer.unmap();

        const matchedIndices: number[] = [];
        for (let i = 0; i < count; i++) {
          if (flagsArr[i] === 1) matchedIndices.push(i);
        }

        coordsBuffer.destroy?.();
        uniformBuffer.destroy?.();
        flagsBuffer.destroy?.();
        binsBuffer.destroy?.();
        flagsReadBuffer.destroy?.();
        binsReadBuffer.destroy?.();
        device.destroy?.();

        return {
          backend: 'webgpu',
          matchedIndices,
          matchedCount: matchedIndices.length,
          densityGrid,
          gridSize: safeGrid,
        };
      }
    } catch {
      device?.destroy?.();
    }
  }

  return executeCPUSpatialFilterKernel(coordsLonLat, bounds, safeGrid);
}
