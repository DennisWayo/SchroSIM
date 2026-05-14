import Foundation

#if canImport(Metal) && canImport(MetalPerformanceShaders)
import Metal
import MetalPerformanceShaders

enum MetalLinearAlgebra {
    static func matmul(_ a: Mat, _ b: Mat) -> Mat? {
        guard let engine = Engine.shared else { return nil }
        guard !a.isEmpty, !b.isEmpty else { return nil }

        let rowsA = a.count
        let colsA = a[0].count
        let rowsB = b.count
        let colsB = b[0].count
        guard rowsB == colsA else { return nil }

        var flatA = flattenMatrix(a, rows: rowsA, cols: colsA)
        var flatB = flattenMatrix(b, rows: rowsB, cols: colsB)
        var flatC = Array(repeating: Float(0), count: rowsA * colsB)

        guard let bufferA = engine.device.makeBuffer(
            bytes: &flatA,
            length: flatA.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }
        guard let bufferB = engine.device.makeBuffer(
            bytes: &flatB,
            length: flatB.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }
        guard let bufferC = engine.device.makeBuffer(
            bytes: &flatC,
            length: flatC.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }

        let descA = MPSMatrixDescriptor(
            rows: rowsA,
            columns: colsA,
            rowBytes: colsA * MemoryLayout<Float>.stride,
            dataType: .float32
        )
        let descB = MPSMatrixDescriptor(
            rows: rowsB,
            columns: colsB,
            rowBytes: colsB * MemoryLayout<Float>.stride,
            dataType: .float32
        )
        let descC = MPSMatrixDescriptor(
            rows: rowsA,
            columns: colsB,
            rowBytes: colsB * MemoryLayout<Float>.stride,
            dataType: .float32
        )

        let matrixA = MPSMatrix(buffer: bufferA, descriptor: descA)
        let matrixB = MPSMatrix(buffer: bufferB, descriptor: descB)
        let matrixC = MPSMatrix(buffer: bufferC, descriptor: descC)

        guard let commandBuffer = engine.queue.makeCommandBuffer() else { return nil }
        let kernel = MPSMatrixMultiplication(
            device: engine.device,
            transposeLeft: false,
            transposeRight: false,
            resultRows: rowsA,
            resultColumns: colsB,
            interiorColumns: colsA,
            alpha: 1.0,
            beta: 0.0
        )
        kernel.encode(commandBuffer: commandBuffer, leftMatrix: matrixA, rightMatrix: matrixB, resultMatrix: matrixC)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        let pointer = bufferC.contents().bindMemory(to: Float.self, capacity: flatC.count)
        var out = LA.zeros(rowsA, colsB)
        for i in 0..<rowsA {
            for j in 0..<colsB {
                out[i][j] = Double(pointer[i * colsB + j])
            }
        }
        return out
    }

    static func matvec(_ a: Mat, _ x: Vec) -> Vec? {
        guard let engine = Engine.shared else { return nil }
        guard !a.isEmpty else { return nil }

        let rows = a.count
        let cols = a[0].count
        guard x.count == cols else { return nil }

        var flatA = flattenMatrix(a, rows: rows, cols: cols)
        var flatX = x.map(Float.init)
        var flatY = Array(repeating: Float(0), count: rows)

        guard let bufferA = engine.device.makeBuffer(
            bytes: &flatA,
            length: flatA.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }
        guard let bufferX = engine.device.makeBuffer(
            bytes: &flatX,
            length: flatX.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }
        guard let bufferY = engine.device.makeBuffer(
            bytes: &flatY,
            length: flatY.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { return nil }

        let matrixDesc = MPSMatrixDescriptor(
            rows: rows,
            columns: cols,
            rowBytes: cols * MemoryLayout<Float>.stride,
            dataType: .float32
        )
        let xDesc = MPSVectorDescriptor(length: cols, dataType: .float32)
        let yDesc = MPSVectorDescriptor(length: rows, dataType: .float32)

        let matrix = MPSMatrix(buffer: bufferA, descriptor: matrixDesc)
        let xVec = MPSVector(buffer: bufferX, descriptor: xDesc)
        let yVec = MPSVector(buffer: bufferY, descriptor: yDesc)

        guard let commandBuffer = engine.queue.makeCommandBuffer() else { return nil }
        let kernel = MPSMatrixVectorMultiplication(
            device: engine.device,
            transpose: false,
            rows: rows,
            columns: cols,
            alpha: 1.0,
            beta: 0.0
        )
        kernel.encode(commandBuffer: commandBuffer, inputMatrix: matrix, inputVector: xVec, resultVector: yVec)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        let pointer = bufferY.contents().bindMemory(to: Float.self, capacity: rows)
        var out = Array(repeating: 0.0, count: rows)
        for i in 0..<rows {
            out[i] = Double(pointer[i])
        }
        return out
    }

    private static func flattenMatrix(_ matrix: Mat, rows: Int, cols: Int) -> [Float] {
        var out = Array(repeating: Float(0), count: rows * cols)
        for i in 0..<rows {
            for j in 0..<cols {
                out[i * cols + j] = Float(matrix[i][j])
            }
        }
        return out
    }

    private final class Engine {
        let device: MTLDevice
        let queue: MTLCommandQueue

        init?(device: MTLDevice) {
            guard let queue = device.makeCommandQueue() else { return nil }
            self.device = device
            self.queue = queue
        }

        static let shared: Engine? = {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            return Engine(device: device)
        }()
    }
}

#else

enum MetalLinearAlgebra {
    static func matmul(_ a: Mat, _ b: Mat) -> Mat? {
        nil
    }

    static func matvec(_ a: Mat, _ x: Vec) -> Vec? {
        nil
    }
}

#endif
