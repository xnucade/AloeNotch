import Foundation
import CoreLocation
import Combine

struct WeatherSnapshot: Equatable {
    var temperatureC: Double
    var symbolName: String
    var summary: String

    /// Localized temperature in the user's preferred unit ("72°" / "22°").
    var temperatureText: String {
        Measurement(value: temperatureC, unit: UnitTemperature.celsius)
            .formatted(.measurement(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            ))
    }
}

/// Publishes current conditions for the user's location. Uses CoreLocation for
/// a coarse position and the keyless Open-Meteo API for conditions, so it works
/// without a WeatherKit entitlement. When location access is denied the UI
/// simply hides the weather pill.
final class WeatherProvider: NSObject, ObservableObject {
    @Published private(set) var current: WeatherSnapshot?

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var isRunning = false
    private let refreshInterval: TimeInterval = 20 * 60

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        requestLocationIfAuthorized()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.requestLocationIfAuthorized()
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func requestLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break // denied/restricted: weather stays hidden
        }
    }

    // MARK: - Fetch

    private func fetch(latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            else { return }

            let c = response.current
            let (symbol, summary) = Self.condition(for: c.weather_code, isDay: c.is_day == 1)
            let snapshot = WeatherSnapshot(
                temperatureC: c.temperature_2m,
                symbolName: symbol,
                summary: summary
            )
            DispatchQueue.main.async { self?.current = snapshot }
        }.resume()
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    /// Maps WMO weather codes to an SF Symbol + short description.
    private static func condition(for code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0:          return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2:       return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3:          return ("cloud.fill", "Overcast")
        case 45, 48:     return ("cloud.fog.fill", "Fog")
        case 51...57:    return ("cloud.drizzle.fill", "Drizzle")
        case 61...67:    return ("cloud.rain.fill", "Rain")
        case 71...77:    return ("cloud.snow.fill", "Snow")
        case 80...82:    return ("cloud.heavyrain.fill", "Showers")
        case 85, 86:     return ("cloud.snow.fill", "Snow showers")
        case 95...99:    return ("cloud.bolt.rain.fill", "Thunderstorm")
        default:         return ("cloud.fill", "—")
        }
    }
}

extension WeatherProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, let location = locations.last else { return }
        fetch(latitude: location.coordinate.latitude,
              longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last snapshot; try again on the next timer tick.
    }
}
