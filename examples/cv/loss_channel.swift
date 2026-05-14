import Foundation
import SchroSIM

@main
struct LossChannelExample {
    static func main() throws {
        let circuit = try Circuit(modes: 1)
        circuit.displace(q: 1.0, p: 0.0, on: 0)
        circuit.loss(eta: 0.9, on: 0)

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let result = try Simulator.runAndMeasure(circuit, rng: &rng)

        print("Final mean:", result.finalState.mean)
        print("Final covariance:", result.finalState.cov)
        print("Measurement events:", result.measurements.count)
    }
}
